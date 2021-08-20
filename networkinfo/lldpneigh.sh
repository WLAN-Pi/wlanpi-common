#!/bin/bash
# Detects LLDP neighbour on eth0 interface

#Check if the script is running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi

#Prevent multiple instances of the script to run at the same time
for pid in $(pidof -x $0); do
    if [ $pid != $$ ]; then
        echo "Error: Another instance of LLDP script is already running. Quitting."
        exit 1
    fi
done

CAPTUREFILE="/tmp/lldpneightcpdump.cap"
OUTPUTFILE="/tmp/lldpneigh.txt"
DIRECTORY="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

#Clean up the output files
sudo "$DIRECTORY"/lldpcleanup.sh

logger "networkinfo script: looking for an LLDP neighbour"

#Run packet capture for up to 61 seconds or stop after we have got the right packets
TIMETOSTOP=0
while [ "$TIMETOSTOP" == 0 ]; do
  timeout 61 sudo tcpdump -vv -s 1500 -c 1 'ether[12:2]=0x88cc' -i eth0 -Q in > "$CAPTUREFILE"
  TIMETOSTOP=$(grep "LLDP" "$CAPTUREFILE")
done

#If we didn't capture any LLDP packets then return
if [ -z "$TIMETOSTOP" ]; then
    logger "networkinfo script: no LLDP neighbour detected"
    exit 0
else 
    logger "networkinfo script: found a new LLDP neighbour"
fi

#Be careful this first statement uses tee without -a and overwrites the content of the text file
DEVICEID=$(grep "System Name" "$CAPTUREFILE" | cut -d ' ' -f7)
if [ "$DEVICEID" ]; then
    echo "Name: $DEVICEID" 2>&1 | tee "$OUTPUTFILE"
else
    echo "No neighbour name found in LLDP packet" 2>&1 | tee "$OUTPUTFILE"
    exit 0
fi

IFNAME=$(grep "Interface Name" "$CAPTUREFILE" | cut -d ':' -f2 | awk '{$1=$1};1')
if [ "$IFNAME" ]; then
    echo "Port: $IFNAME" 2>&1 | tee -a "$OUTPUTFILE"
fi

PORTDESC=$(grep "Port Description" "$CAPTUREFILE" | cut -d ':' -f2 | awk '{$1=$1};1')
if [ "$PORTDESC" ]; then
    echo "Desc: $PORTDESC" 2>&1 | tee -a "$OUTPUTFILE"
fi

ADDRESS=$(grep "Management Address" "$CAPTUREFILE" | cut -d ' ' -f 10 | cut -d$'\n' -f2)
if [ "$ADDRESS" ]; then
    echo "IP: $ADDRESS" 2>&1 | tee -a "$OUTPUTFILE"
fi

PORTVLAN=$(grep -A1 "Port VLAN" "$CAPTUREFILE" | cut -d$'\n' -f2 | cut -d ' ' -f9 | cut -d$'\n' -f1)
if [ "$PORTVLAN" ]; then
    echo "Native VLAN: $PORTVLAN" 2>&1 | tee -a "$OUTPUTFILE"
fi

PLATFORM=$(grep -A 1 "System Description" "$CAPTUREFILE" | cut -d$'\n' -f2 | sed -e 's/^[ \t]*//')
if [ "$PLATFORM" ]; then
    echo "Model: $PLATFORM" 2>&1 | tee -a "$OUTPUTFILE"
fi

exit 0
