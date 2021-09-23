#!/bin/bash
# Detects CDP neighbour on eth0 interface

#Check if the script is running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

#Prevent multiple instances of the script to run at the same time
for pid in $(pidof -x $0); do
    if [ $pid != $$ ]; then
        echo "Error: Another instance of CDP script is already running. Quitting."
        exit 1
    fi
done

CAPTUREFILE="/tmp/cdpneightcpdump.cap"
OUTPUTFILE="/tmp/cdpneigh.txt"
DIRECTORY="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

#Clean up the output files
sudo "$DIRECTORY"/cdpcleanup.sh

logger "networkinfo script: looking for a CDP neighbour"

#Run packet capture for up to 61 seconds or stop after we have got the right packets
TIMETOSTOP=0
while [ "$TIMETOSTOP" == 0 ]; do
    timeout 61 sudo tcpdump -v -s 1500 -c 1 'ether[20:2] == 0x2000' -i eth0 -Q in > "$CAPTUREFILE"
    TIMETOSTOP=$(grep "CDP" "$CAPTUREFILE")
done

#If we didn't capture any LLDP packets then return
if [ -z "$TIMETOSTOP" ]; then
    logger "networkinfo script: no CDP neighbour detected"
    exit 0
else 
    logger "networkinfo script: found a new CDP neighbour"
fi

#Be careful this first statement uses tee without -a and overwrites the content of the text file
DEVICEID=$(grep "Device-ID" "$CAPTUREFILE" | cut -d "'" -f2)
if [ "$DEVICEID" ]; then
    echo -e "Name: $DEVICEID" 2>&1 | tee "$OUTPUTFILE"
else
    echo "No neighbour name found in CDP packet" 2>&1 | tee "$OUTPUTFILE"
    exit 0
fi

PORT=$(grep "Port-ID" "$CAPTUREFILE" | cut -d "'" -f2)
if [ "$PORT" ]; then
    echo -e "Port: $PORT" 2>&1 | tee -a "$OUTPUTFILE"
fi

#UBNT devices send <reverse-ip-address>.in-addr.arpa in their CDP messages
ISREVERSEADDRESS=$(grep "in-addr.arpa" "$CAPTUREFILE")
ADDRESS=$(grep "Address " "$CAPTUREFILE" | grep -E -o "([0-9]{1,3}[\.]){3}[0-9]{1,3}")
if [ "$ISREVERSEADDRESS" ]; then
    ADDRESS=$(echo "$ADDRESS" | awk -F. '{OFS=FS;print $4,$3,$2,$1}')
fi
if [ "$ADDRESS" ]; then
    echo -e "IP: $ADDRESS" 2>&1 | tee -a "$OUTPUTFILE"
fi

NATIVEVLAN=$(grep "Native VLAN ID" "$CAPTUREFILE" | cut -d ':' -f3)
if [ "$NATIVEVLAN" ]; then
    echo -e "Native VLAN:$NATIVEVLAN" 2>&1 | tee -a "$OUTPUTFILE"
fi

PLATFORM=$(grep "Platform" "$CAPTUREFILE" | cut -d "'" -f2)
if [ "$PLATFORM" ]; then
    echo -e "Model: $PLATFORM" 2>&1 | tee -a "$OUTPUTFILE"
fi

SWVER=$(grep -A 1 "Version String" "$CAPTUREFILE" | tail -n 1 | sed 's/^[[:space:]]*//')
if [ "$SWVER" ]; then
    echo -e "SW: $SWVER" 2>&1 | tee -a "$OUTPUTFILE"
fi

exit 0

