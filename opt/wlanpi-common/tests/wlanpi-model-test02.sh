#!/bin/bash
###########################################################
# Description:
#
#  Test suite for wlanpi-model.sh Raspberry Pi 3/4/5 detection
#  (R4 must stay R4, the Pi 5 must report R5, and any other non-CM4 board
#  must report Unknown platform)
#
###########################################################

# MODULE/VERSION/COMMENTS are documentation.
# shellcheck disable=SC2034
MODULE=wlanpi-model.sh
VERSION=1.0.0
COMMENTS="wlanpi-model.sh test suite to validate R4 and R5 detection"
SCRIPT_NAME="$(dirname "$0")/../$MODULE"

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

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

# cpuinfo tail as reported by each board
fake_cpuinfo(){
    printf 'Revision\t: %s\nSerial\t\t: 0000000000000000\nModel\t\t: %s\n' "$1" "$2" > "$TMPROOT/cpuinfo"
}

# Model and Main board lines are printed before the adapter probes
model_line(){
    CPUINFO="$TMPROOT/cpuinfo" "$SCRIPT_NAME" 2>/dev/null | grep "^$1:" | cut -d ":" -f2 | xargs
}

brief(){
    CPUINFO="$TMPROOT/cpuinfo" "$SCRIPT_NAME" -b
}

# --- Raspberry Pi 4 stays R4 ---
fake_cpuinfo c03114 "Raspberry Pi 4 Model B Rev 1.4"
assert_eq "R4" "$(brief)" "Pi 4 brief reports R4"
assert_eq "WLAN Pi R4" "$(model_line Model)" "Pi 4 reports WLAN Pi R4"
assert_eq "Raspberry Pi 4 Model B Rev 1.4" "$(model_line "Main board")" "Pi 4 reports its board"

# --- Raspberry Pi 5 reports R5 ---
fake_cpuinfo c04171 "Raspberry Pi 5 Model B Rev 1.1"
assert_eq "R5" "$(brief)" "Pi 5 brief reports R5"
assert_eq "WLAN Pi R5" "$(model_line Model)" "Pi 5 reports WLAN Pi R5"
assert_eq "Raspberry Pi 5 Model B Rev 1.1" "$(model_line "Main board")" "Pi 5 reports its board"

# --- other Pi 5 family boards are not claimed as R5, they are unknown ---
fake_cpuinfo d04190 "Raspberry Pi 500 Rev 1.0"
assert_eq "Unknown platform" "$(brief)" "Pi 500 brief reports Unknown platform"
assert_eq "" "$(model_line Model)" "Pi 500 reports no Model line"

# --- Pi 3 still pretends to be R4, exactly once, and is not unknown ---
fake_cpuinfo a02082 "Raspberry Pi 3 Model B Rev 1.2"
assert_eq "R4" "$(brief)" "Pi 3 brief reports only R4"

echo
echo "Tests passed: $tests_passed, failed: $tests_failed"
[ "$tests_failed" -eq 0 ]
