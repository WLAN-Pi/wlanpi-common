#!/bin/bash

set -euo pipefail

FIRMWARE_DIR="/lib/firmware"
FIRMWARE_FILE="iwlwifi-gl-c0-fm-c0-92.ucode"
ORIGINAL_SUFFIX=".original"
DISABLED_SUFFIX=".disabled"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

error_exit() {
    log "ERROR: $1"
    exit 1
}

check_space() {
    local file="$1"
    local required_space
    local available_space
    
    if [ -f "$file" ]; then
        required_space=$(stat -c%s "$file")
        available_space=$(df --output=avail "$FIRMWARE_DIR" | tail -n1)
        available_space=$((available_space * 1024))
        [ "$available_space" -gt "$required_space" ] || error_exit "Insufficient space for backup ..."
    fi
}

verify_firmware() {
    local source="$1"
    local destination="$2"
    local checksum_source
    local checksum_dest
    
    checksum_source=$(sha256sum "$source" | awk '{print $1}')
    checksum_dest=$(sha256sum "$destination" | awk '{print $1}')
    [ "$checksum_source" = "$checksum_dest" ] || error_exit "Firmware file integrity check failed ..."
}

elevate() {
    if [ "$EUID" -ne 0 ]; then
        if ! sudo -n true 2>/dev/null; then
            echo "This script requires root privileges. Requesting sudo access ..."
        fi
        exec sudo "$0" "$@"
    fi
}

reset_wireless() {
    log "Resetting wireless modules ..."
    rmmod iwlmvm 2>/dev/null || log "iwlmvm module not loaded ..."
    rmmod iwlwifi 2>/dev/null || log "iwlwifi module not loaded ..."

    sleep 2
    
    modprobe iwlwifi || error_exit "Failed to load iwlwifi module ..."
    log "Wireless modules reset complete ..."
}

disable_firmware() {
    local full_path="$FIRMWARE_DIR/$FIRMWARE_FILE"
    local original="$full_path$ORIGINAL_SUFFIX"
    local disabled="$full_path$DISABLED_SUFFIX"

    if [ ! -f "$original" ]; then
        log "Creating original backup..."
        if [ -f "$full_path" ]; then
            check_space "$full_path"
            cp "$full_path" "$original" || error_exit "Failed to create original backup ..."
            verify_firmware "$full_path" "$original"
            log "Original backup created successfully ..."
        else
            error_exit "Firmware file not found: $full_path ..."
        fi
    fi

    if [ -f "$full_path" ]; then
        log "Moving firmware file to disabled state ..."
        mv "$full_path" "$disabled" || error_exit "Failed to disable firmware ..."
        [ -f "$disabled" ] || error_exit "Firmware file not present after disable ..."
        log "Firmware disabled ..."
        return 0
    else
        log "Firmware already disabled ..."
        return 1
    fi
}

enable_firmware() {
    local full_path="$FIRMWARE_DIR/$FIRMWARE_FILE"
    local disabled="$full_path$DISABLED_SUFFIX"
    local original="$full_path$ORIGINAL_SUFFIX"

    if [ -f "$disabled" ]; then
        log "Restoring firmware from disabled state ..."
        mv "$disabled" "$full_path" || error_exit "Failed to restore firmware ..."
        [ -f "$full_path" ] || error_exit "Firmware file not present after enable ..."
        
        if [ -f "$original" ]; then
            verify_firmware "$full_path" "$original"
            log "Firmware integrity verified against original backup ..."
        fi
        
        log "Firmware enabled ..."
        return 0 
    else
        error_exit "Disabled firmware file not found: $disabled"
    fi
}

verify_environment() {
    [ -d "$FIRMWARE_DIR" ] || error_exit "Firmware directory not found: $FIRMWARE_DIR ..."
    command -v sha256sum >/dev/null || error_exit "sha256sum command not found ..."
    command -v stat >/dev/null || error_exit "stat command not found ..."
}

