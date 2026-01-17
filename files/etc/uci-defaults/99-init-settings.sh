#!/bin/sh

LOG_FILE="/root/setup-xidzswrt.log"
exec > "$LOG_FILE" 2>&1

# variable
SYSTEM_JS="/www/luci-static/resources/view/status/include/10_system.js"
PORTS_JS="/www/luci-static/resources/view/status/include/29_ports.js"
NEW_PORTS_JS="/www/luci-static/resources/view/status/include/11_ports.js"
RELEASE_FILE="/etc/openwrt_release"
TTYD_JSON="/usr/share/luci/menu.d/luci-app-ttyd.json"
TEMP_JS="/www/luci-static/resources/view/status/include/27_temperature.js"
NEW_TEMP_JS="/www/luci-static/resources/view/status/include/15_temperature.js"
XIDZS="/etc/init.d/xidzs"
RC_LOCAL="/etc/rc.local"
CRONTAB_ROOT="/etc/crontabs/root"
USB_MODE="/etc/usb-mode.json"
OPKG_CONF="/etc/opkg.conf"
PROFILE="/etc/profile"
PHP_INI="/etc/php.ini"
PHP_INI_BAK="/etc/php.ini.bak"
VNSTAT_CONF="/etc/vnstat.conf"
INSTALL2_SH="/root/install2.sh"
QUENXX_SH="/root/quenxx.sh"
#ALPHA_CONF="/etc/config/alpha"
ARGON_CONF="/usr/share/ucode/luci/template/themes/argon/header.ut"
#RTA_CONF="/usr/lib/lua/luci/view/themes/rtawrt/header.htm"

echo "$(date)"

# Detect system type
echo "Checking system release..."
if grep -q "ImmortalWrt" /etc/openwrt_release; then
    sed -i 's/\(DISTRIB_DESCRIPTION='\''ImmortalWrt [0-9]*\.[0-9]*\.[0-9]*\).*'\''/\1'\''/g' "$RELEASE_FILE"
    sed -i 's|system/ttyd|services/ttyd|g' "$TTYD_JSON"
    BRANCH_VERSION=$(grep 'DISTRIB_DESCRIPTION=' /etc/openwrt_release | awk -F"'" '{print $2}')
    echo "ImmortalWrt detected: $BRANCH_VERSION"
elif grep -q "OpenWrt" /etc/openwrt_release; then
    sed -i 's/\(DISTRIB_DESCRIPTION='\''OpenWrt [0-9]*\.[0-9]*\.[0-9]*\).*'\''/\1'\''/g' "$RELEASE_FILE"
    mv "$TEMP_JS" "$NEW_TEMP_JS"
    BRANCH_VERSION=$(grep 'DISTRIB_DESCRIPTION=' /etc/openwrt_release | awk -F"'" '{print $2}')
    echo "OpenWrt detected: $BRANCH_VERSION"
else
    echo "Unknown system release"
fi

# package and add custom repo
echo "Disabling OPKG signature checking..."
sed -i 's/option check_signature/# option check_signature/g' "$OPKG_CONF"

echo "Adding custom repository..."
ARCH=$(grep "OPENWRT_ARCH" /etc/os-release | awk -F '"' '{print $2}')
#echo "src/gz custom_packages https://dl.openwrt.ai/latest/packages/$ARCH/kiddin9" >> /etc/opkg/customfeeds.conf

# Basic system
echo "Setting root password..."
(echo "root"; sleep 2; echo "root") | passwd > /dev/null

echo "Configuring hostname and timezone..."
uci batch <<EOF
set system.@system[0].hostname='FREEDOM'
set system.@system[0].timezone='WIB-7'
set system.@system[0].zonename='Asia/Jakarta'
delete system.ntp.server
add_list system.ntp.server='0.id.pool.ntp.org'
add_list system.ntp.server='1.id.pool.ntp.org'
add_list system.ntp.server='2.id.pool.ntp.org'
add_list system.ntp.server='3.id.pool.ntp.org'
add_list system.ntp.server='time.google.com'
commit system
EOF

# language and theme
echo "Setting default language and theme..."
uci batch <<EOF
set luci.@core[0].lang='en'
set luci.main.mediaurlbase='/luci-static/argon'
commit luci
EOF

