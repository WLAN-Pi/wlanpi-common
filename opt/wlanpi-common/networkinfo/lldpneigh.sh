#!/bin/bash
# Detects LLDP neighbour on eth0 or eth1 interface

# Check if the script is running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

# Prevent multiple instances of the script to run at the same time
for pid in $(pidof -x $0); do
    if [ $pid != $$ ]; then
        echo "Error: Another instance of LLDP script is already running. Quitting."
        exit 1
    fi
done

CAPTUREFILE="/tmp/lldpneightcpdump.cap"
OUTPUTFILE="/tmp/lldpneigh.txt"
DIRECTORY="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

check_interface_up() {
    local interface=$1
    if ip link show "$interface" 2>/dev/null | grep -q "state UP"; then
        return 0
    else
        return 1
    fi
}

INTERFACE=""
if check_interface_up "eth0"; then
    INTERFACE="eth0"
    logger "networkinfo script: using eth0 (default choice when available)"
elif check_interface_up "eth1"; then
    INTERFACE="eth1"
    logger "networkinfo script: using eth1 (eth0 not available)"
else
    logger "networkinfo script: neither eth0 nor eth1 is up"
    exit 1
fi

# Clean up the output files
sudo "$DIRECTORY"/lldpcleanup.sh

logger "networkinfo script: looking for an LLDP neighbour on $INTERFACE"

# Run packet capture for up to 61 seconds or stop after we have got the right packets
TIMETOSTOP=0
while [ "$TIMETOSTOP" == 0 ]; do
  timeout 61 sudo tcpdump -vv -s 1500 -c 1 'ether[12:2]=0x88cc' -i "$INTERFACE" -Q in > "$CAPTUREFILE"
  TIMETOSTOP=$(grep "LLDP" "$CAPTUREFILE")
done

# If we didn't capture any LLDP packets then return
if [ -z "$TIMETOSTOP" ]; then
    logger "networkinfo script: no LLDP neighbour detected on $INTERFACE"
    exit 0
else
    logger "networkinfo script: found a new LLDP neighbour on $INTERFACE"
fi

# Be careful this first statement uses tee without -a and overwrites the content of the text file
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
