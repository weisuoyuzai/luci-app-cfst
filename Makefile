#
# Copyright (C) 2026 luci-app-cfst
#
# This is free software, licensed under the Apache License, Version 2.0
#

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-cfst
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=cfst

LUCI_TITLE:=LuCI support for CloudflareST speedtest & PassWall/PassWall2/OpenClash node auto-apply
LUCI_DESCRIPTION:=Speed test Cloudflare IPs and automatically apply the best IP to PassWall/PassWall2/OpenClash nodes, with scheduling and a web UI.
LUCI_DEPENDS:=+rpcd +jshn
LUCI_PKGARCH:=all

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)

include $(TOPDIR)/feeds/luci/luci.mk

define Package/luci-app-cfst/conffiles
/etc/config/cfst
endef

define Package/luci-app-cfst/postinst
#!/bin/sh
[ -n "$$IPKG_INSTROOT" ] || {
	chmod +x /usr/bin/cfst-run /usr/share/cfst/*.sh /usr/libexec/rpcd/luci.cfst 2>/dev/null
	/etc/init.d/cfst enable
	/etc/init.d/cfst start
	rm -f /tmp/luci-indexcache* 2>/dev/null
	rm -rf /tmp/luci-modulecache/* 2>/dev/null
	killall -HUP rpcd 2>/dev/null
	exit 0
}
exit 0
endef

define Package/luci-app-cfst/postrm
#!/bin/sh
[ -n "$$IPKG_INSTROOT" ] || {
	/etc/init.d/cfst stop
	/etc/init.d/cfst disable
	exit 0
}
exit 0
endef

# call BuildPackage - OpenWrt buildroot signature
$(eval $(call BuildPackage,luci-app-cfst))
