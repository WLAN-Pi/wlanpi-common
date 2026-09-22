#!/bin/bash
# Cleans networkinfo cache text files

# Runtime files live in a root-owned directory, never in the shared /tmp. See
# the producer scripts for why. The unit provides RUNTIME_DIRECTORY; the
# fallback covers a manual run.
RUNTIME_DIR="${RUNTIME_DIR:-${RUNTIME_DIRECTORY:-/run/wlanpi-networkinfo}}"
OUTPUTFILE="$RUNTIME_DIR/lldpneigh.txt"

install -d -m 0700 "$RUNTIME_DIR"

#Clean up LLDP cache files
logger "networkinfo script: cleaning LLDP neighbour cache files"
# Publish the placeholder atomically so a reader never sees a partial file.
PLACEHOLDER=$(mktemp "$RUNTIME_DIR/lldpneigh.XXXXXX")
echo "No neighbour, takes up to 60 seconds" > "$PLACEHOLDER"
#Tell me if eth0 is down 
for interface in eth0 eth1; do
    if /sbin/ethtool "$interface" 2>/dev/null | grep -q "Link detected: no"; then
        echo "$interface is down" > "$PLACEHOLDER"
        break
    fi
done
chmod 0600 "$PLACEHOLDER"
mv -f "$PLACEHOLDER" "$OUTPUTFILE"
#Remove capture files
rm -f -- "$RUNTIME_DIR"/*.cap

exit 0
