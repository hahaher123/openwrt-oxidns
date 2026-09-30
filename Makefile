# SPDX-License-Identifier: GPL-3.0-or-later
#
# OpenWrt package for the OxiDNS core binary.
#
#   Upstream project : https://github.com/svenshi/oxidns   (GPL-3.0-or-later)
#   Companion LuCI   : https://github.com/svenshi/luci-app-oxidns
#
# This Makefile is NOT part of the upstream OxiDNS project and is not
# maintained by it. It exists for one purpose only: cross-compiling OxiDNS
# from source inside an OpenWrt buildroot / SDK.
#
# Layout produced by this package (identical to the paths used by
# luci-app-oxidns and by the official release archives):
#
#   /usr/bin/oxidns                        core binary
#   /etc/oxidns/config.yaml                default configuration
#   /usr/share/oxidns/webui/               WebUI static assets
#
# The WebUI is not built here. Upstream publishes it prebuilt inside every
# release archive (webui/), and that is the artifact the official Docker image,
# the Debian package and install.sh all consume - see
# https://oxidns.org/webui. This Makefile downloads the x86_64 musl archive for
# that one directory. The assets are plain HTML/CSS/JS/fonts with no native
# code, so a single copy is correct for every architecture, and it avoids a
# pnpm/Next.js build inside the buildroot.
#
# The PROCD init script (/etc/init.d/oxidns) and the UCI file
# (/etc/config/oxidns) are deliberately NOT shipped by this package:
# luci-app-oxidns already provides both. Shipping them here would make the two
# packages collide on those paths, so this package only ships the core binary
# and the files that luci-app-oxidns does not provide.

include $(TOPDIR)/rules.mk

PKG_NAME:=oxidns
PKG_VERSION:=1.6.0
PKG_RELEASE:=3

# Upstream publishes no source tarball asset, so we use the GitHub tag
# archive. Top level directory inside the archive is "oxidns-<version>",
# which matches the default PKG_BUILD_DIR.
PKG_SOURCE:=v$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://github.com/svenshi/oxidns/archive/refs/tags
PKG_HASH:=7633d6377082f58a61cd301ed02635fa36ac33a75783ef7647bfa7030c3b33c5

PKG_LICENSE:=GPL-3.0-or-later
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=openwrt-oxidns contributors <libiegou2025@gmail.com>

# The Rust host toolchain is built by feeds/packages/lang/rust.
#
# It must be rust >= 1.95: sysinfo 0.39 (pulled in by the upstream Cargo.lock)
# declares rust-version = "1.95". openwrt-25.12 ships 1.96, openwrt-24.10 only
# 1.94, and release SDKs pin feeds/packages to an older commit still carrying
# 1.94 - see the "Known limitations" section of README.md.
PKG_BUILD_DEPENDS:=rust/host
PKG_BUILD_PARALLEL:=1
PKG_BUILD_FLAGS:=no-mips16

include $(INCLUDE_DIR)/package.mk
include $(TOPDIR)/feeds/packages/lang/rust/rust-package.mk

# --- WebUI assets ------------------------------------------------------------
#
# The WebUI ships prebuilt only inside the release archives, never in the tag
# archive (which carries the unbuilt Next.js sources). We take it from the
# x86_64 musl archive: upstream always publishes that one, and webui/ is
# platform independent. The archive also carries a binary and config.yaml;
# Build/Prepare extracts webui/ only.
#
# Upstream publishes no musl asset for mips/mipsel/mips64/powerpc/loongarch64/
# riscv64, so deriving the archive name from $(ARCH) would break the build on
# those targets. Fetching a single archive for all of them is what the official
# Debian package and Docker image do as well.
#
# Download/... must come after package.mk: download.mk is what defines the
# Download macro.
OXIDNS_WEBUI_ARCHIVE:=oxidns-x86_64-unknown-linux-musl.tar.gz
OXIDNS_WEBUI_URL:=https://github.com/svenshi/oxidns/releases/download/v$(PKG_VERSION)
# Kept as its own variable so scripts/sync-upstream.sh can rewrite exactly this
# line on a version bump without touching PKG_HASH.
OXIDNS_WEBUI_HASH:=185d0c2ff627d0bf6154c3c2df618271d224684219a53712c3b763d5317d8c27

define Download/oxidns-webui
  FILE:=$(OXIDNS_WEBUI_ARCHIVE)
  URL:=$(OXIDNS_WEBUI_URL)
  HASH:=$(OXIDNS_WEBUI_HASH)
endef
$(eval $(call Download,oxidns-webui))

# --- upstream supported architectures (see lang/rust/rust-values.mk) ---------
OXIDNS_ARCH_DEPENDS:=@(aarch64||arm||i386||loongarch64||mips||mips64||mips64el||mipsel||powerpc||powerpc64||riscv64||x86_64)

