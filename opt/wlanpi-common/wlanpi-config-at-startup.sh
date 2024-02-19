#!/bin/bash

# Applies platform specific settings to WLAN Pi R4, M4, Pro at startup time

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

# Get WLAN Pi model
MODEL=$(wlanpi-model | grep "Main board:" | cut -d ":" -f2 | xargs)
debugger "Detected WLAN Pi model: $MODEL"

########## R4 ##########

# Apply RPi4 platform specific settings
if [[ "$MODEL" == "Raspberry Pi 4" ]]; then
    echo "Applying WLAN Pi R4 settings"

    # Disable Bluetooth on USB adapters, use RPi4 Bluetooth built into the SoC instead, prevents hci0 and hci1 confusion
    if [ ! -f "/etc/modprobe.d/blacklist-btusb.conf" ]; then
        echo "blacklist btusb" > /etc/modprobe.d/blacklist-btusb.conf
        REQUIRES_REBOOT=1
    fi

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

    # Set USB 2.0 controller OTG mode to 0
    if grep -q -E "^\s*otg_mode=1" /boot/config.txt; then
        debugger "Setting otg_mode to 0"
        sed -i "s/^\s*otg_mode=1/otg_mode=0/" /boot/config.txt
        REQUIRES_REBOOT=1
    elif grep -q -E "^\s*otg_mode=0" /boot/config.txt; then
        debugger "otg_mode is already set to 0, no action needed"
    else
        debugger "otg_mode line not found in config file, creating a new line in CM4 section"
        sed -i "s/\[cm4\]/&\notg_mode=0/" /boot/config.txt
        REQUIRES_REBOOT=1
    fi

    # Set USB mode to otg mode
    CM4_LINE_NUMBER=$(grep -n "\[cm4\]" /boot/config.txt | cut -d ":" -f1)
    LINES_BELOW_CM4=$(sed -n '/\[cm4\]/,/\[*\]/p' /boot/config.txt | grep -n "dtoverlay=dwc2,dr_mode=host" | cut -d ":" -f1)
    if [[ $CM4_LINE_NUMBER -gt 0 ]] && [[ $LINES_BELOW_CM4 -gt 0 ]]; then
        DR_MODE_LINE_NUMBER=$(($CM4_LINE_NUMBER + $LINES_BELOW_CM4 - 1))
        debugger "Found \"dtoverlay=dwc2,dr_mode=host\" CM4 config on line $DR_MODE_LINE_NUMBER"
        debugger "Setting CM4 USB to otg mode"
        sed -i "${DR_MODE_LINE_NUMBER}s/.*/dtoverlay=dwc2,dr_mode=otg/" /boot/config.txt
        REQUIRES_REBOOT=1
    elif ! sed -n '/\[cm4\]/,/\[*\]/p' /boot/config.txt | grep -q "^\s*dtoverlay=dwc2,dr_mode=otg"; then
        debugger "USB mode setting not found in config file, creating a new line in CM4 section"
        sed -i "s/\[cm4\]/&\ndtoverlay=dwc2,dr_mode=otg\n/" /boot/config.txt
        REQUIRES_REBOOT=1
    else
        debugger "USB mode is already set to otg mode, no action needed"
    fi

fi

########## M4 ##########

