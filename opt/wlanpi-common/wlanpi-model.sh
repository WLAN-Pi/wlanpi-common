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

# Sleep is only required at boot time for PCIe and i2c battery fuel gauge to initialise
UPTIME="$(cut -f1 -d '.' /proc/uptime)"
if [[ "$UPTIME" -lt 60 ]]; then
    sleep 1
fi

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

# Is it an easter egg? Unofficial support to just "turn the lights on"
if grep -q "Raspberry Pi 3 Model B Rev 1.2" /proc/cpuinfo; then
    if [ "$BRIEF_OUTPUT" -ne 0 ];then
        echo "R4"
    else
        echo "Main board:           Raspberry Pi 4"
    fi
    debugger "End script now. Platform is Raspberry Pi 4."
fi

# Is it Raspberry Pi 4?
if grep -q "Raspberry Pi 4 Model B" /proc/cpuinfo; then
    if [ "$BRIEF_OUTPUT" -ne 0 ];then
        echo "R4"
    else
        echo "Main board:           Raspberry Pi 4"
    fi
    debugger "End script now. Platform is Raspberry Pi 4."

# Is it WLAN Pi Pro, Mcuzone, or other platform?
# Powered by CM4?
elif grep -q "Raspberry Pi Compute Module 4" /proc/cpuinfo; then
    debugger "Powered by CM4"

    # Look for WLAN Pi Pro i2c Texas Instruments battery fuel gauge
    if grep -q "1" /sys/devices/platform/soc/fe804000.i2c/i2c-1/1-0055/power_supply/bq27546-0/present; then
        debugger "Found WLAN Pi Pro i2c Texas Instruments battery fuel gauge"
        if [ "$BRIEF_OUTPUT" -ne 0 ];then
           echo "Pro"
        else
            echo "Main board:           WLAN Pi Pro"
        fi
            debugger "End script now. Platform is WLAN Pi Pro."
    fi
    # Powered by CM4 and no Pro hardware found -> Mcuzone
    LSPCI_LINES=$(lspci | wc -l)
    if [ $LSPCI_LINES -le 2 ]; then
        debugger "Found less than 2 lines in lspci"
        if [ "$BRIEF_OUTPUT" -ne 0 ];then
            echo "M4"
        else
            echo "Main board:           Mcuzone"
        fi
        debugger "End script now. Platform is Mcuzone."
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
