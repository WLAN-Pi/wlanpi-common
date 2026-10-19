#!/bin/bash
# Behaviour test for disable_r4_onboard_wifi in wlanpi-config-at-startup.sh.
#
#   r4-onboard-wifi-test01.sh [SCRIPT]
#
# Each case runs the function under `set -e`, as at boot, on a config.txt
# fixture, then runs it again on the result. The first run must reboot only
# when it adds the line; the second must change nothing and never reboot.
set -u

SCRIPT=${1:-"$(dirname "$0")/../wlanpi-config-at-startup.sh"}
TMP=$(mktemp -d) || exit 2
trap 'rm -rf "$TMP"' EXIT
sed -n '/^disable_r4_onboard_wifi()/,/^}/p' "$SCRIPT" > "$TMP/function.sh"
[ -s "$TMP/function.sh" ] || { echo "disable_r4_onboard_wifi not found in $SCRIPT" >&2; exit 2; }

# config.txt as on a DeadEye R4 (192.168.6.59): two [pi4] sections, the
# onboard radio only disabled under [cm4], the kernel package's block last.
base() {
    cat <<'EOF'
arm_64bit=1
dtparam=act_led_trigger=heartbeat

[pi4]

[cm4]
otg_mode=0
# Disable CM4's Wi-Fi and BT radio if they are present
dtoverlay=disable-wifi
dtoverlay=disable-bt

[pi5]

[cm5]
dtoverlay=dwc2,dr_mode=host

[all]
# BEGIN WLAN Pi kernel selection
[pi4]
kernel=wlanpi-kernel8.img
[pi5]
kernel=wlanpi-kernel_2712.img
[all]
# END WLAN Pi kernel selection
EOF
}

# Prints the REQUIRES_REBOOT the function leaves, or aborted(rc=N).
run() {
    local out rc
    out=$(
        set -e
        CONFIG_FILE="$TMP/config.txt"
        REQUIRES_REBOOT=0
        export CONFIG_FILE REQUIRES_REBOOT
        debugger() { :; }
        # logger can fail early in boot; must not abort
        log_reason() { return 1; }
        # shellcheck source=/dev/null
        source "$TMP/function.sh"
        disable_r4_onboard_wifi
        echo "$REQUIRES_REBOOT"
    )
    rc=$?
    [ "$rc" -eq 0 ] && echo "$out" || echo "aborted(rc=$rc)"
}

# Active disable-wifi lines the firmware applies on a Pi 4B: before any
# filter, or under [all] or [pi4].
active() {
    awk 'BEGIN{on=1} /^\[/{on=($0=="[all]"||$0=="[pi4]"); next} on && /^dtoverlay=disable-wifi$/' "$1" | grep -c .
}

fails=0
# check NAME WANT_REBOOT WANT_ACTIVE < fixture
check() {
    local name=$1 want_reboot=$2 want_active=$3 got_reboot got_again got_active note=""
    cat > "$TMP/config.txt"
    cp "$TMP/config.txt" "$TMP/before.txt"
    got_reboot=$(run)
    cp "$TMP/config.txt" "$TMP/first.txt"
    got_again=$(run)
    got_active=$(active "$TMP/config.txt")
    if [ "$got_again" != 0 ] || ! cmp -s "$TMP/first.txt" "$TMP/config.txt"; then
        note=" (second run: reboot=$got_again, changed=$(cmp -s "$TMP/first.txt" "$TMP/config.txt" && echo no || echo yes))"
    elif [ "$got_reboot" = 0 ] && ! cmp -s "$TMP/before.txt" "$TMP/config.txt"; then
        note=" (file changed without a reboot)"
    elif [ "$got_reboot" = 1 ] && ! cmp -s -n "$(wc -c < "$TMP/before.txt")" "$TMP/before.txt" "$TMP/config.txt"; then
        note=" (existing lines changed, not only appended)"
    elif [ "$(tail -n 1 "$TMP/config.txt")" != "[all]" ] && [ "$got_reboot" = 1 ]; then
        note=" (appended block does not end in [all])"
    fi
    if [ "$got_reboot" = "$want_reboot" ] && [ "$got_active" = "$want_active" ] && [ -z "$note" ]; then
        printf 'PASS  %-48s reboot=%s active=%s\n' "$name" "$got_reboot" "$got_active"
    else
        printf 'FAIL  %-48s reboot=%s active=%s%s, want reboot=%s active=%s\n' \
            "$name" "$got_reboot" "$got_active" "$note" "$want_reboot" "$want_active"
        fails=$((fails + 1))
    fi
}

check "DeadEye R4, only [cm4] disables" 1 1 < <(base)
check "no [pi4] section at all" 1 1 < <(base | sed '/^\[pi4\]$/d')
check "already under first [pi4]" 0 1 < <(base | sed '0,/^\[pi4\]$/s//[pi4]\ndtoverlay=disable-wifi/')
check "already under [all]" 0 1 < <(base | sed '0,/^\[all\]$/s//[all]\ndtoverlay=disable-wifi/')
check "already before any section" 0 1 < <(base | sed '1i dtoverlay=disable-wifi')
check "commented under [pi4] (opt-out)" 0 0 < <(base | sed '0,/^\[pi4\]$/s//[pi4]\n#dtoverlay=disable-wifi/')
check "commented with space under [pi4] (opt-out)" 0 0 < <(base | sed '0,/^\[pi4\]$/s//[pi4]\n# dtoverlay=disable-wifi/')
check "commented only under [cm4]" 1 1 < <(base | sed 's/^dtoverlay=disable-wifi$/#&/')
check "under [pi5] only" 1 1 < <(base | sed 's/^\[pi5\]$/&\ndtoverlay=disable-wifi/')
check "bullseye R4 ([pi4] and [pi3])" 0 1 < <(printf 'arm_64bit=1\n[pi4]\ndtoverlay=disable-wifi\n[pi3]\ndtoverlay=disable-wifi\n[all]\nkernel=kernel8-wp.img\n')
check "no trailing newline" 1 1 < <(base | head -c -1)

# Missing config.txt: never create one.
rm -f "$TMP/config.txt"
got=$(run)
if [ "$got" = 0 ] && [ ! -e "$TMP/config.txt" ]; then
    printf 'PASS  %-48s reboot=%s created=no\n' "missing config.txt" "$got"
else
    printf 'FAIL  %-48s reboot=%s created=%s, want reboot=0 created=no\n' \
        "missing config.txt" "$got" "$([ -e "$TMP/config.txt" ] && echo yes || echo no)"
    fails=$((fails + 1))
fi

[ "$fails" -eq 0 ] && echo "r4-onboard-wifi: all cases passed ($SCRIPT)" || echo "r4-onboard-wifi: $fails case(s) failed ($SCRIPT)"
[ "$fails" -eq 0 ]
