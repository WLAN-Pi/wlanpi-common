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

# Brief output mode only returns the WLAN Pi model - R4, M4, M4+, Pro, Unknown platform
brief_output(){
    BRIEF_OUTPUT=1
}

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
    if [ "$DEBUG" -ne 0 ]; then
      echo "Debugger: $1"
    fi
}

if [ -d "/boot/firmware" ]; then
    CONFIG_FILE="/boot/firmware/config.txt"
elif [ -d "/boot" ]; then
    CONFIG_FILE="/boot/config.txt"
else
    echo "ERROR: Boot not found"
    exit 1
fi

# Boot-time callers (wlanpi-config-at-startup, avahi) only need Model and Main
# board, and the model is already cached in /etc/wlanpi-model from a previous
# boot. Probing USB/PCIe for them is unnecessary and can block for tens of
# seconds: lsusb blocks in read() on a USB string-descriptor sysfs attribute
# while a hub port retries enumeration. Only short-circuit when the model is
# already on disk; with no cache the full detection must run so the first boot
# records the correct model and board.
UPTIME="$(cut -f1 -d '.' /proc/uptime)"
EARLY_BOOT=0
if [ "$UPTIME" -lt 60 ]; then
    EARLY_BOOT=1
fi

SKIP_PROBES=0
if [ "$EARLY_BOOT" -eq 1 ] && [ -s /etc/wlanpi-model ]; then
    SKIP_PROBES=1
fi

# Is it Raspberry Pi 3? It isn't officially supported but let's pretend it is R4.
if grep -q "Raspberry Pi 3 Model B Rev 1.2" /proc/cpuinfo; then
    if [ "$BRIEF_OUTPUT" -ne 0 ];then
        echo "R4"
    else
        echo "Main board:           Raspberry Pi 4"
    fi
    debugger "End script now. Platform is Raspberry Pi 3 pretending to be Raspberry Pi 4."
fi

# Is it Raspberry Pi 4?
if grep -q "Raspberry Pi 4 Model B" /proc/cpuinfo; then
    if [ "$BRIEF_OUTPUT" -ne 0 ];then
        echo "R4"
    else
        echo "Model:                WLAN Pi R4"
        echo "Main board:           $(grep "Raspberry Pi 4 Model B" /proc/cpuinfo | cut -d " " -f2-)"
    fi
    debugger "End script now. Platform is Raspberry Pi 4."

# Is it powered by CM4?
elif grep -q "Raspberry Pi Compute Module 4" /proc/cpuinfo; then
    debugger "Powered by CM4"

    # Sleep is only required at boot time for PCIe and i2c battery fuel gauge to initialise
    if [ "$EARLY_BOOT" -eq 1 ]; then
        sleep 1
    fi

    # Look for WLAN Pi Pro i2c Texas Instruments battery fuel gauge
    if grep -q "1" /sys/devices/platform/soc/fe804000.i2c/i2c-1/1-0055/power_supply/bq27546-0/present > /dev/null 2>&1; then
        debugger "Found WLAN Pi Pro i2c Texas Instruments battery fuel gauge"
        if [ "$BRIEF_OUTPUT" -ne 0 ]; then
            echo "Pro"
        else
            echo "Model:                WLAN Pi Pro"
            echo "Main board:           WLAN Pi Pro"
        fi
        debugger "End script now. Platform is WLAN Pi Pro."

    # It is powered by CM4 but it isn't Pro


    # Is it Go?
    elif timeout 2 grep -q -m 1 -E "^14," /dev/ttyAMA0 2>/dev/null || grep -i -q "^go$" /home/.device-info/model 2>/dev/null; then
        debugger "Detected Go"
        if [ "$BRIEF_OUTPUT" -ne 0 ]; then
            echo "Go"
        else
            echo "Model:                WLAN Pi Go"
            echo "Main board:           Oscium Go"
        fi
        debugger "End script now. Platform is Go."

    # Is it M4+?
    elif timeout 3 i2cdetect -y 1 2>/dev/null | grep -q "50: 50"; then
            debugger "Detected M4+ Mcuzone EEPROM"
            if [ "$BRIEF_OUTPUT" -ne 0 ]; then
                echo "M4+"
            else
                echo "Model:                WLAN Pi M4+"
                echo "Main board:           Mcuzone M4+"
                if [ "$SKIP_PROBES" -eq 0 ] && grep -q -E "^\s*otg_mode=1" $CONFIG_FILE && [ "$(timeout 3 lsusb | wc -l)" -gt 1 ]; then
                    echo "USB mode:             Host - Bluetooth and USB-A ports enabled"
                else
                    echo "USB mode:             OTG - Bluetooth and USB-A ports disabled"
                fi
            fi
            debugger "End script now. Platform is M4+."

    # Is it M4+ prototype with PCIe packet switch? Skipped when the model is
    # cached and we are in early boot (see SKIP_PROBES): it probes USB/PCIe.
    elif [ "$SKIP_PROBES" -eq 0 ] && timeout 3 lsusb | grep -q "2109:3431" && timeout 3 lspci -n | grep -q "1106:3483" && timeout 3 lspci -n | grep -q "1b21:1182"; then
        debugger "Found ID 2109:3431 VIA Labs, Inc. Hub in lsusb"
        debugger "Found USB controller: VIA Technologies, Inc. VL805/806 xHCI USB 3.0 Controller (rev 01) in lspci"
        debugger "Found PCI bridge: ASMedia Technology Inc. ASM1182e 2-Port PCIe x1 Gen2 Packet Switch in lspci"
        if [ "$BRIEF_OUTPUT" -ne 0 ]; then
            echo "M4+"
        else
            echo "Model:                WLAN Pi M4+"
            echo "Main board:           Mcuzone M4+"
        fi
        debugger "End script now. Platform is M4+ prototype with PCIe packet switch."

    # Is it M4+ that we cannot probe directly? Unprivileged users (e.g. wlanpi-stats
    # at SSH login) cannot open /dev/i2c-1 to detect the Mcuzone EEPROM, and in OTG
    # mode the USB hub is not visible either, so trust the model cached at boot by
    # wlanpi-config-at-startup.sh running as root
    elif [ ! -r /dev/i2c-1 ] && grep -q "M4+" /etc/wlanpi-model 2>/dev/null; then
        debugger "Cannot access i2c bus, using cached model from /etc/wlanpi-model"
        if [ "$BRIEF_OUTPUT" -ne 0 ]; then
            echo "M4+"
        else
            echo "Model:                WLAN Pi M4+"
            echo "Main board:           Mcuzone M4+"
            if [ "$SKIP_PROBES" -eq 0 ] && grep -q -E "^\s*otg_mode=1" $CONFIG_FILE && [ "$(timeout 3 lsusb | wc -l)" -gt 1 ]; then
                echo "USB mode:             Host - Bluetooth and USB-A ports enabled"
            else
                echo "USB mode:             OTG - Bluetooth and USB-A ports disabled"
            fi
        fi
        debugger "End script now. Platform is M4+ from cached model."

    # Assume M4
    else
            # HDMI module is loaded (status 0)
        if [ "$BRIEF_OUTPUT" -ne 0 ]; then
            echo "M4"
        else
            echo "Model:                WLAN Pi M4"
            echo "Main board:           Mcuzone M4"
        fi
        debugger "End script now. Platform is M4."
    fi
