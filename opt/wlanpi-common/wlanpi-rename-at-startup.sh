#!/bin/bash

# Creates a unique name for  WLAN Pi at startup in this format "wlanpi-<the last 3 characters of eth0 MAC address>" 

# Author: Jiri Brejcha, jirka@jiribrejcha.net, @jiribrejcha

# Check if the script is running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must run as root. Add \"sudo\" please".
   exit 1
fi

SCRIPT_NAME=$(echo ${0##*/})

# Get the last 3 chars of eth0 MAC address
LAST_3_CHARS_MAC=$(sed s/://g /sys/class/net/eth0/address | grep -o '...$')

# Check if we got 3 chars
if [ ${#LAST_3_CHARS_MAC} -eq 3 ]; then
    ./wlanpi-hostname.sh set "wlanpi-$LAST_3_CHARS_MAC"
    if [ "$?" != '0' ]; then
        logger "($SCRIPT_NAME) Hostname change at startup failed!"
        exit 1
    fi
else
    logger "($SCRIPT_NAME) Failed to parse eth0 MAC address, skipping hostname change!"
    exit 1
fi
