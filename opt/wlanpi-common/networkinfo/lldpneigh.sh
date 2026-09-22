#!/bin/bash
# Detects LLDP neighbour on eth0 or eth1 interface

# Check if the script is running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

# Prevent multiple instances of the script to run at the same time
for pid in $(pidof -x "$0"); do
    if [ "$pid" != "$$" ]; then
        echo "Error: Another instance of LLDP script is already running. Quitting."
        exit 1
    fi
done

# Runtime files live in a root-owned directory, never in the shared /tmp. These
# steps write to predictable paths, and in a world-writable directory a local
# user can pre-create a symlink that this root script would then follow. The
# unit provides RUNTIME_DIRECTORY; the fallback covers a manual run.
RUNTIME_DIR="${RUNTIME_DIR:-${RUNTIME_DIRECTORY:-/run/wlanpi-networkinfo}}"
OUTPUTFILE="$RUNTIME_DIR/lldpneigh.txt"
DIRECTORY="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

install -d -m 0700 "$RUNTIME_DIR"

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
"$DIRECTORY"/lldpcleanup.sh

logger "networkinfo script: looking for an LLDP neighbour on $INTERFACE"

# Capture into a private temporary file. mktemp creates it 0600 inside the
# root-owned runtime directory, so no symlink can be planted at the path.
CAPTUREFILE=$(mktemp "$RUNTIME_DIR/lldpneigh.XXXXXX.cap")

# Run packet capture, retrying until a parsable LLDP packet arrives or the
# window closes. The old loop tested "$TIMETOSTOP" == 0, which is never true
# (the value is a matching line or empty), so it ran exactly once: one missed
# window meant "no LLDP neighbour detected". LLDP advertises every 30 seconds,
# so two intervals is a generous window.
DEADLINE=$((SECONDS + 70))
TIMETOSTOP=""
while [ -z "$TIMETOSTOP" ] && [ "$SECONDS" -lt "$DEADLINE" ]; do
  timeout $((DEADLINE - SECONDS)) tcpdump -vv -s 1500 -c 1 'ether[12:2]=0x88cc' -i "$INTERFACE" -Q in > "$CAPTUREFILE"
  TIMETOSTOP=$(grep "LLDP" "$CAPTUREFILE")
done

# If we didn't capture any LLDP packets then return
if [ -z "$TIMETOSTOP" ]; then
    logger "networkinfo script: no LLDP neighbour detected on $INTERFACE"
    rm -f -- "$CAPTUREFILE"
    exit 0
else
    logger "networkinfo script: found a new LLDP neighbour on $INTERFACE"
fi

# Publish the parsed output atomically: build it in a private temporary file and
# rename it into place, so a reader never sees a partial file.
OUTPUT_TMP=$(mktemp "$RUNTIME_DIR/lldpneigh.XXXXXX")

# Be careful this first statement uses tee without -a and overwrites the content of the text file
DEVICEID=$(grep "System Name" "$CAPTUREFILE" | cut -d ' ' -f7)
if [ "$DEVICEID" ]; then
    echo "Name: $DEVICEID" 2>&1 | tee "$OUTPUT_TMP"
else
    echo "No neighbour name found in LLDP packet" 2>&1 | tee "$OUTPUT_TMP"
    chmod 0600 "$OUTPUT_TMP"
    mv -f "$OUTPUT_TMP" "$OUTPUTFILE"
    rm -f -- "$CAPTUREFILE"
    exit 0
fi

IFNAME=$(grep "Interface Name" "$CAPTUREFILE" | cut -d ':' -f2 | awk '{$1=$1};1')
if [ "$IFNAME" ]; then
    echo "Port: $IFNAME" 2>&1 | tee -a "$OUTPUT_TMP"
fi

PORTDESC=$(grep "Port Description" "$CAPTUREFILE" | cut -d ':' -f2 | awk '{$1=$1};1')
if [ "$PORTDESC" ]; then
    echo "Desc: $PORTDESC" 2>&1 | tee -a "$OUTPUT_TMP"
fi

ADDRESS=$(grep "Management Address" "$CAPTUREFILE" | cut -d ' ' -f 10 | cut -d$'\n' -f2)
if [ "$ADDRESS" ]; then
    echo "IP: $ADDRESS" 2>&1 | tee -a "$OUTPUT_TMP"
fi

PORTVLAN=$(grep -A1 "Port VLAN" "$CAPTUREFILE" | cut -d$'\n' -f2 | cut -d ' ' -f9 | cut -d$'\n' -f1)
if [ "$PORTVLAN" ]; then
    echo "Native VLAN: $PORTVLAN" 2>&1 | tee -a "$OUTPUT_TMP"
fi

PLATFORM=$(grep -A 1 "System Description" "$CAPTUREFILE" | cut -d$'\n' -f2 | sed -e 's/^[ \t]*//')
if [ "$PLATFORM" ]; then
    echo "Model: $PLATFORM" 2>&1 | tee -a "$OUTPUT_TMP"
fi

chmod 0600 "$OUTPUT_TMP"
mv -f "$OUTPUT_TMP" "$OUTPUTFILE"
rm -f -- "$CAPTUREFILE"

exit 0
