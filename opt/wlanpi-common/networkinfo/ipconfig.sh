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
LEASEDIPISUSED=$(grep "$ACTIVEIP" "$ETHLEASES")
ETHISUP=$(/sbin/ifconfig "$INTERFACE" | grep "RUNNING")
DHCPENABLED=$(grep -i "$INTERFACE" /etc/network/interfaces | grep "dhcp" | grep -v "#")
DHCPSRVNAME=$(grep -A 13 "interface \"$INTERFACE\";" "$ETHLEASES" | tail -13 | grep -B 1 -A 10 "$ACTIVEIP" | grep "server-name" | cut -d '"' -f2)
DHCPSRVADDR=$(grep -A 13 "interface \"$INTERFACE\";" "$ETHLEASES" | tail -13 | grep -B 1 -A 10 "$ACTIVEIP" | grep "dhcp-server-identifier" | grep -E -o "([0-9]{1,3}[\.]){3}[0-9]{1,3}")
DOMAINNAME=$(grep -A 13 "interface \"$INTERFACE\";" "$ETHLEASES" | tail -13 | grep -B 1 -A 10 "$ACTIVEIP" | grep "domain-name " | cut -d '"' -f2)
DEFAULTGW=$(/sbin/route -n | grep G | grep $INTERFACE | cut -d ' ' -f 10)
SPEED=$(ethtool $INTERFACE 2>/dev/null | grep -q "Link detected: yes" && ethtool $INTERFACE 2>/dev/null | grep "Speed" | sed 's/....$//' | cut -d ' ' -f2  || echo "Disconnected")
DUPLEX=$(ethtool $INTERFACE 2>/dev/null | grep -q "Link detected: yes" && ethtool $INTERFACE 2>/dev/null | grep "Duplex" | cut -d ' ' -f 2 || echo "Disconnected")
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
