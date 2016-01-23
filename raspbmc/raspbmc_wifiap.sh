#!/bin/sh
#
# Raspbmc を車載用のAirPlayデバイスとするために
# WiFi アクセスポイントの機能を導入するスクリプト。
#
######################################################################
# 実装上のポイント:
# iPhoneで利用する際に、通常のネットワーク通信は3G/LTE側に流しつつ、
# WiFiで音楽や動画をAirPlayで再生できること。
#
#　　 iPhone を普通の無線LANアクセスポイントに登録すると、
#　　 すべてのデータ通信は無線LAN側に流れます。
#
#　　 しかし車載用の AirPlay を目的としたWiFiアクセスポイントでは
#　　 インターネットへの経路が存在しない閉鎖ネットワークです。
#　　 このために普通に WiFi AP を立ててしまうと車内にいる間は
#　　 メール、ウェブ閲覧、その他のインターネットサービスが使えません。
#
#
#　　 これではあまりにも不便なので以下のいずれかの方法で問題を回避します。
#
#　　 a) DHCPアドレスリースの際にデフォルトゲートウェイやDNSサーバの
#　　　　情報を配布しない。
#
#　　 b) DHCPサーバを動かさず、IPアドレスは静的割り当てとする。
#
#　　 しかし b) では設定が面倒になるので、a) の設定を提供する。
#

########################################
# 設定調整項目

# 無線LANデバイスのIPアドレス設定
WLAN_IP=172.16.0.1

# WiFi アクセスポイントのSSIDとパスフレーズの設定
WLAN_SSID=raspbmc-airplay
WLAN_PASSPHRASE=raspberry

# 設定調整項目ここまで
########################################

# WLAN デバイス名
# 通常は変更しない
WLAN_DEVICE=wlan0


########################################
# ここから下は意味がわかる方だけいじること
########################################

# isc-dhcp-server がインストールされていない場合は
# 必要なパッケージのインストールを行う
dpkg -l | grep -q "isc-dhcp-server"
if [ $? -ne 0 ]; then
    # パッケージのアップデートを行います。
    # これは AirPlay が正常に利用できないことを防止するため？
    apt-get -y update
    apt-get -y upgrade
    apt-get -y autoremove

    # WiFi アクセスポイントの構築に必要な２つのパッケージをインストールします。
    apt-get -y install hostapd isc-dhcp-server

    # patch コマンドでファイルの更新を行う
    #apt-get -y install patch
fi

# dhcpd や hostapd が動いていたら止める
service isc-dhcp-server stop
hostapd_pid=$( pidof hostapd )
if [ "$hostapd_pid" != "" ]; then
    kill $hostapd_pid
fi

