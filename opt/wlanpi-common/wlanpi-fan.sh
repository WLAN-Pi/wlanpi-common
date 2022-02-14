#!/bin/bash

# Script to control WLAN Pi Pro fan

# Author: Jiri Brejcha, jirka@jiribrejcha.net, @jiribrejcha

INPUT="$1"
VERSION="1.0.0"
SCRIPT_NAME="$(basename "$0")"

# Display invalid input message
invalid_input(){
    echo "Error: Invalid argument was provided to the script. Use \"-h\" for help."
    exit 1
}

# Checks if we got an argument
    if [ $# -eq 0 ]; then
        invalid_input
        exit 1
    fi

# Shows supported arguments
usage(){
    echo "Controls the WLAN Pi Pro fan"
    echo
    echo "Usage:"
    echo "  $SCRIPT_NAME on"
    echo "  $SCRIPT_NAME off"
    echo
    echo "Options:"
    echo "  -v, --version  Show version"
    echo "  -h, --help     Show this screen"
    echo
}

# Shows version
version(){
    echo "$VERSION"
    exit 0
}

# Turns fan on
fan_on(){
    /usr/bin/raspi-gpio set 26 op pd dh
}

# Turns fan off
fan_off(){
    echo "WARNING: Disabling the fan might lead to overheating and permanent damage to the unit! Are you aware of the consequences? You are doing this at your own risk."
    sleep 5
    read -p "Disable the fan? (Yes/No): " confirm && [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] || exit 1
    /usr/bin/raspi-gpio set 26 op pd dl
}

#-------------
# Main logic
#-------------

# Process options and filter invalid input out
case $INPUT in
    -h | --help) usage ;;
    -v | --version) version ;;
    on | --on) fan_on ;;
    off | --off) fan_off ;;
    *) invalid_input ;;
esac
