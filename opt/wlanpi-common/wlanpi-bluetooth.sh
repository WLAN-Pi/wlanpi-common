#!/bin/bash

# This script enables Bluetooth PAN on WLAN Pi, removes any previously paired devices, and allows you to connect mobile device to WLAN Pi via Bluetooth

# Author: Jiri Brejcha, jirka@jiribrejcha.net, @jiribrejcha

# hci0 can be a USB dongle, so use the adapter bt-agent set up. wlanpi-bluetooth
# releases without wlanpi-bt-adapter use hci0. If it fails, hci0 may not be the
# adapter bt-timedpair opens, so there is no fallback.
if ! command -v wlanpi-bt-adapter >/dev/null; then
    ADAPTER=hci0
elif ! ADAPTER=$(wlanpi-bt-adapter) || [[ ! $ADAPTER =~ ^hci[0-9]+$ ]]; then
    echo "Error: no Bluetooth adapter" >&2
    exit 1
fi

ALIAS=$(bt-adapter -a "$ADAPTER" -i | grep Alias | awk '{ print $2 }')

# Remove previously paired Bluetooth device to enhance security, and never open
# the pairing window with one left in place. bluetoothctl only sees the default
# controller, and busctl --json can't print GetManagedObjects while BlueZ holds
# a nearby device's ManufacturerData (a{qv}), so check each device object.
# Without the adapter, BlueZ is restarting and the listing can't show its
# pairings.
if ! TREE=$(busctl tree --list org.bluez) || ! grep -qx "/org/bluez/$ADAPTER" <<< "$TREE"; then
    echo "Error: could not list Bluetooth devices" >&2
    exit 1
fi
for DEVICE in $(grep -E "^/org/bluez/$ADAPTER/dev_[0-9A-F_]+$" <<< "$TREE"); do
    if ! PAIRED=$(busctl get-property org.bluez "$DEVICE" org.bluez.Device1 Paired 2>/dev/null); then
        # BlueZ drops a device it only saw nearby soon after a scan, maybe
        # since the listing. Paired devices are never dropped.
        if NOW=$(busctl tree --list org.bluez) && grep -qx "/org/bluez/$ADAPTER" <<< "$NOW" &&
            ! grep -qx "$DEVICE" <<< "$NOW"; then
            continue
        fi
        echo "Error: could not read $DEVICE" >&2
        exit 1
    fi
    case $PAIRED in
        "b true") ;;
        "b false") continue ;;
        *)
            echo "Error: could not read $DEVICE" >&2
            exit 1
            ;;
    esac
    MAC=${DEVICE##*/dev_}
    MAC=${MAC//_/:}
    echo "Removing previously paired Bluetooth devices: $MAC"
    if ! busctl call org.bluez "/org/bluez/$ADAPTER" org.bluez.Adapter1 RemoveDevice o "$DEVICE"; then
        echo "Error: could not remove $MAC" >&2
        exit 1
    fi
done

# Make WLAN Pi Bluetooth PAN network discoverable for 30 seconds and allow a new Bluetooth device to pair
if ! systemctl start bt-timedpair; then
    echo "Error: could not make Bluetooth discoverable" >&2
    exit 1
fi
echo "Ready for you to connect:"
echo "1. Open Bluetooth settings on your mobile device"
echo "2. Connect to $ALIAS in 30 seconds from now"
