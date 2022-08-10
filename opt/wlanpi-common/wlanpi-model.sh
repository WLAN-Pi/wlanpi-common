#!/bin/bash

# This script detects WLAN Pi model

# Author: Jiri Brejcha, jirka@jiribrejcha.net, @jiribrejcha

# Fail on script errors
set -e

SCRIPT_NAME="$(basename "$0")"

# Shows help
show_help(){
    echo "Detects WLAN Pi model"
    echo
    echo "Usage:"
    echo "  $SCRIPT_NAME"
    echo
    echo "Options:"
    echo "  -d, --debug    Enable debugging output"
    echo "  -h, --help     Show this screen"
    echo
    exit 0
}

# Pass --debug argument to the script to enable debugging output
DEBUG=0
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -d|--debug) DEBUG=1 ;;
        -h|--help) show_help ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

# Displays debug output
debugger() {
    if [ "$DEBUG" -ne 0 ];then
      echo "Debugger: $1"
    fi
}

# Is it Raspberry Pi 4?
if grep -q "Raspberry Pi 4 Model B" /proc/cpuinfo; then
    echo "Raspberry Pi 4"
    debugger "End script now. Platform is Raspberry Pi 4."
    exit 0
fi

# Is it WLAN Pi Pro, MCUzone, or other platform?
# Powered by CM4?
if grep -q "Raspberry Pi Compute Module 4" /proc/cpuinfo; then
    debugger "Powered by CM4"

    # Look for Pericom 4-port PCI packet switch in lspci
    if lspci | grep -q "PCI bridge: Pericom Semiconductor PI7C9X2G404 EL/SL PCIe2 4-Port/4-Lane Packet Switch"; then
        debugger "Found Pericom packet switch. Potentially WLAN Pi Pro."

        # Look for VIA USB hub in lsusb
        if lsusb | grep -q "VIA Labs, Inc. Hub"; then
            debugger "Found VIA Labs USB hub. Potentially WLAN Pi Pro."
            echo "WLAN Pi Pro"
            debugger "End script now. Platform is WLAN Pi Pro."
            exit 0
        fi
    fi
    # Powered by CM4 and no Pro hardware found -> MCUzone
    LSPCILINES=$(lspci | wc -l)
    if [ $LSPCILINES -le 2 ]; then
        debugger "Found less than 2 lines in lspci"
        echo "MCUzone"
        debugger "End script now. Platform is MCUzone."
        exit 0
    fi

else
    # Not CM4 nor RPi4 -> Unknown platform
    echo "Unknown platform"
fi