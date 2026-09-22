#!/bin/bash
# Detects CDP neighbour on eth0 interface

#Check if the script is running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

#Prevent multiple instances of the script to run at the same time
for pid in $(pidof -x "$0"); do
    if [ "$pid" != "$$" ]; then
        echo "Error: Another instance of CDP script is already running. Quitting."
        exit 1
    fi
done

# Runtime files live in a root-owned directory, never in the shared /tmp. These
# steps write to predictable paths, and in a world-writable directory a local
# user can pre-create a symlink that this root script would then follow. The
# unit provides RUNTIME_DIRECTORY; the fallback covers a manual run.
RUNTIME_DIR="${RUNTIME_DIR:-${RUNTIME_DIRECTORY:-/run/wlanpi-networkinfo}}"
OUTPUTFILE="$RUNTIME_DIR/cdpneigh.txt"
DIRECTORY="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

install -d -m 0700 "$RUNTIME_DIR"

#Clean up the output files
"$DIRECTORY"/cdpcleanup.sh

ETH0ISUP=$(ip link show eth0 2>/dev/null | grep -q "state UP" && echo "UP")
ETH1ISUP=$(ip link show eth1 2>/dev/null | grep -q "state UP" && echo "UP")

if [ "$ETH0ISUP" ]; then
    INTERFACE="eth0"
elif [ "$ETH1ISUP" ]; then
    INTERFACE="eth1"
else
    logger "networkinfo script: both eth0 and eth1 are down"
    echo "Both eth0 and eth1 are down"
    exit 1
fi

logger "networkinfo script: using interface $INTERFACE, looking for a CDP neighbour"

# Capture into a private temporary file. mktemp creates it 0600 inside the
# root-owned runtime directory, so no symlink can be planted at the path.
CAPTUREFILE=$(mktemp "$RUNTIME_DIR/cdpneigh.XXXXXX.cap")

# Run packet capture, retrying until a parsable CDP packet arrives or the
# window closes. The old loop tested "$TIMETOSTOP" == 0, which is never true
# (the value is a matching line or empty), so it ran exactly once: one missed
# window meant "no CDP neighbour detected". CDP advertises about every 60
# seconds, so allow two intervals before giving up.
DEADLINE=$((SECONDS + 130))
TIMETOSTOP=""
while [ -z "$TIMETOSTOP" ] && [ "$SECONDS" -lt "$DEADLINE" ]; do
    timeout $((DEADLINE - SECONDS)) tcpdump -nv -s 1500 -c 1 -i "$INTERFACE" -Q in 'ether[20:2] == 0x2000' and ether dst 01:00:0c:cc:cc:cc > "$CAPTUREFILE"
    TIMETOSTOP=$(grep "CDP" "$CAPTUREFILE")
done

#If we didn't capture any CDP packets then return
if [ -z "$TIMETOSTOP" ]; then
    logger "networkinfo script: no CDP neighbour detected"
    rm -f -- "$CAPTUREFILE"
    exit 0
else 
    logger "networkinfo script: found a new CDP neighbour"
fi

# Publish the parsed output atomically: build it in a private temporary file and
# rename it into place, so a reader never sees a partial file.
OUTPUT_TMP=$(mktemp "$RUNTIME_DIR/cdpneigh.XXXXXX")

#Be careful this first statement uses tee without -a and overwrites the content of the text file
DEVICEID=$(grep "Device-ID" "$CAPTUREFILE" | cut -d "'" -f2)
if [ "$DEVICEID" ]; then
    echo -e "Name: $DEVICEID" 2>&1 | tee "$OUTPUT_TMP"
else
    echo "No neighbour name found in CDP packet" 2>&1 | tee "$OUTPUT_TMP"
    chmod 0600 "$OUTPUT_TMP"
    mv -f "$OUTPUT_TMP" "$OUTPUTFILE"
    rm -f -- "$CAPTUREFILE"
    exit 0
fi

PORT=$(grep "Port-ID" "$CAPTUREFILE" | cut -d "'" -f2)
if [ "$PORT" ]; then
    echo -e "Port: $PORT" 2>&1 | tee -a "$OUTPUT_TMP"
fi

#UBNT devices send <reverse-ip-address>.in-addr.arpa in their CDP messages
ISREVERSEADDRESS=$(grep "in-addr.arpa" "$CAPTUREFILE")
ADDRESS=$(grep "Address " "$CAPTUREFILE" | grep -E -o "([0-9]{1,3}[\.]){3}[0-9]{1,3}")
if [ "$ISREVERSEADDRESS" ]; then
    ADDRESS=$(echo "$ADDRESS" | awk -F. '{OFS=FS;print $4,$3,$2,$1}')
fi
if [ "$ADDRESS" ]; then
    echo -e "IP: $ADDRESS" 2>&1 | tee -a "$OUTPUT_TMP"
fi

NATIVEVLAN=$(grep "Native VLAN ID" "$CAPTUREFILE" | cut -d ':' -f3)
if [ "$NATIVEVLAN" ]; then
    echo -e "Native VLAN:$NATIVEVLAN" 2>&1 | tee -a "$OUTPUT_TMP"
fi

PLATFORM=$(grep "Platform" "$CAPTUREFILE" | cut -d "'" -f2)
if [ "$PLATFORM" ]; then
    echo -e "Model: $PLATFORM" 2>&1 | tee -a "$OUTPUT_TMP"
fi

SWVER=$(grep -A 1 "Version String" "$CAPTUREFILE" | tail -n 1 | sed 's/^[[:space:]]*//')
if [ "$SWVER" ]; then
    echo -e "SW: $SWVER" 2>&1 | tee -a "$OUTPUT_TMP"
fi

chmod 0600 "$OUTPUT_TMP"
mv -f "$OUTPUT_TMP" "$OUTPUTFILE"
rm -f -- "$CAPTUREFILE"

exit 0
