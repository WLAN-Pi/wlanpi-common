#!/bin/bash
###########################################################
# Description:
#
#  Test suite for wlanpi-model.sh usb_mode() M4+ USB mode reporting
#  (device tree dr_mode, with the USB device count as the fallback) and
#  Bluetooth adapter detection
#
###########################################################

# MODULE/VERSION/COMMENTS are documentation, and the USB_* paths are read by
# the extracted usb_mode() function, which shellcheck cannot see across files.
# shellcheck disable=SC2034
MODULE=wlanpi-model.sh
VERSION=1.0.0
COMMENTS="wlanpi-model.sh test suite to validate M4+ USB mode and Bluetooth reporting"
SCRIPT_NAME="$(dirname "$0")/../$MODULE"

# wlanpi-model.sh runs its detection at the top level, so extract just the
# helper and source that instead of the whole module.
TMPROOT="$(mktemp -d)"
EXTRACTED="$TMPROOT/usb_mode.sh"
trap 'rm -rf "$TMPROOT"' EXIT
sed -n '/^usb_mode()/,/^}/p' "$SCRIPT_NAME" > "$EXTRACTED"
# shellcheck source=/dev/null
. "$EXTRACTED"

# initialize tests passed/failed counters
tests_passed=0
tests_failed=0

assert_eq(){
    local expected=$1
    local actual=$2
    local name=$3
    if [ "$expected" == "$actual" ]; then
        echo "PASS: $name"
        ((tests_passed++))
    else
        echo "FAIL: $name (expected '$expected', got '$actual')"
        ((tests_failed++))
    fi
}

HOST="Host - Bluetooth and USB-A ports enabled"
OTG="OTG - Bluetooth and USB-A ports disabled"

# --- device tree dr_mode is authoritative ---
mkdir -p "$TMPROOT/dt"
printf 'host\0' > "$TMPROOT/dt/dr_mode"
USB_DR_MODE_GLOB="$TMPROOT/dt/dr_mode"
assert_eq "$HOST" "$(usb_mode)" "dr_mode=host reports host"

printf 'otg\0' > "$TMPROOT/dt/dr_mode"
assert_eq "$OTG" "$(usb_mode)" "dr_mode=otg reports otg"

printf 'peripheral\0' > "$TMPROOT/dt/dr_mode"
assert_eq "$OTG" "$(usb_mode)" "dr_mode=peripheral reports otg"

# --- absent device tree property falls back to the USB device count ---
USB_DR_MODE_GLOB="$TMPROOT/missing/dr_mode"

mkdir -p "$TMPROOT/usb/1-1" "$TMPROOT/usb/1-1:1.0" "$TMPROOT/usb/2-1"
USB_DEVICES_PATH="$TMPROOT/usb"
assert_eq "$HOST" "$(usb_mode)" "absent dr_mode with a hub reports host"

mkdir -p "$TMPROOT/usb-otg/1-1" "$TMPROOT/usb-otg/1-1:1.0"
USB_DEVICES_PATH="$TMPROOT/usb-otg"
assert_eq "$OTG" "$(usb_mode)" "absent dr_mode with one device reports otg"

# --- the M4+ host-mode case from the issue: dr_mode=host, hub enumerated ---
mkdir -p "$TMPROOT/dt-host"
printf 'host\0' > "$TMPROOT/dt-host/dr_mode"
USB_DR_MODE_GLOB="$TMPROOT/dt-host/dr_mode"
USB_DEVICES_PATH="$TMPROOT/usb"
assert_eq "$HOST" "$(usb_mode)" "issue #91 case reports host"

# --- Bluetooth: the whole script, with lsusb, lspci and hciconfig stubbed ---
# No USB Bluetooth in lsusb, so the result comes from hciconfig.
mkdir -p "$TMPROOT/bin"
printf '#!/bin/sh\n' > "$TMPROOT/bin/lsusb"
printf '#!/bin/sh\n' > "$TMPROOT/bin/lspci"
printf '#!/bin/sh\ncat "$HCICONFIG_OUT"\n' > "$TMPROOT/bin/hciconfig"
chmod +x "$TMPROOT/bin/"*
bluetooth_line() {
    HCICONFIG_OUT="$TMPROOT/hciconfig.out" PATH="$TMPROOT/bin:$PATH" \
        bash "$SCRIPT_NAME" | grep -E "^(No )?Bluetooth adapter"
}

printf 'hci0:\tType: Primary  Bus: UART\n\tBD Address: B8:27:EB:00:00:01  ACL MTU: 1021:8  SCO MTU: 64:1\n' > "$TMPROOT/hciconfig.out"
assert_eq "Bluetooth adapter:    Built-in" "$(bluetooth_line)" "hci0 reports built-in Bluetooth"

printf 'hci1:\tType: Primary  Bus: UART\n\tBD Address: B8:27:EB:00:00:01  ACL MTU: 1021:8  SCO MTU: 64:1\n' > "$TMPROOT/hciconfig.out"
assert_eq "Bluetooth adapter:    Built-in" "$(bluetooth_line)" "only hci1 reports built-in Bluetooth"

: > "$TMPROOT/hciconfig.out"
assert_eq "No Bluetooth adapter" "$(bluetooth_line)" "no adapter reports none"

echo
echo "Tests passed: $tests_passed, failed: $tests_failed"
[ "$tests_failed" -eq 0 ]