# network interface
echo "Configuring network interfaces..."
uci batch <<EOF
set network.wan=interface
set network.wan.proto='dhcp'
set network.wan.device='eth1'
set network.tethering=interface
set network.tethering.proto='dhcp'
set network.tethering.device='usb0'
set network.mm=interface
set network.mm.proto='modemmanager'
set network.mm.device='/sys/devices/platform/scb/fd500000.pcie/pci0000:00/0000:00:00.0/0000:01:00.0/usb2/2-1'
set network.mm.apn='internet'
set network.mm.auth='none'
set network.mm.iptype='ipv4'
set network.mm.force_connection='1'
delete network.wan6
commit network
EOF

# firewall
echo "Configuring firewall..."
uci batch <<EOF
set firewall.@zone[1].network='tethering wan mm'
commit firewall
EOF

# wireless
if [ -d /sys/class/ieee80211 ] && [ "$(ls /sys/class/ieee80211 2>/dev/null)" ]; then
    echo "Wireless detected - configuring wireless..."
    uci batch <<EOF
set wireless.@wifi-device[0].disabled='0'
set wireless.@wifi-iface[0].disabled='0'
set wireless.@wifi-iface[0].mode='ap'
set wireless.@wifi-iface[0].encryption='psk2'
set wireless.@wifi-iface[0].key='freedom'
set wireless.@wifi-device[0].country='ID'
commit wireless
EOF

    if grep -q "Raspberry Pi 5\|Raspberry Pi 4\|Raspberry Pi 3" /proc/cpuinfo 2>/dev/null; then
        uci set wireless.@wifi-iface[0].ssid='XIDZs_5G'
        uci set wireless.@wifi-device[0].channel='149'
        uci set wireless.@wifi-device[0].htmode='VHT80'
    else
        uci set wireless.@wifi-iface[0].ssid='XIDZs'
        uci set wireless.@wifi-device[0].channel='1'
        uci set wireless.@wifi-device[0].htmode='HT20'
    fi

    uci commit wireless
    
    (wifi reload && wifi up) 2>/dev/null

    if iw dev 2>/dev/null | grep -q Interface; then
        if grep -q "Raspberry Pi 5\|Raspberry Pi 4\|Raspberry Pi 3" /proc/cpuinfo 2>/dev/null; then
            if ! grep -q "wifi up" /etc/rc.local 2>/dev/null; then
                sed -i '/exit 0/i sleep 10 && wifi up' /etc/rc.local
            fi
            if ! grep -q "wifi up" /etc/crontabs/root 2>/dev/null; then
                echo "0 */12 * * * wifi down && sleep 5 && wifi up" >> /etc/crontabs/root
            fi
        fi
    fi
else
    echo "No wireless detected - skipping wireless configuration..."
fi

# me909s and dw5821e
echo "Removing USB modeswitch entries..."
sed -i -e '/12d1:15c1/,+5d' -e '/413c:81d7/,+5d' "$USB_MODE"

# XMM-Modem and TTYD
echo "Disabling XMM-Modem and configuring TTYD..."
uci batch 2>/dev/null <<EOF
set xmm-modem.@xmm-modem[0].enable='0'
set ttyd.@ttyd[0].command='/bin/bash --login'
commit xmm-modem
commit ttyd
EOF

# tinyfm
echo "Setting up TinyFM..."
ln -sf / /www/tinyfm/rootfs

# Add startup scripts
echo "Adding custom startup scripts..."
sed -i '/exit 0/i\
# x-gpio for HG & BH\
#sleep 5 && /usr/bin/x-gpio -r\
#/etc/init.d/openclash restart\
#sleep 5 && /sbin/free.sh\
#/sbin/jam bug.com' "$RC_LOCAL"

# UI customizations
echo "Modifying UI elements..."
sed -i "s#_('Firmware Version'),(L.isObject(boardinfo.release)?boardinfo.release.description+' / ':'')+(luciversion||''),#_('Firmware Version'),(L.isObject(boardinfo.release)?boardinfo.release.description+' | xidz_x':''),#g" "$SYSTEM_JS"
sed -i -E 's/icons\/port_%s\.(svg|png)/icons\/port_%s.gif/g' "$PORTS_JS"
mv "$PORTS_JS" "$NEW_PORTS_JS"

