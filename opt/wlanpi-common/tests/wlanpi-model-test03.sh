#!/bin/bash
# wlanpi-model-test03.sh (no arguments): tests wlanpi-model.sh CM4 detection of the Go, M4+, and M4

SCRIPT_NAME="$(dirname "$0")/../wlanpi-model.sh"

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

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

printf 'Model\t\t: Raspberry Pi Compute Module 4 Rev 1.1\n' > "$TMPROOT/cpuinfo"
printf '600.00 1200.00\n' > "$TMPROOT/uptime"
mkdir -p "$TMPROOT/dt/spi@7e204000/max3421@0" "$TMPROOT/dt/spi@7e204000/spidev@1"
printf 'maxim,max3421\0' > "$TMPROOT/dt/spi@7e204000/max3421@0/compatible"
printf 'spidev\0' > "$TMPROOT/dt/spi@7e204000/spidev@1/compatible"
touch "$TMPROOT/readable-i2c"
mkfifo "$TMPROOT/blocking-serial-fifo"
printf '14,1,0\n' > "$TMPROOT/go-serial"
printf 'Go\n' > "$TMPROOT/go-model"
printf 'WLAN Pi M4+\n' > "$TMPROOT/m4plus-cache"

WITH_OVERLAY="$TMPROOT/dt/spi@*/*/compatible"
NO_OVERLAY="$TMPROOT/dt/spi@*/spidev@*/compatible"
SILENT="$TMPROOT/blocking-serial-fifo"
NONE="$TMPROOT/none"

# Stubs keep host I2C, USB, and PCIe devices out of the detected model.
mkdir "$TMPROOT/bin"
printf '#!/bin/sh\nexit 1\n' > "$TMPROOT/bin/lsusb"
cp "$TMPROOT/bin/lsusb" "$TMPROOT/bin/lspci"
printf '#!/bin/sh\n[ -e "%s" ] && echo "50: 50 -- -- --"\nexit 0\n' "$TMPROOT/eeprom" > "$TMPROOT/bin/i2cdetect"
printf '#!/bin/sh\necho "$*" >> "%s"\nexec %s "$@"\n' "$TMPROOT/timeout.log" "$(command -v timeout)" > "$TMPROOT/bin/timeout"
chmod +x "$TMPROOT/bin/"*

detect(){
    : > "$TMPROOT/timeout.log"
    rm -f "$TMPROOT/eeprom"
    [ "${EEPROM:-0}" = 1 ] && touch "$TMPROOT/eeprom"
    MODEL=$(PATH="$TMPROOT/bin:$PATH" CPUINFO="$TMPROOT/cpuinfo" UPTIME_FILE="$TMPROOT/uptime" \
        PRO_BATTERY_PRESENT="$NONE" GO_SERIAL="${SERIAL:?}" GO_DEVICE_INFO="${INFO:?}" \
        MAX3421_COMPATIBLE_GLOB="${OVERLAY:?}" MODEL_CACHE="${CACHE:-$NONE}" \
        I2C_DEV="${I2C:-$TMPROOT/readable-i2c}" "$SCRIPT_NAME" -b 2>"$TMPROOT/stderr")
}

serial_read(){
    grep -q -- '-E ^14,' "$TMPROOT/timeout.log" && echo read || echo skipped
}

SERIAL="$TMPROOT/go-serial" INFO="$TMPROOT/go-model" OVERLAY="$WITH_OVERLAY" detect
assert_eq "Go" "$MODEL" "Go storage on a Go reports Go"

SERIAL="$TMPROOT/go-serial" INFO="$NONE" OVERLAY="$NO_OVERLAY" detect
assert_eq "Go" "$MODEL" "Go serial answer reports Go without the overlay"

SERIAL="$SILENT" INFO="$TMPROOT/go-model" OVERLAY="$WITH_OVERLAY" detect
assert_eq "Unknown platform" "$MODEL" "Go storage on another board reports Unknown platform"
assert_eq "wlanpi-model: Go software without Go hardware" "$(cat "$TMPROOT/stderr")" \
    "Go storage on another board explains why on stderr"

SERIAL="$SILENT" INFO="$NONE" OVERLAY="$WITH_OVERLAY" detect
assert_eq "Unknown platform" "$MODEL" "Go overlay without Go hardware reports Unknown platform"

SERIAL="$SILENT" INFO="$TMPROOT/go-model" OVERLAY="$NO_OVERLAY" detect
assert_eq "Unknown platform" "$MODEL" "Go device-info without Go hardware reports Unknown platform"

SERIAL="$SILENT" INFO="$NONE" OVERLAY="$NO_OVERLAY" detect
assert_eq "M4" "$MODEL" "no Go signals report M4"
assert_eq "read" "$(serial_read)" "M4 reads the serial port"
assert_eq "" "$(cat "$TMPROOT/stderr")" "M4 prints nothing on stderr"

SERIAL="$SILENT" INFO="$NONE" OVERLAY="$NO_OVERLAY" EEPROM=1 detect
assert_eq "M4+" "$MODEL" "M4+ EEPROM reports M4+"
assert_eq "skipped" "$(serial_read)" "M4+ EEPROM skips the serial read"

SERIAL="$SILENT" INFO="$TMPROOT/go-model" OVERLAY="$WITH_OVERLAY" EEPROM=1 detect
assert_eq "M4+" "$MODEL" "M4+ EEPROM wins over moved Go storage"
assert_eq "" "$(cat "$TMPROOT/stderr")" "M4+ with moved Go storage prints nothing on stderr"
assert_eq "skipped" "$(serial_read)" "M4+ with moved Go storage skips the serial read"

SERIAL="$SILENT" INFO="$NONE" OVERLAY="$NO_OVERLAY" CACHE="$TMPROOT/m4plus-cache" I2C="$NONE" detect
assert_eq "M4+" "$MODEL" "unreadable I2C with an M4+ cache reports M4+"

SERIAL="$TMPROOT/go-serial" INFO="$NONE" OVERLAY="$NO_OVERLAY" CACHE="$TMPROOT/m4plus-cache" I2C="$NONE" detect
assert_eq "Go" "$MODEL" "Go hardware wins over a moved M4+ cache"

SERIAL="$SILENT" INFO="$TMPROOT/go-model" OVERLAY="$WITH_OVERLAY" CACHE="$TMPROOT/m4plus-cache" I2C="$NONE" detect
assert_eq "Unknown platform" "$MODEL" "Go storage wins over an M4+ cache"

FULL=$(PATH="$TMPROOT/bin:$PATH" CPUINFO="$TMPROOT/cpuinfo" UPTIME_FILE="$TMPROOT/uptime" \
    PRO_BATTERY_PRESENT="$NONE" GO_SERIAL="$SILENT" GO_DEVICE_INFO="$TMPROOT/go-model" \
    MAX3421_COMPATIBLE_GLOB="$WITH_OVERLAY" MODEL_CACHE="$NONE" I2C_DEV="$TMPROOT/readable-i2c" \
    "$SCRIPT_NAME" 2>/dev/null)
assert_eq "" "$(echo "$FULL" | grep -E '^(Model|Main board):')" "full output for moved Go storage has no Model line"

echo
echo "Tests passed: $tests_passed, failed: $tests_failed"
[ "$tests_failed" -eq 0 ]