# --- compile-time feature bundle --------------------------------------------
# OxiDNS ships three bundles (bundles -> granular flags -> optional deps).
# "full" is what the upstream release archives and luci-app-oxidns expect.
OXIDNS_BUNDLE:=full
ifeq ($(CONFIG_OXIDNS_BUNDLE_MINIMAL),y)
  OXIDNS_BUNDLE:=minimal
else ifeq ($(CONFIG_OXIDNS_BUNDLE_STANDARD),y)
  OXIDNS_BUNDLE:=standard
endif

RUST_PKG_FEATURES:=$(OXIDNS_BUNDLE)
OXIDNS_RUST_ARGS:=--no-default-features

define Package/oxidns
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=IP Addresses and Names
  TITLE:=OxiDNS - programmable DNS engine (Rust)
  URL:=https://github.com/svenshi/oxidns
  DEPENDS:=$(OXIDNS_ARCH_DEPENDS) +libgcc
endef

define Package/oxidns/description
  OxiDNS is a high-performance, programmable DNS engine written in Rust, aimed
  at software routers, OpenWrt, homelabs and other advanced self-hosted DNS
  setups. It composes matching, caching, forwarding, fallback, rewriting, local
  answers and system side effects into one declarative, explainable pipeline and
  ships a management API, a WebUI, query records and Prometheus metrics.

  Built from source inside the OpenWrt build system. The package layout is
  exactly the one luci-app-oxidns expects, so the two are meant to be installed
  together:

      apk add oxidns luci-app-oxidns

  luci-app-oxidns supplies the procd service, the UCI configuration and the LuCI
  pages; this package supplies the core binary, its default config and the
  prebuilt WebUI assets.

  Upstream project: https://github.com/svenshi/oxidns
endef

define Package/oxidns/conffiles
/etc/oxidns/config.yaml
endef

# --- prepare -----------------------------------------------------------------
# Default Prepare unpacks the tag archive. The WebUI lives in a second archive,
# so it is extracted next to the sources and installed from there.
#
# The release archive is flat: the entries are LICENSE, config.yaml, oxidns and
# webui/, with no wrapping top-level directory. Listing the member as plain
# `webui` extracts the whole subtree and exits 0.
#
# Do NOT use the tag-archive style patterns here. Measured against the real
# v1.6.0 musl archive:
#   '*/webui' '*/webui/*' (--strip-components=1)  -> rc=2, "Not found in archive"
#     (the */ prefix needs a parent dir, which a flat archive has not got -
#      this is what broke the first v1.6.0-r2 build)
#   --wildcards 'webui' 'webui/*'                 -> rc=2 on 'webui/*'
#     (the second pattern matches no member on its own, and tar treats that as
#      an error, which would fail the build)
#   webui                                         -> rc=0, 92 files, index.html
#
# No --strip-components for the same reason: stripping one component would
# remove the webui/ level itself and scatter index.html and _next/ across
# webui-dist. Only webui/ is kept - the binary next to it is the wrong build
# for a cross-compiled package.
define Build/Prepare
	$(call Build/Prepare/Default)

	rm -rf $(PKG_BUILD_DIR)/webui-dist
	mkdir -p $(PKG_BUILD_DIR)/webui-dist
	$(TAR) -xzf $(DL_DIR)/$(OXIDNS_WEBUI_ARCHIVE) \
		-C $(PKG_BUILD_DIR)/webui-dist webui

	[ -f $(PKG_BUILD_DIR)/webui-dist/webui/index.html ] || { \
		echo "WebUI index.html missing from $(OXIDNS_WEBUI_ARCHIVE)" >&2; \
		exit 1; \
	}
endef

# --- compile -----------------------------------------------------------------
# rust-package.mk defines Build/Compile, but it never passes
# --no-default-features, which would make `minimal` / `standard` add to the
# default `full` bundle instead of replacing it.
define Build/Compile
	$(call Build/Compile/Cargo,,$(OXIDNS_RUST_ARGS))
endef

define Package/oxidns/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/bin/oxidns $(1)/usr/bin/oxidns

	$(INSTALL_DIR) $(1)/etc/oxidns
	$(INSTALL_CONF) ./files/oxidns.yaml $(1)/etc/oxidns/config.yaml

	# WebUI static assets, unpacked in Build/Prepare from the official
	# release archive. CP -fpR keeps the directory tree (Next.js emits
	# nested routes and _next/static/*). Modes are normalised afterwards:
	# the archive only carries whatever the upstream CI runner had, and
	# the package would otherwise ship those modes verbatim.
	$(INSTALL_DIR) $(1)/usr/share/oxidns/webui
	$(CP) $(PKG_BUILD_DIR)/webui-dist/webui/. $(1)/usr/share/oxidns/webui/
	$(FIND) $(1)/usr/share/oxidns/webui -type d -exec chmod 0755 {} +
	$(FIND) $(1)/usr/share/oxidns/webui -type f -exec chmod 0644 {} +
endef

define Package/oxidns/config
	source "$(SOURCE)/Config.in"
endef

$(eval $(call BuildPackage,oxidns))
