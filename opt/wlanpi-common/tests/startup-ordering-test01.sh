#!/bin/bash
###########################################################
# Description:
#
#  Regression checks for model-cache publication and the startup ordering
#  between config-at-startup, FPMS, rename-at-startup, and Avahi.
#
###########################################################

DIR="$(dirname "$0")/.."
CONFIG_SCRIPT="$DIR/wlanpi-config-at-startup.sh"
SOURCE_ROOT="$DIR/../.."

if [ -d "$SOURCE_ROOT/debian" ]; then
    CONFIG_UNIT="$SOURCE_ROOT/debian/wlanpi-common.wlanpi-config-at-startup.service"
    RENAME_UNIT="$SOURCE_ROOT/debian/wlanpi-common.wlanpi-rename-at-startup.service"
    AVAHI_OVERRIDE="$SOURCE_ROOT/etc/systemd/system/avahi-daemon.service.d/override.conf"
    DEBIAN_RULES="$SOURCE_ROOT/debian/rules"
else
    CONFIG_UNIT="/usr/lib/systemd/system/wlanpi-config-at-startup.service"
    RENAME_UNIT="/usr/lib/systemd/system/wlanpi-rename-at-startup.service"
    AVAHI_OVERRIDE="/etc/systemd/system/avahi-daemon.service.d/override.conf"
    DEBIAN_RULES=""
fi

tests_passed=0
tests_failed=0

assert_ok(){
    local name=$1
    shift
    if "$@"; then
        echo "PASS: $name"
        ((tests_passed++))
    else
        echo "FAIL: $name"
        ((tests_failed++))
    fi
}

cache_line=$(grep -n 'mv -- "$MODEL_CACHE_TMP" /etc/wlanpi-model' "$CONFIG_SCRIPT" | cut -d: -f1)
first_reboot_line=$(grep -n '^[[:space:]]*reboot$' "$CONFIG_SCRIPT" | cut -d: -f1 | sort -n | sed -n '1p')

assert_ok "model cache uses a temporary file in /etc" grep -q 'mktemp /etc/.wlanpi-model.XXXXXX' "$CONFIG_SCRIPT"
assert_ok "model cache is readable by unprivileged consumers" grep -q 'chmod 0644 "$MODEL_CACHE_TMP"' "$CONFIG_SCRIPT"
assert_ok "model cache is published atomically" test -n "$cache_line"
assert_ok "model cache precedes reboot" test "$cache_line" -lt "$first_reboot_line"
assert_ok "config-at-startup does not restart FPMS" test "$(grep -c 'restart wlanpi-fpms.service' "$CONFIG_SCRIPT")" -eq 0
assert_ok "config-at-startup runs before FPMS" grep -q '^Before=wlanpi-fpms.service$' "$CONFIG_UNIT"
assert_ok "rename-at-startup runs before FPMS" grep -q '^Before=wlanpi-fpms.service$' "$RENAME_UNIT"
assert_ok "Avahi runs after config-at-startup" grep -q '^After=wlanpi-config-at-startup.service$' "$AVAHI_OVERRIDE"
if [ -n "$DEBIAN_RULES" ]; then
    assert_ok "config-at-startup does not run during package upgrades" grep -q 'dh_installinit --no-start --name=wlanpi-config-at-startup' "$DEBIAN_RULES"
    assert_ok "rename-at-startup does not run during package upgrades" grep -q 'dh_installinit --no-start --name=wlanpi-rename-at-startup' "$DEBIAN_RULES"
    assert_ok "debhelper does not restart config-at-startup" test "$(grep -c 'dh_systemd_start.*wlanpi-config-at-startup' "$DEBIAN_RULES")" -eq 0
    assert_ok "debhelper does not restart rename-at-startup" test "$(grep -c 'dh_systemd_start.*wlanpi-rename-at-startup' "$DEBIAN_RULES")" -eq 0
fi

echo
echo "Tests passed: $tests_passed, failed: $tests_failed"
[ "$tests_failed" -eq 0 ]
