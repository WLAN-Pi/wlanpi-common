#!/usr/bin/env bash

# Script to convert WLAN Pi classic mode to networkd
# Author : Nigel Bowden
#
# This script will:
#   1. Decommission dhclient service:
#       a. Remove any existing network entries in the file : /etc/network/interfaces
#       b. Remove any files in the folder /etc/network/interfaces.d
#   2. Decommission the dhcpcd service (isc-dhcp-server):
#       a. Stop the dhcpcd service
#       b. Disable the dhcpd service
#   3. Backup any existing of following files in /etc/systemd/network to /etc/systemd/network.classic
#       a. *.network
#       b. *.netdev
#   4. Add in the following files:
#       a. eth0.network
#       b. eth1.network
#       c. wlan0.network
#       d. wlan1.network
#       e. usb0.network
#       f. usb1.network
#   5. Create wpa_supplicant files for wlan0 & wlan1 (blank config)
#       a. /etc/wpa_supplicant/wpa_supplicant-wlan0.conf
#       b. /etc/wpa_supplicant/wpa_supplicant-wlan1.conf
#   6. Enable wpa_supplicant services:
#       a. systemctl enable wpa_supplicant@wlan0.service
#       b. systemctl enable wpa_supplicant@wlan1.service
#
#
# Logging:
#   Log faiures to syslog
#

# fail on script errors
#set -e

# check if the script is running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must run as root. Add \"sudo\" please".
   exit 1
fi

# Decommission dhclient service (remove files definitions - take effect after network reboot)
echo "Removing dhclient config files."
sudo echo "source /etc/network/interfaces.d/*" > /etc/network/interfaces
sudo rm -f /etc/network/interfaces.d/*

# Decommission the dhcpcd service (isc-dhcp-server):
echo "Stopping and disabling dhcpcd (isc-dhcp-server) service."
sudo systemctl stop dhcpcd.service
sudo systemctl disable dhcpcd.service

# Disable
echo "Stopping and disabling ifplugd service."
sudo systemctl stop ifplugd
sudo systemctl disable ifplugd

# Backup any existing of following files in /etc/systemd/network 
# to /etc/systemd/network.classic
#   a. *.network
#   b. *.netdev
echo "Copying existing networkd files to dedicated classic mode directory."
sudo mkdir -p /etc/systemd/network.classic
sudo cp /etc/systemd/network/*.network /etc/systemd/network.classic
sudo cp /etc/systemd/network/*.netdev /etc/systemd/network.classic

# Create (or overwrite) networkd files for classic mode
declare -a interfaces=(eth0 eth1 wlan0 wlan1 usb1)

for i in "${interfaces[@]}"
do
    echo "Creating networkd file for $i."
    cat << EOF > "/etc/systemd/network.classic/$i.network"
[Match]
Name=$i

[Network]
DHCP=yes
EOF

done

# Create usb0 network file
cat << EOF > /etc/systemd/network.classic/usb0.network
[Match]
Name=usb0
[Address]
Address=169.254.42.1/24
Scope=link
[Network]
DHCPServer=yes
LinkLocalAddressing=no
IPv6AcceptRA=no
[DHCPServer]
EmitRouter=no
PoolSize=10
EOF

# Create wpa_supplicant files for wlan0 & wlan1
declare -a wlan_interfaces=(wlan0 wlan1)

for i in "${wlan_interfaces[@]}"
do
    echo "Creating wpa supplicant config file for $i"
    cat << EOF > "/etc/wpa_supplicant/wpa_supplicant-$i.conf"
ap_scan=1
p2p_disabled=1

#######################################################################################
# NOTE: to use the templates below, remove the hash symbols at the start of each line
#######################################################################################

# WPA2 PSK Network sample (highest priority - joined first)
#network={
#  ssid="enter SSID Name"
#  psk="enter key"
#  priority=10
#}

# WPA2 PSK Network sample (next priority - joined if first priority not available) - don't unhash this line

#network={
#    ssid="enter SSID Name"
#    psk="enter key"
#    priority=3
#}

# WPA2 PEAP example (next priority - joined if second priority not available) - don't unhash this line

#network={
#  ssid="enter SSID Name"
#  key_mgmt=WPA-EAP
#  eap=PEAP
#  anonymous_identity="anonymous"
#  identity="enter your username"
#  password="enter your password"
#  phase2="autheap=MSCHAPV2"
#  priority=2
#}

# Open network example (lowest priority, only joined other 3 networks not available) - don't unhash this line

#network={
#   ssid="enter SSID Name"
#   key_mgmt=NONE
#   priority=1
#}

# SAE mechanism for PWE derivation
# 0 = hunting-and-pecking (HNP) loop only (default without password identifier)
# 1 = hash-to-element (H2E) only (default with password identifier)
# 2 = both hunting-and-pecking loop and hash-to-element enabled
# Note: The default value is likely to change from 0 to 2 once the new
# hash-to-element mechanism has received more interoperability testing.
# When using SAE password identifier, the hash-to-element mechanism is used
# regardless of the sae_pwe parameter value.
#
#sae_pwe=0 <--- default value, change to 1 or 2 if AP forces H2E.

# WPA3 PSK network sample for 6 GHz (note SAE and PMF is required) - don't unhash this line

#network={
#  ssid="6 GHz SSID"
#  psk="password"
#  priority=10
#  key_mgmt=SAE
#  ieee80211w=2
#}
EOF

done

# Remove old wpa supplicant file
if [ -e /etc/wpa_supplicant/wpa_supplicant.conf ]; then
    echo "Removing old wpa_supplicant.conf file"
    sudo rm  /etc/wpa_supplicant/wpa_supplicant.conf 
fi

# Enable wpa supplicant services
echo "Enabling wpa supplicant services for wlan0 & wlan1"
sudo systemctl enable wpa_supplicant@wlan0.service
sudo systemctl enable wpa_supplicant@wlan1.service

echo "Finished."

# Copy new networkd files to /etc/systemd/network to make them live
echo "Copying networkd files to live directory for activation"
sudo \cp /etc/systemd/network.classic/*.* /etc/systemd/network

echo "Rebooting for new settings to take effect..."
sudo reboot