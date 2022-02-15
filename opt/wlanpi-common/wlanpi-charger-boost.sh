#!/bin/bash

# Forces charger to draw up to 1.5 A

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
    echo "Forces charger to draw up to 1.5 A by enabling the boost"
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

# Enables charger boost
enable_boost(){
    /usr/bin/raspi-gpio set 21 op pd dh
}

# Disables charger boost
disable_boost(){
    /usr/bin/raspi-gpio set 21 op pd dh
}

#-------------
# Main logic
#-------------

# Process options and filter invalid input out
case $INPUT in
    -h | --help) usage ;;
    -v | --version) version ;;
    on | --on) enable_boost ;;
    off | --off) disable_boost ;;
    *) invalid_input ;;
esac