# System customizations
echo "Applying system.."
sed -i -e 's/\[ -f \/etc\/banner \] && cat \/etc\/banner/#&/' -e 's/\[ -n \"\$FAILSAFE\" \] && cat \/etc\/banner.failsafe/& || \/usr\/bin\/syntax/' "$PROFILE"
"$XIDZS" disable

# Execute scripts
echo "Running quenxx script..."
"$QUENXX_SH"

echo "Running install2 script..."
"$INSTALL2_SH"

# Tunnel configurasi
echo "Checking tunnel.."
for pkg in luci-app-openclash luci-app-nikki luci-app-passwall; do
    if opkg list-installed | grep -qw "$pkg" 2>/dev/null; then
        echo "$pkg detected - configuring"
        
        case "$pkg" in
            luci-app-openclash)
                echo "Configuring OpenClash"
                ln -sf /etc/openclash/history/xidzs.db /etc/openclash/cache.db
                ln -sf /etc/openclash/core/clash_meta /etc/openclash/clash    
                            
                sed -i '103,105s/.*/<\!-- & -->/' "$RTA_CONF"
                sed -i '144s/.*/<\!-- & -->/' "$ARGON_CONF"
                sed -i "88s/'Enable'/'Disable'/" "$ALPHA_CONF"
                ;;
                
            luci-app-nikki)
                echo "Configuring Nikki"               
                sed -i '115,117s/.*/<\!-- & -->/' "$RTA_CONF"
                sed -i '146s/.*/<\!-- & -->/' "$ARGON_CONF"
                sed -i "40s/'Enable'/'Disable'/" "$ALPHA_CONF"
                ;;
                
            luci-app-passwall)
                echo "Configuring Passwall"
                sed -i '112,114s/.*/<\!-- & -->/' "$RTA_CONF"
                sed -i '147s/.*/<\!-- & -->/' "$ARGON_CONF"
                sed -i "72s/'Enable'/'Disable'/" "$ALPHA_CONF"
                ;;
        esac
        
    else
        echo "$pkg not found - cleaning up"
        
        case "$pkg" in
            luci-app-openclash)
                rm -rf /etc/openclash
                
                sed -i '118,120s/.*/<\!-- & -->/' "$RTA_CONF"
                sed -i '149s/.*/<\!-- & -->/' "$ARGON_CONF"
                sed -i "104s/'Enable'/'Disable'/" "$ALPHA_CONF"
                ;;
                
            luci-app-nikki)
                rm -f /etc/config/nikki
                rm -rf /etc/nikki
                
                sed -i '121,123s/.*/<\!-- & -->/' "$RTA_CONF"
                sed -i '150s/.*/<\!-- & -->/' "$ARGON_CONF"
                sed -i "120s/'Enable'/'Disable'/" "$ALPHA_CONF"
                ;;
                
            luci-app-passwall)
                rm -f /etc/config/passwall
                
                sed -i '124,126s/.*/<\!-- & -->/' "$RTA_CONF"
                sed -i '151s/.*/<\!-- & -->/' "$ARGON_CONF"
                sed -i "136s/'Enable'/'Disable'/" "$ALPHA_CONF"
                ;;
        esac
    fi
done

# Web server
echo "Configuring web server and PHP..."
uci batch << EOF
set uhttpd.main.ubus_prefix='/ubus'
set uhttpd.main.interpreter='.php=/usr/bin/php-cgi'
set uhttpd.main.index_page='cgi-bin/luci'
add_list uhttpd.main.index_page='index.html'
add_list uhttpd.main.index_page='index.php'
commit uhttpd
EOF

cp /etc/php.ini "$PHP_INI_BAK"
sed -i \
    -e 's|^memory_limit = .*|memory_limit = 128M|g' \
    -e 's|^max_execution_time = .*|max_execution_time = 60|g' \
    -e 's|^display_errors = .*|display_errors = Off|g' \
    -e 's|^;*date\.timezone =.*|date.timezone = Asia/Jakarta|g' \
    "$PHP_INI"

ln -sf /usr/lib/php8

# Final cleanup
echo "cleaning up, completed setup..."
rm -rf /etc/uci-defaults/$(basename "$0")

exit 0
