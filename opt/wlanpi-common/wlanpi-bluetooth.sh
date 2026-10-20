#!/bin/bash

# This script enables Bluetooth PAN on WLAN Pi, removes any previously paired devices, and allows you to connect mobile device to WLAN Pi via Bluetooth

# Author: Jiri Brejcha, jirka@jiribrejcha.net, @jiribrejcha

# hci0 can be a USB dongle, so use the adapter bt-agent set up. wlanpi-bluetooth
# releases without wlanpi-bt-adapter use hci0.
ADAPTER=$(wlanpi-bt-adapter 2>/dev/null)
ADAPTER=${ADAPTER:-hci0}

ALIAS=$(bt-adapter -a "$ADAPTER" -i | grep Alias | awk '{ print $2 }')

# Remove previously paired Bluetooth device to enhance security. Ask BlueZ for
# this adapter's paired devices: bluetoothctl only sees the default controller,
# and bt-device -l also lists unpaired ones.
for DEVICE in $(busctl --json=short call org.bluez / org.freedesktop.DBus.ObjectManager GetManagedObjects |
    jq -r --arg adapter "/org/bluez/$ADAPTER" '.data[0][]["org.bluez.Device1"] // empty | select(.Adapter.data == $adapter and .Paired.data) | .Address.data'); do
    echo "Removing previously paired Bluetooth devices: $DEVICE"
    bt-device -a "$ADAPTER" -r "$DEVICE"
done

# Make WLAN Pi Bluetooth PAN network discoverable for 30 seconds and allow a new Bluetooth device to pair
systemctl start bt-timedpair
echo "Ready for you to connect:"
echo "1. Open Bluetooth settings on your mobile device"
echo "2. Connect to $ALIAS in 30 seconds from now"
