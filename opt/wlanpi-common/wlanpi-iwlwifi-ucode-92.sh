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

check_args() {
    case "${1:-}" in
        "enable"|"disable")
            return 0
            ;;
        *)
            echo "Usage: $0 {enable|disable}"
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
    esac
}

main "$@"