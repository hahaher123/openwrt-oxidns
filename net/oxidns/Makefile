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
# The PROCD init script and the /etc/config/oxidns UCI file live in the
# separate "oxidns-service" package so that they never collide with the
# copies shipped by luci-app-oxidns.

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

  Built from source inside the OpenWrt build system. Package layout matches the
  one used by luci-app-oxidns, so the LuCI app can drive this build directly.

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

# --- CLI-only deployment: procd service + UCI ---------------------------------
# Ships exactly the two files that luci-app-oxidns also ships, therefore the
# two packages are mutually exclusive.
define Package/oxidns-service
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=IP Addresses and Names
  TITLE:=OxiDNS procd service and UCI configuration (CLI deployment)
  URL:=https://github.com/svenshi/oxidns
  DEPENDS:=+oxidns
  CONFLICTS:=luci-app-oxidns
endef

define Package/oxidns-service/description
  PROCD init script (/etc/init.d/oxidns) and UCI configuration
  (/etc/config/oxidns) for running OxiDNS without LuCI.

  Do not install this together with luci-app-oxidns: the LuCI app ships the
  same two files, so opkg/apk would report a file conflict. Install either
  "oxidns + oxidns-service" (CLI only) or "oxidns + luci-app-oxidns" (LuCI).
endef

define Package/oxidns-service/conffiles
/etc/config/oxidns
endef

define Package/oxidns-service/install
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/oxidns.init $(1)/etc/init.d/oxidns

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/oxidns.config $(1)/etc/config/oxidns
endef

$(eval $(call BuildPackage,oxidns))
$(eval $(call BuildPackage,oxidns-service))
