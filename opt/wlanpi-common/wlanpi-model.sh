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

# Brief output mode only returns the WLAN Pi model - R4, R5, M4, M4+, Pro, Unknown platform
brief_output(){
    BRIEF_OUTPUT=1
}

# Shows help
show_help(){
    echo "Detects WLAN Pi and Wi-Fi adapter model"
    echo
    echo "The detected platform is cached in /etc/wlanpi-model after the"
    echo "first successful detection. Later calls skip detection when that"
    echo "file exists and the SoC family still matches. Moving an SD card"
    echo "between a Pro and an M4, or a Go CM4 to another platform, is not"
    echo "supported. Delete the cache file to force a new detection."
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

# Reports the M4+ USB mode. The dwc2 platform attribute
# (/sys/bus/platform/devices/*.usb/dr_mode) is not exported on the M4+, but the
# device tree property is world-readable and authoritative. Fall back to the USB
# device count when it is absent: the internal hub and Bluetooth being
# enumerated means host mode. Both paths are overridable so the helper can be
# tested.
USB_DR_MODE_GLOB="${USB_DR_MODE_GLOB:-/sys/firmware/devicetree/base/soc/usb@*/dr_mode}"
USB_DEVICES_PATH="${USB_DEVICES_PATH:-/sys/bus/usb/devices}"

CPUINFO="${CPUINFO:-/proc/cpuinfo}"
PRO_BATTERY_PRESENT="${PRO_BATTERY_PRESENT:-/sys/devices/platform/soc/fe804000.i2c/i2c-1/1-0055/power_supply/bq27546-0/present}"
MAX3421_COMPATIBLE_GLOB="${MAX3421_COMPATIBLE_GLOB:-/sys/firmware/devicetree/base/soc/spi@*/*/compatible}"
GO_DEVICE_INFO="${GO_DEVICE_INFO:-/home/.device-info/model}"
GO_SERIAL="${GO_SERIAL:-/dev/ttyAMA0}"
PLATFORM_CACHE="${PLATFORM_CACHE:-/etc/wlanpi-model}"
PCI_DEVICES_DIR="${PCI_DEVICES_DIR:-/sys/bus/pci/devices}"

go_serial_answers() {
    local tries=$1
    while [ "$tries" -gt 0 ]; do
        timeout 2 grep -q -m 1 -E "^14," "$GO_SERIAL" 2>/dev/null && return 0
        tries=$((tries - 1))
    done
    return 1
}

pro_battery_present() {
    grep -q "1" "$PRO_BATTERY_PRESENT" > /dev/null 2>&1
}

m4plus_eeprom_present() {
    timeout 3 i2cdetect -y 1 2>/dev/null | grep -q "50: 50"
}

go_device_info_says_go() {
    grep -i -q "^go$" "$GO_DEVICE_INFO" 2>/dev/null
}

max3421_overlay_present() {
    grep -qs max3421 $MAX3421_COMPATIBLE_GLOB
}

m4plus_prototype_ids() {
    timeout 3 lsusb | grep -q "2109:3431" && timeout 3 lspci -n | grep -q "1106:3483" && timeout 3 lspci -n | grep -q "1b21:1182"
}

cache_says_m4plus() {
    grep -q "M4+" "$PLATFORM_CACHE" 2>/dev/null
}

cached_model_name() {
    local raw
    [ -s "$PLATFORM_CACHE" ] || return 1
    raw=$(head -n 1 "$PLATFORM_CACHE" 2>/dev/null | tr -d '\r')
    raw="${raw#"${raw%%[![:space:]]*}"}"
    raw="${raw%"${raw##*[![:space:]]}"}"
    [ -n "$raw" ] || return 1
    printf '%s\n' "$raw"
}

soc_family() {
    if grep -q "Raspberry Pi 3 Model B Rev 1.2" "$CPUINFO" || grep -q "Raspberry Pi 4 Model B" "$CPUINFO"; then
        printf '%s\n' r4
    elif grep -q "Raspberry Pi 5 Model B" "$CPUINFO"; then
        printf '%s\n' r5
    elif grep -q "Raspberry Pi Compute Module 4" "$CPUINFO"; then
        printf '%s\n' cm4
    else
        printf '%s\n' unknown
    fi
}

cached_soc_family() {
    case "$1" in
        "WLAN Pi R4"|"R4") printf '%s\n' r4 ;;
        "WLAN Pi R5"|"R5") printf '%s\n' r5 ;;
        "WLAN Pi M4"|"M4"|"WLAN Pi M4+"|"M4+"|"WLAN Pi Pro"|"Pro"|"WLAN Pi Go"|"Go")
            printf '%s\n' cm4 ;;
        *) printf '%s\n' unknown ;;
    esac
}

