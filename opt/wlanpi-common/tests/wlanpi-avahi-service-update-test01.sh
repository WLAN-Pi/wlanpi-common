#!/bin/bash
###########################################################
# Description:
#
#  Test suite for wlanpi-avahi-service-update.sh, which generates the
#  WLAN Pi mDNS service file from the model and /etc/wlanpi-release
#
###########################################################

# MODULE/VERSION/COMMENTS are documentation.
# shellcheck disable=SC2034
MODULE=wlanpi-avahi-service-update.sh
VERSION=1.0.0
COMMENTS="wlanpi-avahi-service-update.sh test suite to validate the service file"
SCRIPT_NAME="$(dirname "$0")/../$MODULE"

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

export WLANPI_MODEL_CMD="$TMPROOT/wlanpi-model"
export WLANPI_MODEL_CACHE="$TMPROOT/model"
export WLANPI_RELEASE_FILE="$TMPROOT/release"
export SERVICE_FILE="$TMPROOT/services/wlanpi_announce.service"
mkdir -p "$TMPROOT/services"

tests_passed=0
tests_failed=0

assert_eq(){
    if [ "$1" == "$2" ]; then
        echo "PASS: $3"
        ((tests_passed++))
    else
        echo "FAIL: $3 (expected '$1', got '$2')"
        ((tests_failed++))
    fi
}

# run <release file contents> [model cache]: runs the script and prints its
# exit status plus, per service, "type:port:model:ver".
run(){
    printf '%b' "$1" > "$WLANPI_RELEASE_FILE"
    printf '%s' "${2-WLAN Pi M4}" > "$WLANPI_MODEL_CACHE"
    bash "$SCRIPT_NAME" >/dev/null 2>&1
    echo "rc=$? $(awk -F'[<>]' '
        /<type>/ {t=$3} /<port>/ {p=$3}
        /model=/ {sub("model=", "", $3); m=$3}
        /ver=/   {sub("ver=", "", $3); v=$3}
        /<\/service>/ {printf "%s:%s:%s:%s ", t, p, m, v; m=v=""}' "$SERVICE_FILE")"
}

SERVICES="_https._tcp:31415:WLAN Pi M4:26.10-rc.1 _http._tcp:80:WLAN Pi M4:26.10-rc.1 _ssh._tcp:22:: "
PLACEHOLDER="_https._tcp:31415:WLAN Pi:0 _http._tcp:80:WLAN Pi:0 _ssh._tcp:22:: "

assert_eq "rc=0 $SERVICES" "$(run 'VERSION=26.10-rc.1\n')" "version-only release file"
assert_eq "rc=0 $SERVICES" "$(run 'VERSION=26.10-rc.1\nCODENAME=DeadEye\n')" "codename line is not advertised"
assert_eq "rc=1 $PLACEHOLDER" "$(run 'CODENAME=DeadEye\n' '')" "missing model and version still publish placeholders"
assert_eq "644" "$(stat -c %a "$SERVICE_FILE")" "service file is world-readable"
grep -q 'id=wlanpi' "$SERVICE_FILE"
assert_eq "0" "$?" "ssh service keeps id=wlanpi"

run 'VERSION=26.10-rc.1\n' >/dev/null
INODE=$(stat -c %i "$SERVICE_FILE")
run 'VERSION=26.10-rc.1\n' >/dev/null
assert_eq "$INODE" "$(stat -c %i "$SERVICE_FILE")" "unchanged content is not rewritten"
assert_eq "" "$(find "$TMPROOT/services" -name '.wlanpi_announce.*')" "no temp files left behind"

echo
echo "Tests passed: $tests_passed, failed: $tests_failed"
[ "$tests_failed" -eq 0 ]
