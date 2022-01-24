#!/bin/bash

# Creates a unique name for  WLAN Pi at startup in this format "wlanpi-<the last 3 characters of eth0 MAC address>" 

# Author: Jiri Brejcha, jirka@jiribrejcha.net, @jiribrejcha

SCRIPT_NAME=$(echo ${0##*/})
echo "Got script name: $SCRIPT_NAME"

# Check if the script is running as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must run as root. Add \"sudo\" please".
    echo "Not running as root"
    exit 1
else
    echo "Running as root"
fi

# Get the last 3 chars of eth0 MAC address
LAST_3_CHARS_MAC=$(sed s/://g /sys/class/net/eth0/address | grep -o '...$')
echo "Got these 3 chars: $LAST_3_CHARS_MAC"

# Check if we got 3 chars
if [ ${#LAST_3_CHARS_MAC} -ne 3 ]; then
    logger "($SCRIPT_NAME) Failed to parse eth0 MAC address, skipping hostname change!"
    echo "Did not get 3 chars"
    exit 1
fi

# If hostname matches wlanpi or wlanpi-<3-chars>, change it
if [ "$HOSTNAME" == "wlanpi" ] || echo "$HOSTNAME" | grep -q "^wlanpi-...$" ; then
    echo "Let's change hostname"
    wlanpi-hostname set "wlanpi-$LAST_3_CHARS_MAC"
    if [ "$?" != '0' ]; then
        logger "($SCRIPT_NAME) Hostname change failed!"
        echo "Hostname change failed!"
        exit 1
    else
        echo "Hostname successfully changed"
   fi
fi
