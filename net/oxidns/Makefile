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
#   /usr/bin/oxidns                core binary
#   /etc/oxidns/config.yaml        default configuration
#   /usr/share/oxidns/webui        WebUI asset directory (see README)
#
# The PROCD init script (/etc/init.d/oxidns) and the UCI file
# (/etc/config/oxidns) are deliberately NOT shipped by this package:
# luci-app-oxidns already provides both. Shipping them here would make the two
# packages collide on those paths, so this package only ships the core binary
# and the files that luci-app-oxidns does not provide.

include $(TOPDIR)/rules.mk

PKG_NAME:=oxidns
PKG_VERSION:=1.5.2
PKG_RELEASE:=1

# Upstream publishes no source tarball asset, so we use the GitHub tag
# archive. Top level directory inside the archive is "oxidns-<version>",
# which matches the default PKG_BUILD_DIR.
PKG_SOURCE:=v$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://github.com/svenshi/oxidns/archive/refs/tags
PKG_HASH:=51d2b554926bcd4504115f51a7d93e552c1a9e1252d4617487b2ebc5699775d6

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
  pages; this package only supplies the core binary and its default config.

  Upstream project: https://github.com/svenshi/oxidns
endef

define Package/oxidns/conffiles
/etc/oxidns/config.yaml
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

	# Directory only. The WebUI is a Next.js bundle that is not part of the
	# upstream source tree; see README.md for how to populate it.
	$(INSTALL_DIR) $(1)/usr/share/oxidns/webui
endef

define Package/oxidns/config
	source "$(SOURCE)/Config.in"
endef

$(eval $(call BuildPackage,oxidns))
