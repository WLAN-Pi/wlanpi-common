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
    CONFIG_UNIT="$SOURCE_ROOT/debian/wlanpi-config-at-startup.service"
    RENAME_UNIT="$SOURCE_ROOT/debian/wlanpi-rename-at-startup.service"
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
first_reboot_line=$(grep -n 'systemctl reboot$' "$CONFIG_SCRIPT" | cut -d: -f1 | sort -n | sed -n '1p')

assert_ok "model cache uses a temporary file in /etc" grep -q 'mktemp /etc/.wlanpi-model.XXXXXX' "$CONFIG_SCRIPT"
assert_ok "model cache is readable by unprivileged consumers" grep -q 'chmod 0644 "$MODEL_CACHE_TMP"' "$CONFIG_SCRIPT"
assert_ok "model cache is published atomically" test -n "$cache_line"
assert_ok "model cache precedes reboot" test "$cache_line" -lt "$first_reboot_line"
assert_ok "config-at-startup reboots only from the final block" test "$(grep -c 'reboot$' "$CONFIG_SCRIPT")" -eq 2
assert_ok "reboot waits for multi-user.target" grep -q '^[[:space:]]*systemd-run --no-block --property=After=multi-user.target systemctl reboot$' "$CONFIG_SCRIPT"
assert_ok "reboot has a fallback if startup hangs" grep -q '^[[:space:]]*systemd-run --no-block --on-active=10min systemctl reboot$' "$CONFIG_SCRIPT"
assert_ok "config-at-startup does not restart FPMS" test "$(grep -c 'restart wlanpi-fpms.service' "$CONFIG_SCRIPT")" -eq 0
assert_ok "config-at-startup runs before FPMS" grep -q '^Before=wlanpi-fpms.service$' "$CONFIG_UNIT"
assert_ok "rename-at-startup runs before FPMS" grep -q '^Before=wlanpi-fpms.service$' "$RENAME_UNIT"
assert_ok "Avahi runs after config-at-startup" grep -q '^After=wlanpi-config-at-startup.service$' "$AVAHI_OVERRIDE"
if [ -n "$DEBIAN_RULES" ]; then
    assert_ok "config-at-startup does not run during package upgrades" grep -q 'dh_installsystemd --no-start wlanpi-config-at-startup.service wlanpi-rename-at-startup.service' "$DEBIAN_RULES"
    assert_ok "rename-at-startup does not run during package upgrades" grep -q 'dh_installsystemd --no-start wlanpi-config-at-startup.service wlanpi-rename-at-startup.service' "$DEBIAN_RULES"
    assert_ok "check-for-updates runs during package install" grep -qE '^[[:space:]]*dh_installsystemd[[:space:]]+wlanpi-check-for-updates\.service[[:space:]]+wlanpi-networkinfo\.service' "$DEBIAN_RULES"
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/etc"
sed -n '/^SPECS=\$(wlanpi-model)$/,/^trap - EXIT$/p' "$CONFIG_SCRIPT" | sed "s#/etc/#$TMP/etc/#g" > "$TMP/cache-block.sh"
seed_stale_cache_from_another_board(){
    printf 'WLAN Pi Go\n' > "$TMP/etc/wlanpi-model"
}
run_cache_block(){
    printf '#!/bin/sh\nprintf "%%s\\n" "%s"\n' "$1" > "$TMP/bin/wlanpi-model"
    chmod +x "$TMP/bin/wlanpi-model"
    seed_stale_cache_from_another_board
    PATH="$TMP/bin:$PATH" bash -e "$TMP/cache-block.sh" 2>/dev/null
}
assert_ok "model cache block found" grep -q 'rm -f' "$TMP/cache-block.sh"
run_cache_block "Unknown platform"
assert_ok "no model exits nonzero" test "$?" -ne 0
assert_ok "no model removes the stale model cache" test ! -e "$TMP/etc/wlanpi-model"
run_cache_block "Model:                WLAN Pi M4"
assert_ok "a detected model replaces the stale model cache" grep -qx "WLAN Pi M4" "$TMP/etc/wlanpi-model"

echo
echo "Tests passed: $tests_passed, failed: $tests_failed"
[ "$tests_failed" -eq 0 ]
