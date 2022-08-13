#!/bin/bash

# Applies platform specific settings to WLAN Pi Pro and CE at startup

# Author: Jiri Brejcha, jirka@jiribrejcha.net, @jiribrejcha

# Fail on script errors
set -e

SCRIPT_NAME="$(basename "$0")"
WAVESHARE_FILE="/boot/waveshare"

# Shows help
show_help(){
    echo "Applies platform specific settings to WLAN Pi Pro and CE at startup time"
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

# Pass debug argument to the script to enable debugging output
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

MODEL=$(wlanpi-model | grep "Main board:" | cut -d ":" -f2 | xargs)


########## MCUzone ##########

# Apply MCUzone platform specific settings
if [[ "$MODEL" == "MCUzone" ]]; then
    debugger "Applying MCUzone settings"

    # Enable Waveshare display
    debugger "Creating Waveshare file to enable display and buttons"
    touch "$WAVESHARE_FILE"

    # If WLAN Pi Pro fan controller is enabled, disable the controller
    if grep -q -E "^\s*dtoverlay=gpio-fan,gpiopin=26" /boot/config.txt; then
        debugger "Fan controller was enabled, disabling it now"
        sed -i "s/^\s*dtoverlay=gpio-fan,gpiopin=26/#dtoverlay=gpio-fan,gpiopin=26/" /boot/config.txt
    fi
fi

########## Pro ##########

# Apply WLAN Pi Pro platform specific settings
if [[ "$MODEL" == "WLAN Pi Pro" ]]; then
    debugger "Applying WLAN Pi Pro settings"

    # Disable Waveshare display
    if [ -f "$WAVESHARE_FILE" ]; then
        debugger "Waveshare file found, but not needed, removing it now"
        rm "$WAVESHARE_FILE"
    fi

    # Enable WLAN Pi Pro fan controller if disabled
    if grep -q -E "\s*#\s*dtoverlay=gpio-fan,gpiopin=26" /boot/config.txt; then
        sed -i "s/\s*#\s*dtoverlay=gpio-fan,gpiopin=26/dtoverlay=gpio-fan,gpiopin=26/" /boot/config.txt
    fi
fi

########## RPi4 ##########

# Apply RPi4 platform specific settings
if [[ "$MODEL" == "Raspberry Pi 4" ]]; then
    debugger "Applying RPi4 settings"

    # Waveshare file is not needed on RPi4 - FPMS recognises RPi4
    if [ -f "$WAVESHARE_FILE" ]; then
        debugger "Waveshare file found, but not needed, removing it now"
        rm "$WAVESHARE_FILE"
    fi

    # If WLAN Pi Pro fan controller is enabled, disable the controller
    if grep -q -E "^\s*dtoverlay=gpio-fan,gpiopin=26" /boot/config.txt; then
        debugger "Fan controller was enabled, disabling it now"
        sed -i "s/^\s*dtoverlay=gpio-fan,gpiopin=26/#dtoverlay=gpio-fan,gpiopin=26/" /boot/config.txt
    fi
fi