platform_cache_matches() {
    local cached cached_fam cpu_fam
    cached=$(cached_model_name) || return 1
    cached_fam=$(cached_soc_family "$cached")
    cpu_fam=$(soc_family)
    [ "$cached_fam" != unknown ] && [ "$cpu_fam" != unknown ] && [ "$cached_fam" = "$cpu_fam" ]
}

write_platform_cache() {
    local model=$1 dir tmp
    [ -n "$model" ] || return 0
    dir=$(dirname -- "$PLATFORM_CACHE")
    [ -d "$dir" ] && [ -w "$dir" ] || return 0
    tmp=$(mktemp "$dir/.wlanpi-model.XXXXXX") || return 0
    if printf '%s\n' "$model" > "$tmp" && chmod 0644 -- "$tmp" && mv -- "$tmp" "$PLATFORM_CACHE"; then
        return 0
    fi
    rm -f -- "$tmp"
    return 0
}

warn_unsupported() {
    echo "wlanpi-model: $1" >&2
    if command -v logger >/dev/null 2>&1; then
        logger -t wlanpi-model -- "$1" || true
    fi
}

warn_if_unsupported_move() {
    local cached=$1
    case "$cached" in
        "WLAN Pi Pro"|"Pro")
            if ! pro_battery_present; then
                warn_unsupported "cached platform is Pro, but the Pro battery gauge is not present. Moving an SD card between a Pro and an M4 is not supported."
            fi
            ;;
        "WLAN Pi M4"|"M4")
            if pro_battery_present; then
                warn_unsupported "cached platform is M4, but a Pro battery gauge is present. Moving an SD card between a Pro and an M4 is not supported."
            fi
            ;;
        "WLAN Pi Go"|"Go")
            if ! max3421_overlay_present && ! go_device_info_says_go; then
                warn_unsupported "cached platform is Go, but this board has no Go overlay and no Go device-info. Moving a Go CM4 to another platform is not supported."
            fi
            ;;
    esac
}

emit_model() {
    local brief=$1
    local model=$2
    local board=$3
    if [ "$BRIEF_OUTPUT" -ne 0 ]; then
        echo "$brief"
    else
        echo "Model:                $model"
        echo "Main board:           $board"
    fi
}

emit_m4plus_usb_mode() {
    emit_model "M4+" "WLAN Pi M4+" "Mcuzone M4+"
    if [ "$BRIEF_OUTPUT" -eq 0 ]; then
        echo "USB mode:             $(usb_mode)"
    fi
}

report_go() {
    debugger "Detected Go"
    emit_model "Go" "WLAN Pi Go" "Oscium Go"
    write_platform_cache "WLAN Pi Go"
    debugger "End script now. Platform is Go."
}

emit_cached_platform() {
    local cached brief model board
    cached=$(cached_model_name)
    warn_if_unsupported_move "$cached"
    case "$cached" in
        "WLAN Pi R4"|"R4")
            brief=R4
            model="WLAN Pi R4"
            board=$(grep "Raspberry Pi 4 Model B" "$CPUINFO" | cut -d " " -f2-)
            [ -n "$board" ] || board="Raspberry Pi 4"
            emit_model "$brief" "$model" "$board"
            ;;
        "WLAN Pi R5"|"R5")
            brief=R5
            model="WLAN Pi R5"
            board=$(grep "Raspberry Pi 5 Model B" "$CPUINFO" | cut -d " " -f2-)
            [ -n "$board" ] || board="Raspberry Pi 5"
            emit_model "$brief" "$model" "$board"
            ;;
        "WLAN Pi M4"|"M4")
            emit_model "M4" "WLAN Pi M4" "Mcuzone M4"
            ;;
        "WLAN Pi M4+"|"M4+")
            emit_m4plus_usb_mode
            ;;
        "WLAN Pi Pro"|"Pro")
            emit_model "Pro" "WLAN Pi Pro" "WLAN Pi Pro"
            ;;
        "WLAN Pi Go"|"Go")
            emit_model "Go" "WLAN Pi Go" "Oscium Go"
            ;;
    esac
    debugger "Used cached platform from $PLATFORM_CACHE: $cached"
}