# Apply M4 platform specific settings
if [[ "$MODEL" == "Mcuzone M4" ]]; then
    echo "Applying WLAN Pi M4 settings"

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

    # Set USB 2.0 controller OTG mode to 1
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

    # Enable pcie-32bit-dma overlay for MediaTek Wi-Fi 6E MT7921K and MT7922A adapters to work
    if lspci -nn | grep -q -E "14c3:0608|14c3:0616"; then
        if ! sed -n '/\[cm4\]/,/\[*\]/p' /boot/config.txt | grep -q "^\s*dtoverlay=pcie-32bit-dma"; then
            debugger "pcie-32bit-dma overlay not enabled in cm4 config section, enabling it now"
            if sed -n '/\[cm4\]/,/\[*\]/p' /boot/config.txt | grep -q "^\s*#dtoverlay=pcie-32bit-dma"; then
                sed -i "s/^\s*#dtoverlay=pcie-32bit-dma/dtoverlay=pcie-32bit-dma/" /boot/config.txt
            else
                sed -i "s/\[cm4\]/&\n# Allows MT7921K adapter to work with 64-bit kernel\ndtoverlay=pcie-32bit-dma\n/" /boot/config.txt
            fi
            REQUIRES_REBOOT=1
        else
            debugger "pcie-32bit-dma overlay is already enabled, no action needed"
        fi
    else
        if sed -n '/\[cm4\]/,/\[*\]/p' /boot/config.txt | grep -q "^\s*dtoverlay=pcie-32bit-dma"; then
            debugger "pcie-32bit-dma is enabled but non-MediaTek M.2 adapter is used, disabling 32-bit DMA overlay now"
            sed -i "s/^\s*dtoverlay=pcie-32bit-dma/#dtoverlay=pcie-32bit-dma/" /boot/config.txt
            REQUIRES_REBOOT=1
        fi
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

########## M4+ ##########

# Apply M4+ platform specific settings
if [[ "$MODEL" == "Mcuzone M4+" ]]; then
    echo "Applying WLAN Pi M4+ settings"

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

    # Enable OTG by setting USB 2.0 controller OTG mode to 0
    if grep -q -E "^\s*otg_mode=1" /boot/config.txt; then
        debugger "otg_mode is currently set to 1, comment the line out"
        sed -i "s/^\s*otg_mode=1/#otg_mode=1/" /boot/config.txt
        REQUIRES_REBOOT=1
    fi

    # Set USB ports to otg mode
    CM4_LINE_NUMBER=$(grep -n "\[cm4\]" /boot/config.txt | cut -d ":" -f1)
    LINES_BELOW_CM4=$(sed -n '/\[cm4\]/,/\[*\]/p' /boot/config.txt | grep -n "dtoverlay=dwc2,dr_mode=host" | cut -d ":" -f1)
    if [[ $CM4_LINE_NUMBER -gt 0 ]] && [[ $LINES_BELOW_CM4 -gt 0 ]]; then
        DR_MODE_LINE_NUMBER=$(($CM4_LINE_NUMBER + $LINES_BELOW_CM4 - 1))
        debugger "Found \"dtoverlay=dwc2,dr_mode=host\" CM4 config on line $DR_MODE_LINE_NUMBER"
        debugger "Setting CM4 USB to otg mode"
        sed -i "${DR_MODE_LINE_NUMBER}s/.*/dtoverlay=dwc2,dr_mode=otg/" /boot/config.txt
        REQUIRES_REBOOT=1
    elif ! sed -n '/\[cm4\]/,/\[*\]/p' /boot/config.txt | grep -q "^\s*dtoverlay=dwc2,dr_mode=otg"; then
        debugger "USB mode setting not found in config file, creating a new line in CM4 section"
        sed -i "s/\[cm4\]/&\ndtoverlay=dwc2,dr_mode=otg\n/" /boot/config.txt
        REQUIRES_REBOOT=1
    else
        debugger "USB mode is already set to otg mode, no action needed"
    fi

    # Enable pcie-32bit-dma overlay for MediaTek Wi-Fi 6E MT7921K and MT7922A adapters to work
    if lspci -nn | grep -q -E "14c3:0608|14c3:0616"; then
        if ! sed -n '/\[cm4\]/,/\[*\]/p' /boot/config.txt | grep -q "^\s*dtoverlay=pcie-32bit-dma"; then
            debugger "pcie-32bit-dma overlay not enabled in cm4 config section, enabling it now"
            if sed -n '/\[cm4\]/,/\[*\]/p' /boot/config.txt | grep -q "^\s*#dtoverlay=pcie-32bit-dma"; then
                sed -i "s/^\s*#dtoverlay=pcie-32bit-dma/dtoverlay=pcie-32bit-dma/" /boot/config.txt
            else
                sed -i "s/\[cm4\]/&\n# Allows MT7921K adapter to work with 64-bit kernel\ndtoverlay=pcie-32bit-dma\n/" /boot/config.txt
            fi
            REQUIRES_REBOOT=1
        else
            debugger "pcie-32bit-dma overlay is already enabled, no action needed"
        fi
    else
        if sed -n '/\[cm4\]/,/\[*\]/p' /boot/config.txt | grep -q "^\s*dtoverlay=pcie-32bit-dma"; then
            debugger "pcie-32bit-dma is enabled but non-MediaTek M.2 adapter is used, disabling 32-bit DMA overlay now"
            sed -i "s/^\s*dtoverlay=pcie-32bit-dma/#dtoverlay=pcie-32bit-dma/" /boot/config.txt
            REQUIRES_REBOOT=1
        fi
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

