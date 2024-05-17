#!/bin/bash

# This script regularly checks for WLAN Pi package updates and new software image

# Author: Jiri Brejcha, jirka@jiribrejcha.net, @jiribrejcha

while true; do
    # Check for number of upgradeable WLAN Pi packages
    NUMBER_OF_PACKAGES=$(/opt/wlanpi-common/wlanpi-update.sh -c)
    if [ "$NUMBER_OF_PACKAGES" -gt 0 ]; then
        echo "$NUMBER_OF_PACKAGES" > /tmp/wlanpi-update-packages
    else
        # All WLAN Pi packages are up-to-date
        rm -f /tmp/wlanpi-update-packages
    fi

    # Check if new image is available for download
    if /opt/wlanpi-common/wlanpi-update.sh -i | grep -q "New software image is available for download" ; then
        LATEST_IMAGE=$(/opt/wlanpi-common/wlanpi-update.sh -i | grep -Po 'Latest image: \K[0-9.]*')
        echo "$LATEST_IMAGE" > /tmp/wlanpi-update-image
    else
        # Running the latest image already
        rm -f /tmp/wlanpi-update-image
    fi

    # Check updates every 24 hours (86400 seconds)
    sleep 86400
done