pci_card_instantiated() {
    local net="$PCI_DEVICES_DIR/$1/net"
    local iface
    [ -d "$net" ] || return 1
    for iface in "$net"/*; do
        [ -e "$iface" ] && return 0
    done
    return 1
}

pci_sysfs_addr() {
    case "$1" in
        *:*:*.*) printf '%s\n' "$1" ;;
        *:*.*) printf '%s\n' "0000:$1" ;;
        *) return 1 ;;
    esac
}

print_m2_wifi_adapters() {
    local line addr sysfs name any=0
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        addr=${line%% *}
        sysfs=$(pci_sysfs_addr "$addr") || continue
        name=$(printf '%s\n' "$line" | cut -d ":" -f 3- | cut -c 2-)
        if pci_card_instantiated "$sysfs"; then
            echo "M.2 Wi-Fi adapter:    $name"
        else
            echo "M.2 Wi-Fi adapter:    $name (enumerated, not instantiated)"
        fi
        any=1
    done
    [ "$any" -eq 1 ]
}

usb_mode() {
    local dr_mode usb_devices
    # shellcheck disable=SC2086  # the glob must expand
    dr_mode=$(cat $USB_DR_MODE_GLOB 2>/dev/null | tr -d '\0' | head -n 1)
    case "$dr_mode" in
        host)
            echo "Host - Bluetooth and USB-A ports enabled"
            ;;
        otg | peripheral)
            echo "OTG - Bluetooth and USB-A ports disabled"
            ;;
        *)
            usb_devices=$(find "$USB_DEVICES_PATH" -maxdepth 1 -mindepth 1 ! -name "*:*" 2>/dev/null | wc -l)
            if [ "$usb_devices" -gt 1 ]; then
                echo "Host - Bluetooth and USB-A ports enabled"
            else
                echo "OTG - Bluetooth and USB-A ports disabled"
            fi
            ;;
    esac
}

if [ ! -d "/boot/firmware" ] && [ ! -d "/boot" ]; then
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
if [ "$EARLY_BOOT" -eq 1 ] && [ -s "$PLATFORM_CACHE" ]; then
    SKIP_PROBES=1
fi

if platform_cache_matches; then
    debugger "Platform cache matches this SoC family"
    emit_cached_platform

# Is it Raspberry Pi 3? It isn't officially supported but let's pretend it is R4.
elif grep -q "Raspberry Pi 3 Model B Rev 1.2" "$CPUINFO"; then
    if [ "$BRIEF_OUTPUT" -ne 0 ];then
        echo "R4"
    else
        echo "Main board:           Raspberry Pi 4"
    fi
    debugger "End script now. Platform is Raspberry Pi 3 pretending to be Raspberry Pi 4."

# Is it Raspberry Pi 4?
elif grep -q "Raspberry Pi 4 Model B" "$CPUINFO"; then
    emit_model "R4" "WLAN Pi R4" "$(grep "Raspberry Pi 4 Model B" "$CPUINFO" | cut -d " " -f2-)"
    write_platform_cache "WLAN Pi R4"
    debugger "End script now. Platform is Raspberry Pi 4."

elif grep -q "Raspberry Pi 5 Model B" "$CPUINFO"; then
    emit_model "R5" "WLAN Pi R5" "$(grep "Raspberry Pi 5 Model B" "$CPUINFO" | cut -d " " -f2-)"
    write_platform_cache "WLAN Pi R5"
    debugger "End script now. Platform is Raspberry Pi 5."

# Is it powered by CM4?
elif grep -q "Raspberry Pi Compute Module 4" "$CPUINFO"; then
    debugger "Powered by CM4"

    # Sleep is only required at boot time for PCIe and i2c battery fuel gauge to initialise
    if [ "$EARLY_BOOT" -eq 1 ]; then
        sleep 1
    fi

    if pro_battery_present; then
        debugger "Found WLAN Pi Pro i2c Texas Instruments battery fuel gauge"
        emit_model "Pro" "WLAN Pi Pro" "WLAN Pi Pro"
        write_platform_cache "WLAN Pi Pro"
        debugger "End script now. Platform is WLAN Pi Pro."

    elif m4plus_eeprom_present; then
        debugger "Detected M4+ Mcuzone EEPROM"
        emit_m4plus_usb_mode
        write_platform_cache "WLAN Pi M4+"
        debugger "End script now. Platform is M4+."

    elif go_device_info_says_go; then
        report_go

    elif go_serial_answers 1; then
        report_go

    elif max3421_overlay_present && go_serial_answers 2; then
        report_go

    elif max3421_overlay_present; then
        report_go

    elif [ "$SKIP_PROBES" -eq 0 ] && m4plus_prototype_ids; then
        debugger "Found ID 2109:3431 VIA Labs, Inc. Hub in lsusb"
        debugger "Found USB controller: VIA Technologies, Inc. VL805/806 xHCI USB 3.0 Controller (rev 01) in lspci"
        debugger "Found PCI bridge: ASMedia Technology Inc. ASM1182e 2-Port PCIe x1 Gen2 Packet Switch in lspci"
        emit_model "M4+" "WLAN Pi M4+" "Mcuzone M4+"
        write_platform_cache "WLAN Pi M4+"
        debugger "End script now. Platform is M4+ prototype with PCIe packet switch."

    elif [ ! -r /dev/i2c-1 ] && cache_says_m4plus; then
        debugger "Cannot access i2c bus, using cached model from $PLATFORM_CACHE"
        emit_m4plus_usb_mode
        debugger "End script now. Platform is M4+ from cached model."

    else
        emit_model "M4" "WLAN Pi M4" "Mcuzone M4"
        write_platform_cache "WLAN Pi M4"
        debugger "End script now. Platform is M4."
    fi

else
    echo "Unknown platform"
    debugger "End script now. Platform is unknown."
fi
# List installed adapters. Skipped in brief mode and when SKIP_PROBES is set
# (early boot with a cached model): these USB/PCIe probes block for tens of
# seconds, and boot-time callers only need Model/Main board. Normal, post-boot
# invocations still list adapters.
if [ "$BRIEF_OUTPUT" -eq 0 ] && [ "$SKIP_PROBES" -eq 0 ]; then
    USB_WIFI_ADAPTER=$(timeout 3 lsusb | grep -i -E "Wireless|Wi-Fi|Wi_Fi|WiFi" | grep -v -E "0489:e0e2|0e8d:0608" | cut -d " " -f 6-)
    BLUETOOTH_ADAPTER=$(timeout 3 lsusb | grep -i -E "Bluetooth|0489:e0e2|0e8d:0608|8087:0036" | cut -d " " -f 6-)
    M2_LISTED=0
    if timeout 3 lspci -nn 2>/dev/null | grep -i -E "Wireless|Wi-Fi|Wi_Fi|WiFi" | print_m2_wifi_adapters; then
        M2_LISTED=1
    fi

    IFS="
"

    if [ -n "$USB_WIFI_ADAPTER" ]; then
        debugger "Found USB Wi-Fi adapter"
        for item in $USB_WIFI_ADAPTER
        do
            echo "USB Wi-Fi adapter:    $item"
        done
    fi

    if [ -z "$USB_WIFI_ADAPTER" ] && [ "$M2_LISTED" -eq 0 ]; then
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
            # Any adapter: numbers follow probe order, so the onboard one can be hci1
            if timeout 3 hciconfig | grep -q "^hci[0-9]"; then
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