########## Pro ##########

# Apply WLAN Pi Pro platform specific settings
if [[ "$MODEL" == "WLAN Pi Pro" ]]; then
    echo "Applying WLAN Pi Pro settings"

    # Enable PCIe on WLAN Pi Pro if disabled. We disabled PCIe at boot by default as a workaround for M4.
    if grep -q -E "\s*dtparam=pcie=off" /boot/config.txt; then
        sed -i "s/\s*dtparam=pcie=off/dtparam=pcie=on/" /boot/config.txt
        debugger "PCIe is disabled, enabling it now"
        REQUIRES_REBOOT=1
    else
        debugger "PCIe is already enabled, no action needed"
    fi

    # Set USB 2.0 controller OTG mode to 0
    if grep -q -E "^\s*otg_mode=1" /boot/config.txt; then
        debugger "Setting otg_mode to 0"
        sed -i "s/^\s*otg_mode=1/otg_mode=0/" /boot/config.txt
        REQUIRES_REBOOT=1
    elif grep -q -E "^\s*otg_mode=0" /boot/config.txt; then
        debugger "otg_mode is already set to 0, no action needed"
    else
        debugger "otg_mode line not found in config file, creating a new line in CM4 section"
        sed -i "s/\[cm4\]/&\notg_mode=0/" /boot/config.txt
        REQUIRES_REBOOT=1
    fi

    # Set USB ports to otg mode
    CM4_LINE_NUMBER=$(grep -n "\[cm4\]" /boot/config.txt | cut -d ":" -f1)
    LINES_BELOW_CM4=$(sed -n '/\[cm4\]/,/\[*\]/p' /boot/config.txt | grep -n "dtoverlay=dwc2,dr_mode=host" | cut -d ":" -f1)
    if [[ $CM4_LINE_NUMBER -gt 0 ]] && [[ $LINES_BELOW_CM4 -gt 0 ]]; then
        DR_MODE_LINE_NUMBER=$(($CM4_LINE_NUMBER + $LINES_BELOW_CM4 - 1))
        debugger "Found \"dtoverlay=dwc2,dr_mode=host\" CM4 config on line $DR_MODE_LINE_NUMBER"
        debugger "Setting CM4 USB to otg mode"
        sed -i "${DR_MODE_LINE_NUMBER}s/.*/dtoverlay=dwc2,dr_mode=otg/" /boot/config.txt
        REQUIRES_REBOOT=1
    elif ! sed -n '/\[cm4\]/,/\[*\]/p' /boot/config.txt | grep -q "^\s*dtoverlay=dwc2,dr_mode=otg"; then
        debugger "USB mode setting not found in config file, creating a new line in CM4 section"
        sed -i "s/\[cm4\]/&\ndtoverlay=dwc2,dr_mode=otg\n/" /boot/config.txt
        REQUIRES_REBOOT=1
    else
        debugger "USB mode is already set to otg mode, no action needed"
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