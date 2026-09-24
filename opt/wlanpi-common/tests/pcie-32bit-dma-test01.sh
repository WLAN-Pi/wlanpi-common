#!/bin/bash
set -eu

SCRIPT="$(dirname "$0")/../wlanpi-config-at-startup.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
sed -n '/^configure_pcie_32bit_dma()/,/^}/p' "$SCRIPT" > "$TMP/function.sh"

# Build a fake /sys/bus/pci/devices from "slot=vendor:device/class" entries.
fake_pci() {
    rm -rf "$TMP/pci"; mkdir -p "$TMP/pci"
    local entry slot ids
    for entry in "$@"; do
        slot=${entry%%=*}; ids=${entry#*=}
        mkdir -p "$TMP/pci/$slot"
        echo "0x${ids%%:*}" > "$TMP/pci/$slot/vendor"
        ids=${ids#*:}
        echo "0x${ids%%/*}" > "$TMP/pci/$slot/device"
        # No "/class" part: leave the class file out (half-enumerated device)
        [ "$ids" = "${ids#*/}" ] || echo "${ids#*/}" > "$TMP/pci/$slot/class"
    done
}

run_case() {
    expected_reboot=$1
    expected_line=$2
    config=$3
    shift 3
    fake_pci "$@"
    printf '%s\n' "$config" > "$TMP/config.txt"
    CONFIG_FILE="$TMP/config.txt"
    REQUIRES_REBOOT=0
    PCI_DEVICES_DIR="$TMP/pci"
    export CONFIG_FILE REQUIRES_REBOOT PCI_DEVICES_DIR
    debugger() { :; }
    log_reason() { :; }
    # shellcheck source=/dev/null
    source "$TMP/function.sh"
    configure_pcie_32bit_dma
    [ "$REQUIRES_REBOOT" -eq "$expected_reboot" ]
    grep -q "^$expected_line$" "$CONFIG_FILE"
}

base_config=$'[cm4]\notg_mode=0\n[all]'
enabled_config=$'[cm4]\ndtoverlay=pcie-32bit-dma\n[all]'
root=0000:00:00.0=14e4:2711/0x060400

run_case 1 'dtoverlay=pcie-32bit-dma' "$base_config" "$root" 0000:01:00.0=14c3:0608/0x028000
run_case 0 'dtoverlay=pcie-32bit-dma' "$enabled_config" "$root" 0000:01:00.0=14c3:0608/0x028000
run_case 1 '#dtoverlay=pcie-32bit-dma' "$enabled_config" "$root" 0000:01:00.0=8086:272b/0x028000
run_case 0 'otg_mode=0' "$base_config" "$root" 0000:01:00.0=8086:272b/0x028000
# M4 with the WCN785x fitted (ath12k)
run_case 1 'dtoverlay=pcie-32bit-dma' "$base_config" "$root" 0000:01:00.0=17cb:1107/0x028000
# Empty slot or a card whose link failed: leave the overlay alone, no reboot
run_case 0 'dtoverlay=pcie-32bit-dma' "$enabled_config" "$root"
run_case 0 'otg_mode=0' "$base_config" "$root"
# Pro: switch and USB controller on the bus; only Wi-Fi functions count
run_case 1 'dtoverlay=pcie-32bit-dma' "$base_config" "$root" \
    0000:01:00.0=12d8:2404/0x060400 0000:03:00.0=1106:3483/0x0c0330 \
    0000:04:00.0=14c3:0608/0x028000 0000:05:00.0=14c3:0608/0x028000
run_case 1 '#dtoverlay=pcie-32bit-dma' "$enabled_config" "$root" \
    0000:01:00.0=12d8:2404/0x060400 0000:03:00.0=1106:3483/0x0c0330 \
    0000:04:00.0=8086:272b/0x028000 0000:05:00.0=8086:272b/0x028000
# Commented overlay is uncommented, not duplicated
run_case 1 'dtoverlay=pcie-32bit-dma' $'[cm4]\n#dtoverlay=pcie-32bit-dma\n[all]' "$root" \
    0000:01:00.0=14c3:0608/0x028000
[ "$(grep -c 'dtoverlay=pcie-32bit-dma' "$CONFIG_FILE")" -eq 1 ]
# One matching card among others keeps the overlay
run_case 0 'dtoverlay=pcie-32bit-dma' "$enabled_config" "$root" \
    0000:04:00.0=8086:272b/0x028000 0000:05:00.0=14c3:0608/0x028000
# A device without a class file is ignored, alone or next to a real card
run_case 0 'dtoverlay=pcie-32bit-dma' "$enabled_config" "$root" 0000:01:00.0=14c3:0608
[ "$(cat "$CONFIG_FILE")" = "$enabled_config" ]
run_case 1 'dtoverlay=pcie-32bit-dma' "$base_config" "$root" \
    0000:01:00.0=8086:272b 0000:02:00.0=17cb:1107/0x028000
# IDs match whatever the class: only 14c3:0608 and 17cb:1107 were checked on
# hardware (both 0x028000), so a listed card with another network class counts
run_case 1 'dtoverlay=pcie-32bit-dma' "$base_config" "$root" 0000:01:00.0=14c3:0616/0x020000
# and so does an unlisted network card of that class
run_case 1 '#dtoverlay=pcie-32bit-dma' "$enabled_config" "$root" 0000:01:00.0=10ec:8125/0x020000
echo "pcie-32bit-dma tests passed"
