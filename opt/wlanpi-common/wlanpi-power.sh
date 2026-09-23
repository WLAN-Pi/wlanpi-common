#!/bin/bash

# Shows if WLAN Pi is powered by PoE, USB, or battery

# Author: Jiri Brejcha, jirka@jiribrejcha.net, @jiribrejcha

PINCTRL=${PINCTRL:-/usr/bin/pinctrl}

# Set up GPIO
if ! "$PINCTRL" set 7,9 ip pu; then
    echo "Failed to configure power-detection GPIOs" >&2
    exit 1
fi

# Main logic
if ! POE=$("$PINCTRL" lev 9); then
    echo "Failed to read PoE GPIO" >&2
    exit 1
fi

if [ "$POE" = 0 ]; then
    # level=0 means that PoE is present
    echo "Powered by PoE"
elif ! USB=$("$PINCTRL" lev 7); then
    echo "Failed to read USB GPIO" >&2
    exit 1
elif [ "$USB" = 0 ]; then
    # level=0 means that USB power is present
    echo "Powered by USB"
elif [ "$POE" = 1 ] && [ "$USB" = 1 ]; then
    echo "Powered by battery"
else
    echo "Invalid power-detection GPIO level" >&2
    exit 1
fi
