#!/usr/bin/env bash

# Script to determin WLAN Pi model/variant
# Author : Nigel Bowden
#
# This script inspects various platform attributes to determine
# which base architecture this script is running on and which 
# variant (if applicable)
#
# Models available:
#  - pro
#  - ce_rpi4 (vanilla RPi4)
#  - ce_rpi4/w (RPI4 with Waveshare OLED)
#  - ce_mz (Vanilla MCUZone in metal case)
#  - ce_mz/w (MCUZone with Waveshare OLED)
#
# Return values:
#
#   string: model variant from list above 
#
# Logging:
#   Log faiures to syslog
#

# fail on script errors
set -e

DEBUG=0
STATUS_FILE="/etc/wlanpi-state"
MODEL="pro"
SCRIPT_NAME=$(echo ${0##*/})

# check if the script is running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must run as root. Add \"sudo\" please".
   exit 1
fi

get_model() {

    # check if we're CM4
    if grep -q "Compute Module 4" /proc/cpuinfo ; then
        
        # check if we have usb3
        if [[ `lsusb | grep '3.0 root hub'` ]]; then 
            echo "pro"
            exit 0
        fi

        # must be a ce_mz or ce_mz/w
        if [ -f "/boot/waveshare" ]; then
            echo "ce_mz/w"
            exit 0
        fi

        echo "ce_mz"
        exit 0
    fi
    
    if grep -q "Raspberry Pi 4" /proc/cpuinfo ; then
        
        # must be a ce_rpi4 or ce_rpi4/w
        if [ -f "/boot/waveshare" ]; then
            echo "ce_rpi4/w"
            exit 0
        fi

        echo "ce_rpi4"
        exit 0
    fi

    echo "unknown"
    exit 0
}


# usage output
usage () {
        echo "Usage: wlanpi-model.sh { help }"
        echo ""
        echo "  wlanpi-model.sh: show WLAN Pi model"
        echo "  wlanpi-mode.sh help: show usage info"
        echo ""
        exit 0

}

# case statements
case "$1" in
  help)
        usage
        ;;
  *)
        get_model
        ;;
esac

exit 0