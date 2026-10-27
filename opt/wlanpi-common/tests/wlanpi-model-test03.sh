#!/bin/bash
# wlanpi-model-test03.sh (no arguments): tests wlanpi-model.sh WLAN Pi Go detection on a CM4

MODULE=wlanpi-model.sh
SCRIPT_NAME="$(dirname "$0")/../$MODULE"

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
mkdir -p "$TMPROOT/dt/spi@7e204000/max3421@0" "$TMPROOT/dt/spi@7e204000/spidev@1"
printf 'maxim,max3421\0' > "$TMPROOT/dt/spi@7e204000/max3421@0/compatible"
printf 'spidev\0' > "$TMPROOT/dt/spi@7e204000/spidev@1/compatible"
# A FIFO with no writer blocks the serial read until its 2 s timeout.
mkfifo "$TMPROOT/silent-serial"
printf '14,1,0\n' > "$TMPROOT/go-serial"
printf 'Go\n' > "$TMPROOT/go-model"

ELAPSED_MS=0
brief(){
    local start
    start=$(date +%s%N)
    MODEL=$(CPUINFO="$TMPROOT/cpuinfo" MAX3421_COMPATIBLE_GLOB="$1" GO_SERIAL="$2" \
        GO_DEVICE_INFO="$3" "$SCRIPT_NAME" -b 2>/dev/null)
    ELAPSED_MS=$(( ($(date +%s%N) - start) / 1000000 ))
}

brief "$TMPROOT/dt/spi@*/spidev@*/compatible" "$TMPROOT/silent-serial" "$TMPROOT/none"
assert_eq "M4" "$MODEL" "no max3421 node reports M4"
assert_eq "skipped" "$([ "$ELAPSED_MS" -lt 1500 ] && echo skipped || echo "waited ${ELAPSED_MS}ms")" \
    "no max3421 node skips the serial read"

brief "$TMPROOT/dt/spi@*/*/compatible" "$TMPROOT/silent-serial" "$TMPROOT/go-model"
assert_eq "Go" "$MODEL" "max3421 and device-info model report Go"
assert_eq "skipped" "$([ "$ELAPSED_MS" -lt 1500 ] && echo skipped || echo "waited ${ELAPSED_MS}ms")" \
    "device-info model skips the serial read"

brief "$TMPROOT/dt/spi@*/*/compatible" "$TMPROOT/go-serial" "$TMPROOT/none"
assert_eq "Go" "$MODEL" "max3421 and Go serial line report Go"

brief "$TMPROOT/dt/spi@*/*/compatible" "$TMPROOT/silent-serial" "$TMPROOT/none"
assert_eq "M4" "$MODEL" "max3421 without a Go answer falls back to M4"

brief "$TMPROOT/dt/spi@*/spidev@*/compatible" "$TMPROOT/go-serial" "$TMPROOT/go-model"
assert_eq "M4" "$MODEL" "Go answers are ignored without a max3421 node"

echo
echo "Tests passed: $tests_passed, failed: $tests_failed"
[ "$tests_failed" -eq 0 ]
