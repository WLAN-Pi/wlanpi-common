#!/bin/bash

WLANPI_MODEL_CMD="/usr/bin/wlanpi-model"
WLANPI_RELEASE_FILE="/etc/wlanpi-release"
SERVICE_FILE="/etc/avahi/services/wlanpi_announce.service"

for req in "$WLANPI_MODEL_CMD" "$WLANPI_RELEASE_FILE" "$SERVICE_FILE"; do
    if [ ! -f "$req" ]; then
        echo "Error: Required file $req not found!" >&2
        exit 1
    fi
done

if ! MODEL=$("$WLANPI_MODEL_CMD" | awk -F': +' '/^Model/ { print $2 }'); then
    echo "Error: Failed to get model information" >&2
    exit 1
fi

if [ -z "$MODEL" ]; then
    echo "Error: Empty model information" >&2
    exit 1
fi

if ! VERSION=$(sed 's/^VERSION=//' "$WLANPI_RELEASE_FILE"); then
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