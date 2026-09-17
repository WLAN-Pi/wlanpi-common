#!/bin/bash

# This script regularly checks for WLAN Pi package updates and new software image

# Author: Jiri Brejcha, jirka@jiribrejcha.net, @jiribrejcha

while true; do
    # Check for number of upgradeable WLAN Pi packages
    declare -i NUMBER_OF_PACKAGES
    NUMBER_OF_PACKAGES=$(/opt/wlanpi-common/wlanpi-update.sh -c)
    if [ "$NUMBER_OF_PACKAGES" -gt 0 ]; then
        echo "$NUMBER_OF_PACKAGES" > /tmp/wlanpi-update-packages
    else
        # All WLAN Pi packages are up-to-date
        rm -f /tmp/wlanpi-update-packages
    fi

    # Check if new image is available for download.
    # On check failure keep the previous result instead of losing it.
    IMAGE_CHECK=$(/opt/wlanpi-common/wlanpi-update.sh -i 2>/dev/null)
    if [ $? -eq 0 ]; then
        if echo "$IMAGE_CHECK" | grep -q "New software image is available for download"; then
            LATEST_IMAGE=$(echo "$IMAGE_CHECK" | sed -n 's/^Latest image: //p')
            if [ -n "$LATEST_IMAGE" ]; then
                echo "$LATEST_IMAGE" > /tmp/wlanpi-update-image
            fi
        elif echo "$IMAGE_CHECK" | grep -qE "latest stable release|bleeding edge release"; then
            # Running the latest image already
            rm -f /tmp/wlanpi-update-image
        fi
    fi

    # Check updates every 24 hours (86400 seconds)
    sleep 86400
done
