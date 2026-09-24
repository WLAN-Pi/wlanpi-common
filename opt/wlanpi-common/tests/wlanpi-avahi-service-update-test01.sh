#!/bin/bash
###########################################################
# Description:
#
#  Test suite for wlanpi-avahi-service-update.sh TXT records
#  (only the VERSION line of /etc/wlanpi-release is advertised)
#
###########################################################

# MODULE/VERSION/COMMENTS are documentation.
# shellcheck disable=SC2034
MODULE=wlanpi-avahi-service-update.sh
VERSION=1.0.0
COMMENTS="wlanpi-avahi-service-update.sh test suite to validate TXT records"
SCRIPT_NAME="$(dirname "$0")/../$MODULE"

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

export WLANPI_MODEL_CMD="$TMPROOT/wlanpi-model"
export WLANPI_MODEL_CACHE="$TMPROOT/model"
export WLANPI_RELEASE_FILE="$TMPROOT/release"
export SERVICE_FILE="$TMPROOT/announce.service"
touch "$WLANPI_MODEL_CMD"
echo "WLAN Pi M4" > "$WLANPI_MODEL_CACHE"

tests_passed=0
tests_failed=0

# run <release file contents>: resets the service file, runs the script,
# and prints its exit status followed by the ver= record.
run(){
    printf '%b' "$1" > "$WLANPI_RELEASE_FILE"
    printf '<txt-record>model=x</txt-record>\n<txt-record>ver=x</txt-record>\n' > "$SERVICE_FILE"
    bash "$SCRIPT_NAME" >/dev/null 2>&1
    echo "rc=$? $(grep -o 'ver=[^<]*' "$SERVICE_FILE")"
}

assert_eq(){
    if [ "$1" == "$2" ]; then
        echo "PASS: $3"
        ((tests_passed++))
    else
        echo "FAIL: $3 (expected '$1', got '$2')"
        ((tests_failed++))
    fi
}

assert_eq "rc=0 ver=26.10-rc.1" "$(run 'VERSION=26.10-rc.1\n')" "version-only release file"
assert_eq "rc=0 ver=26.10-rc.1" "$(run 'VERSION=26.10-rc.1\nCODENAME=DeadEye\n')" "codename line is not advertised"
assert_eq "rc=1 ver=x" "$(run 'CODENAME=DeadEye\n')" "missing VERSION fails and leaves record untouched"

echo
echo "Tests passed: $tests_passed, failed: $tests_failed"
[ "$tests_failed" -eq 0 ]