fi
# List installed adapters. Skipped in brief mode and when SKIP_PROBES is set
# (early boot with a cached model): these USB/PCIe probes block for tens of
# seconds, and boot-time callers only need Model/Main board. Normal, post-boot
# invocations still list adapters.
if [ "$BRIEF_OUTPUT" -eq 0 ] && [ "$SKIP_PROBES" -eq 0 ]; then
    USB_WIFI_ADAPTER=$(timeout 3 lsusb | grep -i -E "Wireless|Wi-Fi|Wi_Fi|WiFi" | grep -v -E "0489:e0e2|0e8d:0608" | cut -d " " -f 6-)
    M2_WIFI_ADAPTER=$(timeout 3 lspci -nn | grep -i -E "Wireless|Wi-Fi|Wi_Fi|WiFi" | cut -d ":" -f 3- | cut -c 2-)
    BLUETOOTH_ADAPTER=$(timeout 3 lsusb | grep -i -E "Bluetooth|0489:e0e2|0e8d:0608|8087:0036" | cut -d " " -f 6-)

    IFS="
"

    if [ -n "$USB_WIFI_ADAPTER" ]; then
        debugger "Found USB Wi-Fi adapter"
        for item in $USB_WIFI_ADAPTER
        do
            echo "USB Wi-Fi adapter:    $item"
        done
    fi

    if [ -n "$M2_WIFI_ADAPTER" ]; then
        debugger "Found M.2 Wi-Fi adapter"
        for item in $M2_WIFI_ADAPTER
        do
            echo "M.2 Wi-Fi adapter:    $item"
        done
    fi

    if [ -z "$USB_WIFI_ADAPTER" ] && [ -z "$M2_WIFI_ADAPTER" ]; then
        echo "No Wi-Fi adapter"
    fi

    if [ -n "$BLUETOOTH_ADAPTER" ]; then
        debugger "Found Bluetooth adapter"
        for item in $BLUETOOTH_ADAPTER
        do
            # List Bluetooth adapters connected via USB
            echo "Bluetooth adapter:    $item"
        done
    else
        if command -v hciconfig &> /dev/null; then
            if timeout 3 hciconfig | grep -q "hci0"; then
                # Built-in Bluetooth adapter is present on Raspberry Pi
                echo "Bluetooth adapter:    Built-in"
            else
                echo "No Bluetooth adapter"
            fi
        else
            echo "Bluetooth tools (BlueZ) not installed (hciconfig not found)"
        fi
    fi
fi
