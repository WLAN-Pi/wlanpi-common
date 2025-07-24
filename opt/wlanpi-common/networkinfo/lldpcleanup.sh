#!/bin/bash
# Cleans networkinfo cache text files 

DIRECTORY=$1
CAPTUREFILE="/tmp/lldpneightcpdump.cap"
OUTPUTFILE="/tmp/lldpneigh.txt"

#Clean up LLDP cache files
logger "networkinfo script: cleaning LLDP neighbour cache files"
echo "No neighbour, takes up to 60 seconds" > "$OUTPUTFILE"
#Tell me if eth0 is down 
for interface in eth0 eth1; do
    if sudo /sbin/ethtool "$interface" 2>/dev/null | grep -q "Link detected: no"; then
        echo "$interface is down" > "$OUTPUTFILE"
        break
    fi
done
#Remove capture file
sudo rm -f "$CAPTUREFILE"

exit 0
