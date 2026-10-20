#!/bin/bash
# wlanpi-model-test02.sh (no arguments): tests wlanpi-model.sh Raspberry Pi 3/4/5 detection

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

fake_cpuinfo(){
    printf 'Revision\t: %s\nSerial\t\t: 0000000000000000\nModel\t\t: %s\n' "$1" "$2" > "$TMPROOT/cpuinfo"
}

model_line(){
    CPUINFO="$TMPROOT/cpuinfo" "$SCRIPT_NAME" 2>/dev/null | grep "^$1:" | cut -d ":" -f2 | xargs
}

brief(){
    CPUINFO="$TMPROOT/cpuinfo" "$SCRIPT_NAME" -b
}

fake_cpuinfo c03114 "Raspberry Pi 4 Model B Rev 1.4"
assert_eq "R4" "$(brief)" "Pi 4 brief reports R4"
assert_eq "WLAN Pi R4" "$(model_line Model)" "Pi 4 reports WLAN Pi R4"
assert_eq "Raspberry Pi 4 Model B Rev 1.4" "$(model_line "Main board")" "Pi 4 reports its board"

fake_cpuinfo c04171 "Raspberry Pi 5 Model B Rev 1.1"
assert_eq "R5" "$(brief)" "Pi 5 brief reports R5"
assert_eq "WLAN Pi R5" "$(model_line Model)" "Pi 5 reports WLAN Pi R5"
assert_eq "Raspberry Pi 5 Model B Rev 1.1" "$(model_line "Main board")" "Pi 5 reports its board"

fake_cpuinfo d04190 "Raspberry Pi 500 Rev 1.0"
assert_eq "Unknown platform" "$(brief)" "Pi 500 brief reports Unknown platform"
assert_eq "" "$(model_line Model)" "Pi 500 reports no Model line"

fake_cpuinfo a02082 "Raspberry Pi 3 Model B Rev 1.2"
assert_eq "R4" "$(brief)" "Pi 3 brief reports only R4"

echo
echo "Tests passed: $tests_passed, failed: $tests_failed"
[ "$tests_failed" -eq 0 ]
