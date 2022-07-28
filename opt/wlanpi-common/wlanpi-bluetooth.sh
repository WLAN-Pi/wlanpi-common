#!/bin/bash

# This script enables Bluetooth PAN on WLAN Pi, removes any previously paired devices, and allows you to connect mobile device to WLAN Pi via Bluetooth

# Author: Jiri Brejcha, jirka@jiribrejcha.net, @jiribrejcha

ALIAS=$(bt-adapter -a hci0 -i | grep Alias | awk '{ print $2 }')

# Remove previously paired Bluetooth device to enhance security
for DEVICE in $(bluetoothctl -- paired-devices | grep -iv 'no default controller' | cut -d " " -f2); do
    echo "Removing previously paired Bluetooth devices: $DEVICE"
    bluetoothctl -- remove "$DEVICE"
done

# Make WLAN Pi Bluetooth PAN network discoverable for 30 seconds and allow a new Bluetooth device to pair
systemctl start bt-timedpair
echo "Ready for you to connect:"
echo "1. Open Bluetooth settings on your mobile device"
echo "2. Connect to $ALIAS in 30 seconds from now"