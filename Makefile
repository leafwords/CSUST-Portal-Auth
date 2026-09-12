include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-campus-portal
PKG_VERSION:=1.2.0
PKG_RELEASE:=1

PKG_LICENSE:=MIT
PKG_MAINTAINER:=Codex

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-campus-portal
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=Campus ePortal auto login
  PKGARCH:=all
  DEPENDS:=+luci-base +ucode +ucode-mod-fs +curl
endef

define Package/luci-app-campus-portal/description
 Lightweight ePortal campus network auto-login service with automatic WAN IP,
 WAN MAC detection and a LuCI configuration page.
endef

define Package/luci-app-campus-portal/conffiles
/etc/config/campus_portal
endef

define Build/Compile
endef

define Package/luci-app-campus-portal/install
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/etc/config/campus_portal $(1)/etc/config/campus_portal
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/etc/init.d/campus-portal $(1)/etc/init.d/campus-portal
	$(INSTALL_DIR) $(1)/etc/hotplug.d/iface
	$(INSTALL_BIN) ./files/etc/hotplug.d/iface/95-campus-portal $(1)/etc/hotplug.d/iface/95-campus-portal
	$(INSTALL_DIR) $(1)/usr/libexec
	$(INSTALL_BIN) ./files/usr/libexec/campus-portal.uc $(1)/usr/libexec/campus-portal.uc
	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d
	$(INSTALL_DATA) ./files/usr/share/luci/menu.d/luci-app-campus-portal.json $(1)/usr/share/luci/menu.d/luci-app-campus-portal.json
	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) ./files/usr/share/rpcd/acl.d/luci-app-campus-portal.json $(1)/usr/share/rpcd/acl.d/luci-app-campus-portal.json
	$(INSTALL_DIR) $(1)/www/luci-static/resources/view/services
	$(INSTALL_DATA) ./files/www/luci-static/resources/view/services/campus-portal-v2.js $(1)/www/luci-static/resources/view/services/campus-portal-v2.js
endef

$(eval $(call BuildPackage,luci-app-campus-portal))
