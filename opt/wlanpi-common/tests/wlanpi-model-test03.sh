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
mkdir -p "$TMPROOT/dt/spi@7e204000/max3421@0" "$TMPROOT/dt/spi@7e204000/spidev@1" "$TMPROOT/bound"
printf 'maxim,max3421\0' > "$TMPROOT/dt/spi@7e204000/max3421@0/compatible"
printf 'spidev\0' > "$TMPROOT/dt/spi@7e204000/spidev@1/compatible"
touch "$TMPROOT/bound/spi0.0" "$TMPROOT/readable-i2c"
mkfifo "$TMPROOT/blocking-serial-fifo"
printf '14,1,0\n' > "$TMPROOT/go-serial"
printf 'Go\n' > "$TMPROOT/go-model"
printf 'WLAN Pi M4+\n' > "$TMPROOT/m4plus-cache"

WITH_OVERLAY="$TMPROOT/dt/spi@*/*/compatible"
NO_OVERLAY="$TMPROOT/dt/spi@*/spidev@*/compatible"
BOUND="$TMPROOT/bound/spi*"
SILENT="$TMPROOT/blocking-serial-fifo"
NONE="$TMPROOT/none"

# Stubs keep host I2C, USB, and PCIe devices out of the detected model.
mkdir "$TMPROOT/bin"
printf '#!/bin/sh\nexit 1\n' > "$TMPROOT/bin/lsusb"
cp "$TMPROOT/bin/lsusb" "$TMPROOT/bin/lspci"
printf '#!/bin/sh\n[ -e "%s" ] && echo "50: 50 -- -- --"\nexit 0\n' "$TMPROOT/eeprom" > "$TMPROOT/bin/i2cdetect"
printf '#!/bin/sh\necho "$*" >> "%s"\nexec %s "$@"\n' "$TMPROOT/timeout.log" "$(command -v timeout)" > "$TMPROOT/bin/timeout"
chmod +x "$TMPROOT/bin/"*

# detect BOUND_GLOB SERIAL DEVICE_INFO OVERLAY_GLOB [EEPROM] [CACHE] [I2C_DEV]
detect(){
    : > "$TMPROOT/timeout.log"
    rm -f "$TMPROOT/eeprom"
    [ "${5:-}" = eeprom ] && touch "$TMPROOT/eeprom"
    MODEL=$(PATH="$TMPROOT/bin:$PATH" CPUINFO="$TMPROOT/cpuinfo" UPTIME_FILE="$TMPROOT/uptime" \
        PRO_BATTERY_PRESENT="$NONE" MAX3421_BOUND_GLOB="$1" GO_SERIAL="$2" GO_DEVICE_INFO="$3" \
        MAX3421_COMPATIBLE_GLOB="$4" MODEL_CACHE="${6:-$NONE}" I2C_DEV="${7:-$TMPROOT/readable-i2c}" \
        "$SCRIPT_NAME" -b 2>"$TMPROOT/stderr")
}

serial_read(){
    grep -q -- "$SILENT" "$TMPROOT/timeout.log" && echo read || echo skipped
}

detect "$BOUND" "$SILENT" "$NONE" "$WITH_OVERLAY"
assert_eq "Go" "$MODEL" "bound max3421 driver reports Go"
assert_eq "skipped" "$(serial_read)" "bound max3421 driver skips the serial read"

detect "$NONE" "$TMPROOT/go-serial" "$NONE" "$NO_OVERLAY"
assert_eq "Go" "$MODEL" "Go serial answer reports Go without the overlay"

detect "$NONE" "$SILENT" "$TMPROOT/go-model" "$WITH_OVERLAY"
assert_eq "Unknown platform" "$MODEL" "Go storage on another board reports Unknown platform"
assert_eq "wlanpi-model: Go software without Go hardware" "$(cat "$TMPROOT/stderr")" \
    "Go storage on another board explains why on stderr"

detect "$NONE" "$SILENT" "$NONE" "$WITH_OVERLAY"
assert_eq "Unknown platform" "$MODEL" "Go overlay without Go hardware reports Unknown platform"

detect "$NONE" "$SILENT" "$TMPROOT/go-model" "$NO_OVERLAY"
assert_eq "Unknown platform" "$MODEL" "Go device-info without Go hardware reports Unknown platform"

detect "$NONE" "$SILENT" "$NONE" "$NO_OVERLAY"
assert_eq "M4" "$MODEL" "no Go signals report M4"
assert_eq "read" "$(serial_read)" "M4 reads the serial port"
assert_eq "" "$(cat "$TMPROOT/stderr")" "M4 prints nothing on stderr"

detect "$NONE" "$SILENT" "$NONE" "$NO_OVERLAY" eeprom
assert_eq "M4+" "$MODEL" "M4+ EEPROM reports M4+"
assert_eq "skipped" "$(serial_read)" "M4+ EEPROM skips the serial read"

detect "$NONE" "$SILENT" "$NONE" "$NO_OVERLAY" "" "$TMPROOT/m4plus-cache" "$NONE"
assert_eq "M4+" "$MODEL" "unreadable I2C with an M4+ cache reports M4+"

detect "$NONE" "$TMPROOT/go-serial" "$NONE" "$NO_OVERLAY" "" "$TMPROOT/m4plus-cache" "$NONE"
assert_eq "Go" "$MODEL" "Go hardware wins over a moved M4+ cache"

detect "$NONE" "$SILENT" "$TMPROOT/go-model" "$WITH_OVERLAY" "" "$TMPROOT/m4plus-cache" "$NONE"
assert_eq "Unknown platform" "$MODEL" "Go storage wins over an M4+ cache"

echo
echo "Tests passed: $tests_passed, failed: $tests_failed"
[ "$tests_failed" -eq 0 ]
