#!/bin/bash

# Shows if WLAN Pi is powered by PoE, USB, or battery

# Author: Jiri Brejcha, jirka@jiribrejcha.net, @jiribrejcha

# Set up GPIO
/usr/bin/raspi-gpio set 9 ip pu
/usr/bin/raspi-gpio set 7 ip pu

# Main logic
if /usr/bin/raspi-gpio get 9 | grep -q "level=0"; then
    # level=0 means that PoE is present
    echo "Powered by PoE"
elif /usr/bin/raspi-gpio get 7 | grep -q "level=0"; then
    # level=0 means that USB power is present
    echo "Powered by USB"
else
    echo "Powered by battery"
fi
