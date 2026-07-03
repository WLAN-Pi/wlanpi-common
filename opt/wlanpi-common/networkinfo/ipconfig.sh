#!/bin/bash

#Displays IP address, subnet mask, default gateway, DNS servers, speed, duplex, DHCP server IP address and name, MAC address

# Author: Jiri Brejcha, jirka@jiribrejcha.net, @jiribrejcha

ETH0ISUP=$(ip link show eth0 2>/dev/null | grep -q "state UP" && echo "UP")
ETH1ISUP=$(ip link show eth1 2>/dev/null | grep -q "state UP" && echo "UP")

if [ "$ETH0ISUP" ]; then
    INTERFACE="eth0"
elif [ "$ETH1ISUP" ]; then
    INTERFACE="eth1"
else
    echo "Eth0 and eth1 are down"
    exit 1
fi

# echo "Using interface: $INTERFACE"

ETHLEASES="/var/lib/dhcp/dhclient.${INTERFACE}.leases"
ACTIVEIP=$(ip a | grep "$INTERFACE" | grep "inet" | grep -v "secondary" | head -n1 | cut -d '/' -f1 | cut -d ' ' -f6)
SUBNET=$(ip a | grep "$INTERFACE" | grep "inet" | grep -v "secondary" | head -n1 | cut -d ' ' -f6 | tail -c 4)
ETHISUP=$(/sbin/ifconfig "$INTERFACE" | grep "RUNNING")

# DHCP lease details. Trixie and later have no dhclient or /etc/network/interfaces:
# NetworkManager manages the interface with its internal DHCP client, so ask nmcli.
# Older images (bullseye/bookworm) fall back to parsing the dhclient lease file.
NMDHCP4=""
if command -v nmcli >/dev/null 2>&1; then
    NMDHCP4=$(nmcli -t -f DHCP4 device show "$INTERFACE" 2>/dev/null)
fi

if [[ "$NMDHCP4" ]]; then
    # DHCP4 section is only populated when the address was obtained via DHCP
    DHCPENABLED="$NMDHCP4"
    LEASEDIPISUSED=$(echo "$NMDHCP4" | grep ":ip_address = $ACTIVEIP")
    DHCPSRVNAME="" # server name (sname) is not exposed by NetworkManager
    DHCPSRVADDR=$(echo "$NMDHCP4" | grep ":dhcp_server_identifier = " | grep -E -o "([0-9]{1,3}[\.]){3}[0-9]{1,3}")
    DOMAINNAME=$(echo "$NMDHCP4" | grep ":domain_name = " | sed 's/^.* = //')
elif [[ -f "$ETHLEASES" ]]; then
    LEASEDIPISUSED=$(grep "$ACTIVEIP" "$ETHLEASES")
    DHCPENABLED=$(grep -i "$INTERFACE" /etc/network/interfaces 2>/dev/null | grep "dhcp" | grep -v "#")
    DHCPSRVNAME=$(grep -A 13 "interface \"$INTERFACE\";" "$ETHLEASES" | tail -13 | grep -B 1 -A 10 "$ACTIVEIP" | grep "server-name" | cut -d '"' -f2)
    DHCPSRVADDR=$(grep -A 13 "interface \"$INTERFACE\";" "$ETHLEASES" | tail -13 | grep -B 1 -A 10 "$ACTIVEIP" | grep "dhcp-server-identifier" | grep -E -o "([0-9]{1,3}[\.]){3}[0-9]{1,3}")
    DOMAINNAME=$(grep -A 13 "interface \"$INTERFACE\";" "$ETHLEASES" | tail -13 | grep -B 1 -A 10 "$ACTIVEIP" | grep "domain-name " | cut -d '"' -f2)
else
    LEASEDIPISUSED=""
    DHCPENABLED=""
    DHCPSRVNAME=""
    DHCPSRVADDR=""
    DOMAINNAME=""
fi
DEFAULTGW=$(/sbin/route -n | grep G | grep $INTERFACE | cut -d ' ' -f 10)
# Read speed/duplex from sysfs: ethtool lives in /usr/sbin, which is not on the
# PATH for regular users on trixie, and sysfs needs no external tool at all
if [[ "$(cat /sys/class/net/$INTERFACE/carrier 2>/dev/null)" == "1" ]]; then
    SPEED=$(cat /sys/class/net/$INTERFACE/speed 2>/dev/null)
    DUPLEX=$(cat /sys/class/net/$INTERFACE/duplex 2>/dev/null | sed 's/./\u&/')
else
    SPEED="Disconnected"
    DUPLEX="Disconnected"
fi
MACADDRESS=$(sed 's/://g' /sys/class/net/$INTERFACE/address)
DNSSERVERS=$(grep "nameserver" /etc/resolv.conf | sed 's/nameserver/DNS:/g')
MTU=$(cat /sys/class/net/$INTERFACE/mtu)

echo "IP: $ACTIVEIP"
echo "Subnet: $SUBNET"
echo "DG: $DEFAULTGW"
echo "$DNSSERVERS"

#DHCP server info
if [[ "$LEASEDIPISUSED" ]] && [[ "$ACTIVEIP" ]] && [[ "$DHCPENABLED" ]]; then
    if [[ "$DHCPSRVNAME" ]] && [[ "$LEASEDIPISUSED" ]]; then
        echo "DHCP server name: $DHCPSRVNAME"
    fi
    if [[ "$DHCPSRVADDR" ]] && [[ "$LEASEDIPISUSED" ]] && [[ "$ACTIVEIP" ]]; then
        echo "DHCP server address: $DHCPSRVADDR"
    fi
    if [[ "$DOMAINNAME" ]] && [[ "$LEASEDIPISUSED" ]] && [[ "$ACTIVEIP" ]]; then
        echo "Domain: $DOMAINNAME"
    fi
else
    echo "DHCP: server not detected"
fi

echo "Speed: $SPEED"
echo "Duplex: $DUPLEX"
echo "MAC: $MACADDRESS"
echo "MTU: $MTU"
