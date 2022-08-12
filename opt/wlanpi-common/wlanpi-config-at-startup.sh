#!/bin/bash

# Applies platform specific settings to WLAN Pi Pro and CE at startup

# Author: Jiri Brejcha, jirka@jiribrejcha.net, @jiribrejcha

# Fail on script errors
set -e

SCRIPT_NAME="$(basename "$0")"

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

# Apply MCUzone platform specific settings
if [[ "$MODEL" == "MCUzone" ]]; then
    debugger "Applying MCUzone settings"
    touch /tmp/MCUzone
fi

# Apply WLAN Pi Pro platform specific settings
if [[ "$MODEL" == "WLAN Pi Pro" ]]; then
    debugger "Applying WLAN Pi Pro settings"
    touch /tmp/Pro
fi

# Apply RPi4 platform specific settings
if [[ "$MODEL" == "Raspberry Pi 4" ]]; then
    debugger "Applying RPi4 settings"
    touch /tmp/RPi4
fi
