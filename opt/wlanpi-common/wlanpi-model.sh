#!/bin/bash

# This script detects WLAN Pi model

# Author: Jiri Brejcha, jirka@jiribrejcha.net, @jiribrejcha

# Fail on script errors
set -e

SCRIPT_NAME="$(basename "$0")"

# Pass debug argument to the script to enable debugging output
DEBUG=0

# Show full output by default
BRIEF_OUTPUT=0

# Brief output mode only returns the WLAN Pi mode (R4, M4, Pro)
brief_output(){
    BRIEF_OUTPUT=1
}

# Shows help
show_help(){
    echo "Detects WLAN Pi and Wi-Fi adapter model"
    echo
    echo "Usage:"
    echo "  $SCRIPT_NAME"
    echo
    echo "Options:"
    echo "  -d, --debug    Enable debugging output"
    echo "  -b, --brief    Show only short model name"
    echo "  -h, --help     Show this screen"
    echo
    exit 0
}

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -d|--debug) DEBUG=1 ;;
        -h|--help) show_help ;;
        -b|--brief) brief_output ;;
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

# Brief output mode only returns the WLAN Pi mode (R4, M4, Pro)
brief_output(){
    BRIEF_OUTPUT=1
}

# Is it Raspberry Pi 4?
if grep -q "Raspberry Pi 4 Model B" /proc/cpuinfo; then
    if [ "$BRIEF_OUTPUT" -ne 0 ];then
        echo "R4"
    else
        echo "Main board:           Raspberry Pi 4"
    fi
    debugger "End script now. Platform is Raspberry Pi 4."

# Is it WLAN Pi Pro, MCUzone, or other platform?
# Powered by CM4?
elif grep -q "Raspberry Pi Compute Module 4" /proc/cpuinfo; then
    debugger "Powered by CM4"

    # Look for Pericom 4-port PCI packet switch in lspci
    if lspci | grep -q "PCI bridge: Pericom Semiconductor PI7C9X2G404 EL/SL PCIe2 4-Port/4-Lane Packet Switch"; then
        debugger "Found Pericom packet switch. Potentially WLAN Pi Pro."

        # Look for VIA USB hub in lsusb
        if lsusb | grep -q "VIA Labs, Inc. Hub"; then
            debugger "Found VIA Labs USB hub. Potentially WLAN Pi Pro."
            if [ "$BRIEF_OUTPUT" -ne 0 ];then
                echo "Pro"
            else
                echo "Main board:           WLAN Pi Pro"
            fi
            debugger "End script now. Platform is WLAN Pi Pro."
        fi
    fi
    # Powered by CM4 and no Pro hardware found -> MCUzone
    LSPCI_LINES=$(lspci | wc -l)
    if [ $LSPCI_LINES -le 2 ]; then
        debugger "Found less than 2 lines in lspci"
        if [ "$BRIEF_OUTPUT" -ne 0 ];then
            echo "M4"
        else
            echo "Main board:           MCUzone"
        fi
        debugger "End script now. Platform is MCUzone."
    fi
else
    # Not CM4 nor RPi4 -> Unknown platform
    if [ "$BRIEF_OUTPUT" -ne 0 ];then
        echo "?"
    else
        echo "Unknown platform"
    fi
fi

# List installed Wi-Fi adapters
USB_WIFI_ADAPTER=$(lsusb | grep -i -E "Wireless|Wi-Fi|Wi_Fi|WiFi" | grep -v -e "0608" | cut -d " " -f 6-)
M2_WIFI_ADAPTER=$(lspci | grep -i -E "Wireless|Wi-Fi|Wi_Fi|WiFi" | cut -d ":" -f 3- | cut -c 2-)

IFS="
"
if [ -n "$USB_WIFI_ADAPTER" ] && [ "$BRIEF_OUTPUT" -eq 0 ]; then
    debugger "Found USB Wi-Fi adapter"
    for item in $USB_WIFI_ADAPTER
    do
        echo "USB Wi-Fi adapter:    $item"
    done
fi

if [ -n "$M2_WIFI_ADAPTER" ] && [ "$BRIEF_OUTPUT" -eq 0 ]; then
    debugger "Found M.2 Wi-Fi adapter"
    for item in $M2_WIFI_ADAPTER
    do
        echo "M.2 Wi-Fi adapter:    $item"
    done
fi

if [ -z "$USB_WIFI_ADAPTER" ] && [ -z "$M2_WIFI_ADAPTER" ] && [ "$BRIEF_OUTPUT" -eq 0 ]; then
    echo "No Wi-Fi adapter"
fi