# /etc/network/interfaces に wlan0 のネットワーク設定を書き込む処理
# ルーティングは不要なので iptables の設定は省略している。
# このファイルは常に上書きでよい。
(
cat << EOF
allow-hotplug ${WLAN_DEVICE}
iface ${WLAN_DEVICE} inet static
    address   ${WLAN_IP}
    netmask   255.255.255.0
    broadcast ${WLAN_IP%.*}.255
    network   ${WLAN_IP%.*}.0
    post-up   /usr/sbin/hostapd -B /etc/hostapd/hostapd.conf
    post-up   /usr/sbin/service isc-dhcp-server start
    pre-down  kill \`pidof hostapd\`
EOF
) > /etc/network/interfaces

####################
# 設定ファイルのパッチ当てる前のファイルが存在していたら
# それを用いて設定ファイルを復元する。

for file in /etc/dhcp/dhcpd.conf \
            /etc/default/isc-dhcp-server \
            /etc/NetworkManager/NetworkManager.conf \
            /etc/hostapd/hostapd.conf ; do
    if [ -e ${file}.orig ]; then
        mv ${file}.orig ${file}
    fi
done

# 本スクリプトの初回実行時には hostapd.conf は /etc に存在していないため、
# サンプルを展開する。
if [ ! -e /etc/hostapd/hostapd.conf ]; then
    zcat /usr/share/doc/hostapd/examples/hostapd.conf.gz > /etc/hostapd/hostapd.conf
fi

# wlan0 の MAC アドレスを抽出する。
# これは NetworkManager.conf で管理外のNIC指定に用いる
MACADDR=$( /sbin/ifconfig ${WLAN_DEVICE} | head -1 | awk '{ print $5 }' )

####################
# patch に流し込める形式で設定ファイルの差分を作る
#
# (1) /etc/default/isc-dhcp-server
# ・IPアドレスをリースするだけの簡単な設定。
# ・デフォルトゲートウェイは切らない。
# ・DNSサーバ情報も出さない。
#
# (2) /etc/NetworkManager/NetworkManager.conf
# ・wlan0 の MACアドレスを管理除外対象として追記する。
#
# (3) /etc/default/isc-dhcp-server
# ・DHCPのアドレスリースを wlan0 だけに絞る指定を追記する。
#
# (4) /etc/hostapd/hostapd.conf
# ・SSID とパスフレーズを設定する。

(
cat << EOF
--- /etc/dhcp/dhcpd.conf	2012-09-14 12:24:53.000000000 +0900
+++ /etc/dhcp/dhcpd.conf.new	2015-01-31 23:10:32.464728758 +0900
@@ -105,3 +105,10 @@
 #    range 10.0.29.10 10.0.29.230;
 #  }
 #}
+subnet ${WLAN_IP%.*}.0 netmask 255.255.255.0 {
+  range ${WLAN_IP%.*}.50 ${WLAN_IP%.*}.100;
+  option broadcast-address ${WLAN_IP%.*}.255;
+  option domain-name "localnet";
+  default-lease-time 600;
+  max-lease-time 7200;
+}
--- /etc/default/isc-dhcp-server	2015-01-31 23:10:16.445995339 +0900
+++ /etc/default/isc-dhcp-server.new	2015-01-31 23:10:32.504725694 +0900
@@ -18,4 +18,4 @@
 
 # On what interfaces should the DHCP server (dhcpd) serve DHCP requests?
 #	Separate multiple interfaces with spaces, e.g. "eth0 eth1".
-INTERFACES=""
+INTERFACES="${WLAN_DEVICE}"
--- /etc/NetworkManager/NetworkManager.conf	1970-01-01 09:00:24.480000000 +0900
+++ /etc/NetworkManager/NetworkManager.conf.new	2015-01-31 23:10:32.594718800 +0900
@@ -5,3 +5,6 @@
 
 [ifupdown]
 managed=false
+
+[keyfile]
+unmanaged-devices=mac:${MACADDR}
--- /etc/hostapd/hostapd.conf	2015-02-01 15:58:04.163637719 +0900
+++ /etc/hostapd/hostapd.conf.new	2015-02-01 15:59:42.411575746 +0900
@@ -83,12 +83,12 @@
 ##### IEEE 802.11 related configuration #######################################
 
 # SSID to be used in IEEE 802.11 management frames
-ssid=test
+ssid=${WLAN_SSID}
 
 # Country code (ISO/IEC 3166-1). Used to set regulatory domain.
 # Set as needed to indicate country in which device is operating.
 # This can limit available channels and transmit power.
-#country_code=US
+country_code=JP
 
 # Enable IEEE 802.11d. This advertises the country_code and the set of allowed
 # channels and transmit power levels based on the regulatory limits. The
@@ -679,7 +679,7 @@
 # and/or WPA2 (full IEEE 802.11i/RSN):
 # bit0 = WPA
 # bit1 = IEEE 802.11i/RSN (WPA2) (dot11RSNAEnabled)
-#wpa=1
+wpa=2
 
 # WPA pre-shared keys for WPA-PSK. This can be either entered as a 256-bit
 # secret in hex format (64 hex digits), wpa_psk, or as an ASCII passphrase
@@ -688,7 +688,7 @@
 # wpa_psk (dot11RSNAConfigPSKValue)
 # wpa_passphrase (dot11RSNAConfigPSKPassPhrase)
 #wpa_psk=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
-#wpa_passphrase=secret passphrase
+wpa_passphrase=${WLAN_PASSPHRASE}
 
 # Optionally, WPA PSKs can be read from a separate text file (containing list
 # of (PSK,MAC address) pairs. This allows more than one PSK to be configured.
@@ -700,7 +700,7 @@
 # entries are separated with a space. WPA-PSK-SHA256 and WPA-EAP-SHA256 can be
 # added to enable SHA256-based stronger algorithms.
 # (dot11RSNAConfigAuthenticationSuitesTable)
-#wpa_key_mgmt=WPA-PSK WPA-EAP
+wpa_key_mgmt=WPA-PSK
 
 # Set of accepted cipher suites (encryption algorithms) for pairwise keys
 # (unicast packets). This is a space separated list of algorithms:
@@ -856,7 +856,7 @@
 # 0 = WPS disabled (default)
 # 1 = WPS enabled, not configured
 # 2 = WPS enabled, configured
-#wps_state=2
+wps_state=0
 
 # AP can be configured into a locked state where new WPS Registrar are not
 # accepted, but previously authorized Registrars (including the internal one)
EOF
) | patch -b -p0
