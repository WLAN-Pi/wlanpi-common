#!/bin/bash
# Cleans networkinfo cache text files 

DIRECTORY=$1
CAPTUREFILE="/tmp/cdpneightcpdump.cap"
OUTPUTFILE="/tmp/cdpneigh.txt"

#Clean up LLDP cache files
logger "networkinfo script: cleaning CDP neighbour cache files"
echo "No neighbour, takes up to 60 seconds" > "$OUTPUTFILE"
#Tell me if eth0 is down 
sudo /sbin/ethtool eth0 | grep -q "Link detected: no" && echo "eth0 is down" > "$OUTPUTFILE"

#Remove capture file
sudo rm -f "$CAPTUREFILE"

exit 0
