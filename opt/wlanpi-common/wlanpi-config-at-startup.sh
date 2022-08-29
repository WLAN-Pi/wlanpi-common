#!/bin/bash

# Applies platform specific settings to WLAN Pi R4 and M4 at startup time

# Author: Jiri Brejcha, jirka@jiribrejcha.net, @jiribrejcha

# Fail on script errors
set -e

SCRIPT_NAME="$(basename "$0")"
WAVESHARE_FILE="/boot/waveshare"
EEPROM_FILE="/opt/wlanpi-common/r4-eeprom-boot.conf"
REQUIRES_REBOOT=0

# Shows help
show_help(){
    echo "Applies platform specific settings to WLAN Pi R4 and M4 at startup time"
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

########## R4 ##########

# Apply RPi4 platform specific settings
if [[ "$MODEL" == "Raspberry Pi 4" ]]; then
    echo "Applying RPi4 settings"

    # Update EEPROM so that RPi4 powers down after shutdown
    if [ -f "$EEPROM_FILE" ]; then
        debugger "EEPROM file found, continuing"
        if rpi-eeprom-config | grep -q "POWER_OFF_ON_HALT=1" && rpi-eeprom-config | grep -q "WAKE_ON_GPIO=0" ; then
            debugger "EEPROM is already correctly configured, no action needed"
        else
            debugger "EEPROM needs to be updated, configuring it now"
            rpi-eeprom-config --apply "$EEPROM_FILE"
            REQUIRES_REBOOT=1
        fi
    fi
fi

########## M4 ##########

# Apply MCUzone platform specific settings
if [[ "$MODEL" == "MCUzone" ]]; then
    echo "Applying MCUzone settings"

    # Enable Waveshare display
    if [ ! -f "$WAVESHARE_FILE" ]; then
        debugger "Creating Waveshare file to enable display and buttons"
        touch "$WAVESHARE_FILE"
        systemctl restart wlanpi-fpms.service
    else
        debugger "Waveshare file already exists, no action needed"
    fi

    # If WLAN Pi Pro fan controller is enabled, disable the controller
    if grep -q -E "^\s*dtoverlay=gpio-fan,gpiopin=26" /boot/config.txt; then
        debugger "Fan controller is enabled, disabling it now"
        sed -i "s/^\s*dtoverlay=gpio-fan,gpiopin=26/#dtoverlay=gpio-fan,gpiopin=26/" /boot/config.txt
        REQUIRES_REBOOT=1
    else
        debugger "Fan controller is already disabled, no action needed"
    fi

    # Set USB OTG mode to 1
    if grep -q -E "^\s*#\s*otg_mode=1" /boot/config.txt; then
        debugger "Setting otg_mode to 1 by uncommenting the config line"
        sed -i "s/^\s*#\s*otg_mode=1/otg_mode=1/" /boot/config.txt
        REQUIRES_REBOOT=1
    elif grep -q -E "^\s*otg_mode=1" /boot/config.txt; then
        debugger "otg_mode is already set to 1, no action needed"
    else
        debugger "otg_mode line not found in config file, creating a new line in CM4 section"
        sed -i "s/\[cm4\]/&\notg_mode=1/" /boot/config.txt
        REQUIRES_REBOOT=1
    fi

    # Set USB ports to host mode
    CM4_LINE_NUMBER=$(grep -n "\[cm4\]" /boot/config.txt | cut -d ":" -f1)
    LINES_BELOW_CM4=$(sed -n '/\[cm4\]/,/\[*\]/p' /boot/config.txt | grep -n "dtoverlay=dwc2,dr_mode=otg" | cut -d ":" -f1)
    if [[ $CM4_LINE_NUMBER -gt 0 ]] && [[ $LINES_BELOW_CM4 -gt 0 ]]; then
        DR_MODE_LINE_NUMBER=$(($CM4_LINE_NUMBER + $LINES_BELOW_CM4 - 1))
        debugger "Found \"dtoverlay=dwc2,dr_mode=otg\" CM4 config on line $DR_MODE_LINE_NUMBER"
        debugger "Setting CM4 USB to host mode"
        sed -i "${DR_MODE_LINE_NUMBER}s/.*/dtoverlay=dwc2,dr_mode=host/" /boot/config.txt
        REQUIRES_REBOOT=1
    elif ! sed -n '/\[cm4\]/,/\[*\]/p' /boot/config.txt | grep -q "^\s*dtoverlay=dwc2,dr_mode=host"; then
        debugger "USB mode setting not found in config file, creating a new line in CM4 section"
        sed -i "s/\[cm4\]/&\ndtoverlay=dwc2,dr_mode=host\n/" /boot/config.txt
        REQUIRES_REBOOT=1
    else
        debugger "USB mode is already set to host mode, no action needed"
    fi

    # Enable pcie-32bit-dma overlay for MediaTek Wi-Fi 6E adapters to work
    if ! sed -n '/\[cm4\]/,/\[*\]/p' /boot/config.txt | grep -q "^\s*dtoverlay=pcie-32bit-dma"; then
        debugger "pcie-32bit-dma overlay not enabled in cm4 config section, enabling it now"
        sed -i "s/\[cm4\]/&\n# Allows MT7921K adapter to work with 64-bit kernel\ndtoverlay=pcie-32bit-dma\n/" /boot/config.txt
        REQUIRES_REBOOT=1
    else
        debugger "pcie-32bit-dma overlay is already enabled, no action needed"
    fi

    # Disable RTC
    if grep -q -E "^\s*dtoverlay=i2c-rtc,pcf85063a,addr=0x51" /boot/config.txt; then
        debugger "RTC is enabled, disabling it now"
        sed -i "s/^\s*dtoverlay=i2c-rtc,pcf85063a,addr=0x51/#dtoverlay=i2c-rtc,pcf85063a,addr=0x51/" /boot/config.txt
        REQUIRES_REBOOT=1
    else
        debugger "RTC is already disabled, no action needed"
    fi

    # Disable battery gauge
    if grep -q -E "^\s*dtoverlay=battery_gauge" /boot/config.txt; then
        debugger "Battery gauge is enabled, disabling it now"
        sed -i "s/^\s*dtoverlay=battery_gauge/#dtoverlay=battery_gauge/" /boot/config.txt
        REQUIRES_REBOOT=1
    else
        debugger "Battery gauge is already disabled, no action needed"
    fi

fi

# Reboot if required
if [ "$REQUIRES_REBOOT" -gt 0 ]; then
    echo "Reboot required, rebooting now"
    reboot
fi





# The rest of this script is commented out
# We have no plans to support SD card swapping between Pro and CE platforms

: '
########## Pro ##########

# Apply WLAN Pi Pro platform specific settings
if [[ "$MODEL" == "WLAN Pi Pro" ]]; then
    echo "Applying WLAN Pi Pro settings"

    # Disable Waveshare display
    if [ -f "$WAVESHARE_FILE" ]; then
        debugger "Waveshare file found, removing it now"
        rm "$WAVESHARE_FILE"
    fi

    # Enable WLAN Pi Pro fan controller if disabled
    if grep -q -E "\s*#\s*dtoverlay=gpio-fan,gpiopin=26" /boot/config.txt; then
        sed -i "s/\s*#\s*dtoverlay=gpio-fan,gpiopin=26/dtoverlay=gpio-fan,gpiopin=26/" /boot/config.txt
        debugger "Fan controller is disabled, enabling it now"
        REQUIRES_REBOOT=1
    else
        debugger "Fan controller is already enabled, no action needed"
    fi
fi

########## RPi4 ##########

# Apply RPi4 platform specific settings
if [[ "$MODEL" == "Raspberry Pi 4" ]]; then
    echo "Applying RPi4 settings"

    # Waveshare file is not needed on RPi4 - FPMS recognises RPi4
    if [ -f "$WAVESHARE_FILE" ]; then
        debugger "Waveshare file found, removing it now"
        rm "$WAVESHARE_FILE"
    fi

    # If WLAN Pi Pro fan controller is enabled, disable the controller
    if grep -q -E "^\s*dtoverlay=gpio-fan,gpiopin=26" /boot/config.txt; then
        debugger "Fan controller is enabled, disabling it now"
        sed -i "s/^\s*dtoverlay=gpio-fan,gpiopin=26/#dtoverlay=gpio-fan,gpiopin=26/" /boot/config.txt
        REQUIRES_REBOOT=1
    else
        debugger "Fan controller is already disabled, no action needed"
    fi
fi
'