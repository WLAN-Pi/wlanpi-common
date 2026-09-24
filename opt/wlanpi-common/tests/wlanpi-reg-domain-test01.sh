#!/bin/bash
###########################################################
# Description:
#
#  Test suite for wlanpi-reg-domain.sh set_domain(): applies the domain,
#  never prompts, and restarts a running profiler without blocking
#
###########################################################

# MODULE/VERSION/COMMENTS are documentation; the path variables are read by
# the extracted functions, which shellcheck cannot see across files.
# shellcheck disable=SC2034
MODULE=wlanpi-reg-domain.sh
VERSION=1.0.0
COMMENTS="wlanpi-reg-domain.sh test suite to validate set_domain"
SCRIPT_NAME="$(dirname "$0")/../$MODULE"

# The script dispatches at the top level and needs root, so extract only the
# functions set_domain uses and run them against temp files and PATH shims.
TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT
EXTRACTED="$TMPROOT/functions.sh"
sed -n -e '/^debugger()/,/^}/p' -e '/^err_report()/,/^}/p' \
    -e '/^wait_for_domain ()/,/^}/p' -e '/^update_hostapd_country ()/,/^}/p' \
    -e '/^set_domain ()/,/^}/p' "$SCRIPT_NAME" > "$EXTRACTED"

SHIMS="$TMPROOT/bin"
mkdir -p "$SHIMS"
# iw: "reg set XX" records XX, "reg get" reports it
cat > "$SHIMS/iw" <<EOF
#!/bin/bash
if [ "\$2" = set ]; then echo "\$3" > "$TMPROOT/domain"; fi
if [ "\$2" = get ]; then echo "global"; echo "country \$(cat "$TMPROOT/domain"): DFS-TEST"; fi
EOF
# systemctl: log every call; is-active/try-restart exit per env
cat > "$SHIMS/systemctl" <<EOF
#!/bin/bash
echo "\$*" >> "$TMPROOT/systemctl.log"
case "\$1" in
    is-active) exit "\${PROFILER_ACTIVE_RC:-3}" ;;
    try-restart) exit "\${TRY_RESTART_RC:-0}" ;;
esac
EOF
printf '#!/bin/sh\n' > "$SHIMS/logger"
printf '#!/bin/sh\necho reboot >> "%s/reboot.log"\n' "$TMPROOT" > "$SHIMS/reboot"
chmod +x "$SHIMS"/*

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

# run_set <domain> [--no-prompt]: runs set_domain under set -e with stdin
# closed, like FPMS and wlanpi-core, and prints its exit status.
run_set(){
    rm -f "$TMPROOT/systemctl.log" "$TMPROOT/out"
    echo US > "$TMPROOT/domain"
    (
        set -e
        PATH="$SHIMS:$PATH"
        REGDOMAIN_MODPROBE_FILE="$TMPROOT/modprobe.conf"
        HOTSPOT_FILE="$TMPROOT/missing" WCONSOLE_FILE="$TMPROOT/missing"
        SERVER_FILE="$TMPROOT/missing"
        PROFILER_UNIT="wlanpi-profiler"
        DEBUG=0
        DOMAIN=$1
        # shellcheck source=/dev/null
        . "$EXTRACTED"
        set_domain
    ) </dev/null >"$TMPROOT/out" 2>&1
    echo "rc=$?"
}

assert_eq "rc=0" "$(run_set GB)" "set without --no-prompt succeeds with stdin closed"
assert_eq "GB" "$(cat "$TMPROOT/domain")" "domain applied"
assert_eq "options cfg80211 ieee80211_regdom=GB" "$(cat "$TMPROOT/modprobe.conf")" "domain persisted"
assert_eq "" "$(cat "$TMPROOT/reboot.log" 2>/dev/null)" "never reboots"
assert_eq "is-active --quiet wlanpi-profiler" "$(cat "$TMPROOT/systemctl.log")" "stopped profiler is not restarted"

export PROFILER_ACTIVE_RC=0
assert_eq "rc=0" "$(run_set DE)" "set with a running profiler succeeds"
assert_eq "try-restart --no-block wlanpi-profiler" "$(tail -n1 "$TMPROOT/systemctl.log")" "running profiler restarted without blocking"
grep -q "Restarting the profiler" "$TMPROOT/out"
assert_eq "0" "$?" "restart is reported"

export TRY_RESTART_RC=1
assert_eq "rc=0" "$(run_set FR)" "failed profiler restart does not fail the set"
assert_eq "FR" "$(cat "$TMPROOT/domain")" "domain still applied when the restart fails"
grep -q "Could not restart wlanpi-profiler; restart it to apply FR" "$TMPROOT/out"
assert_eq "0" "$?" "failed restart is reported"

echo
echo "Tests passed: $tests_passed, failed: $tests_failed"
[ "$tests_failed" -eq 0 ]