UDEV_RULE_FILE="/etc/udev/rules.d/50-iwlwifi-disable-v92.rules"
UDEV_RULE_CONTENT='# Disable iwlwifi v92 firmware at boot - Intel BE200
ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x8086", ATTR{device}=="0x272b", RUN+="/bin/sh -c '\''test -f /lib/firmware/iwlwifi-gl-c0-fm-c0-92.ucode && mv /lib/firmware/iwlwifi-gl-c0-fm-c0-92.ucode /lib/firmware/iwlwifi-gl-c0-fm-c0-92.ucode.disabled'\''"'

install_udev_rule() {
    log "Installing udev rule to disable v92 at boot ..."
    echo "$UDEV_RULE_CONTENT" > "$UDEV_RULE_FILE" || error_exit "Failed to create udev rule ..."
    udevadm control --reload-rules || error_exit "Failed to reload udev rules ..."
    log "Udev rule installed. v92 will be disabled on next boot ..."
}

remove_udev_rule() {
    log "Removing udev rule ..."
    rm -f "$UDEV_RULE_FILE" || error_exit "Failed to remove udev rule ..."
    udevadm control --reload-rules || error_exit "Failed to reload udev rule ..."
    log "Udev rule removed. v92 will be available on next boot ..."
}

test_udev_rule() {
    local full_path="$FIRMWARE_DIR/$FIRMWARE_FILE"
    local disabled="$full_path$DISABLED_SUFFIX"
    
    log "Testing udev rule ..."
    
    if [ ! -f "$UDEV_RULE_FILE" ]; then
        error_exit "udev rule not installed. Run 'disable-boot' first ..."
    fi
    
    if [ -f "$full_path" ]; then
        log "Firmware is currently enabled. Moving to disabled state for test ..."
        mv "$full_path" "$disabled" || error_exit "Failed to move firmware ..."
    fi
    
    log "Unloading iwlwifi modules ..."
    rmmod iwlmvm 2>/dev/null || true
    rmmod iwlwifi 2>/dev/null || true
    
    sleep 1
    
    log "Triggering udev for Intel BE200 ..."
    udevadm trigger --subsystem-match=pci --attr-match=vendor=0x8086 --attr-match=device=0x272b
    
    sleep 2
    
    log "Loading iwlwifi driver ..."
    modprobe iwlwifi || error_exit "Failed to load iwlwifi ..."
    
    sleep 2
    
    log "Checking which firmware was loaded ..."
    local loaded_firmware=$(dmesg | tail -30 | grep "loaded firmware version" | tail -1)
    log "Firmware check: $loaded_firmware"
    if echo "$loaded_firmware" | grep -q "gl-c0-fm-c0-92.ucode"; then
        log "FAIL: v92 firmware was loaded"
        return 1
    else
        log "SUCCESS: v92 firmware was NOT loaded"
        return 0
    fi
}

check_args() {
    case "${1:-}" in
        "enable"|"disable"|"enable-boot"|"disable-boot"|"test-udev")
            return 0
            ;;
        *)
            echo "Usage: $0 {enable|disable|enable-boot|disable-boot|test-udev}"
            echo "  enable:       Enable v92 firmware for current session"
            echo "  disable:      Disable v92 firmware for current session"
            echo "  enable-boot:  Allow v92 to load at boot (remove udev rule)"
            echo "  disable-boot: Prevent v92 from loading at boot (install udev rule)"
            echo "  test-udev:    Test udev rule without rebooting"
            exit 1
            ;;
    esac
}

main() {
    check_args "$@"
    verify_environment
    elevate "$@"
    
    case "$1" in
        "enable")
            enable_firmware && reset_wireless
            ;;
        "disable")
            disable_firmware && reset_wireless
            ;;
        "enable-boot")
            remove_udev_rule
            ;;
        "disable-boot")
            install_udev_rule
            ;;
        "test-udev")
            test_udev_rule
            ;;
    esac
}

main "$@"