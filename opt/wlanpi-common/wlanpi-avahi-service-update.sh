#!/bin/bash

WLANPI_MODEL_CMD="${WLANPI_MODEL_CMD:-/usr/bin/wlanpi-model}"
WLANPI_MODEL_CACHE="${WLANPI_MODEL_CACHE:-/etc/wlanpi-model}"
WLANPI_RELEASE_FILE="${WLANPI_RELEASE_FILE:-/etc/wlanpi-release}"
SERVICE_FILE="${SERVICE_FILE:-/etc/avahi/services/wlanpi_announce.service}"

for req in "$WLANPI_MODEL_CMD" "$WLANPI_RELEASE_FILE" "$SERVICE_FILE"; do
    if [ ! -f "$req" ]; then
        echo "Error: Required file $req not found!" >&2
        exit 1
    fi
done

# Prefer the model cached at boot by wlanpi-config-at-startup.sh (which this
# unit is ordered after). Running wlanpi-model probes USB/PCIe and can block on
# a stalled bus; the cache holds the same string the awk below extracts.
if [ -s "$WLANPI_MODEL_CACHE" ]; then
    MODEL=$(cat "$WLANPI_MODEL_CACHE")
elif ! MODEL=$("$WLANPI_MODEL_CMD" | awk -F': +' '/^Model/ { print $2 }'); then
    echo "Error: Failed to get model information" >&2
    exit 1
fi

if [ -z "$MODEL" ]; then
    echo "Error: Empty model information" >&2
    exit 1
fi

if ! VERSION=$(sed -n 's/^VERSION=//p' "$WLANPI_RELEASE_FILE"); then
    echo "Error: Failed to read version file" >&2
    exit 1
fi

if [ -z "$VERSION" ]; then
    echo "Error: Empty version information" >&2
    exit 1
fi

if ! sed -i -E \
    -e "s|<txt-record>model=.*</txt-record>|<txt-record>model=$MODEL</txt-record>|" \
    -e "s|<txt-record>ver=.*</txt-record>|<txt-record>ver=$VERSION</txt-record>|" \
    "$SERVICE_FILE"; then
    echo "Error: Failed to update service file" >&2
    exit 1
fi

if ! grep -q "<txt-record>model=$MODEL</txt-record>" "$SERVICE_FILE" || \
   ! grep -q "<txt-record>ver=$VERSION</txt-record>" "$SERVICE_FILE"; then
    echo "Error: Failed to verify changes" >&2
    exit 1
fi