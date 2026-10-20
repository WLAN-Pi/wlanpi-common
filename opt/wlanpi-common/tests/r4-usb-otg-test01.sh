#!/bin/bash
# Behaviour test for enable_r4_usb_otg in wlanpi-config-at-startup.sh.
#
#   r4-usb-otg-test01.sh [SCRIPT]
#
# Each case runs the function under `set -e`, as at boot, on a config.txt
# fixture, then runs it again on the result. The first run must reboot only
# when it adds the block; the second must change nothing and never reboot.
set -u

SCRIPT=${1:-"$(dirname "$0")/../wlanpi-config-at-startup.sh"}
TMP=$(mktemp -d) || exit 2
trap 'rm -rf "$TMP"' EXIT
sed -n '/^enable_r4_usb_otg()/,/^}/p' "$SCRIPT" > "$TMP/function.sh"
[ -s "$TMP/function.sh" ] || { echo "enable_r4_usb_otg not found in $SCRIPT" >&2; exit 2; }

# config.txt as on a DeadEye R4 (192.168.6.59): dwc2 only under [cm4] and
# [cm5], the kernel package's block last.
base() {
    cat <<'EOF'
arm_64bit=1
dtparam=act_led_trigger=heartbeat

[pi4]

[cm4]
otg_mode=0
dtoverlay=dwc2,dr_mode=otg
dtoverlay=disable-wifi

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
        enable_r4_usb_otg
        echo "$REQUIRES_REBOOT"
    )
    rc=$?
    [ "$rc" -eq 0 ] && echo "$out" || echo "aborted(rc=$rc)"
}

# Active dwc2 overlays the firmware applies on a Pi 4B: before any filter, or
# under [all], [pi4] or [board-type=0x11].
active() {
    awk 'BEGIN{on=1} /^\[/{on=($0=="[all]"||$0=="[pi4]"||$0=="[board-type=0x11]"); next} on && /^dtoverlay=dwc2(,|$)/' "$1" | grep -c .
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
    elif [ "$got_reboot" = 1 ] && ! tail -n 4 "$TMP/config.txt" | grep -v '^#' | tr '\n' ' ' | grep -qx '\[board-type=0x11\] dtoverlay=dwc2,dr_mode=peripheral \[all\] '; then
        note=" (appended block is not [board-type=0x11] peripheral ending in [all])"
    fi
    if [ "$got_reboot" = "$want_reboot" ] && [ "$got_active" = "$want_active" ] && [ -z "$note" ]; then
        printf 'PASS  %-48s reboot=%s active=%s\n' "$name" "$got_reboot" "$got_active"
    else
        printf 'FAIL  %-48s reboot=%s active=%s%s, want reboot=%s active=%s\n' \
            "$name" "$got_reboot" "$got_active" "$note" "$want_reboot" "$want_active"
        fails=$((fails + 1))
    fi
}

check "DeadEye R4, dwc2 only under [cm4]/[cm5]" 1 1 < <(base)
check "full image template ([cm4] dr_mode=host)" 1 1 < <(base | sed 's/^dtoverlay=dwc2,dr_mode=otg$/dtoverlay=dwc2,dr_mode=host/')
check "after the onboard Wi-Fi block (#139)" 1 1 < <(base; printf '\n[pi4]\n# Onboard Wi-Fi has no monitor mode. Comment out to keep it on.\ndtoverlay=disable-wifi\n[all]\n')
check "bullseye R4 ([pi4] dr_mode=otg)" 0 1 < <(printf 'arm_64bit=1\n[pi4]\ndtoverlay=dwc2,dr_mode=otg\n[all]\nkernel=kernel8-wp.img\n')
check "already under [board-type=0x11]" 0 1 < <(base; printf '\n[board-type=0x11]\ndtoverlay=dwc2,dr_mode=peripheral\n[all]\n')
check "already before any section" 0 1 < <(base | sed '1i dtoverlay=dwc2,dr_mode=peripheral')
check "commented under [board-type=0x11] (opt-out)" 0 0 < <(base; printf '\n[board-type=0x11]\n# dtoverlay=dwc2,dr_mode=peripheral\n[all]\n')
check "dwc2-something is not dwc2" 1 1 < <(base | sed '0,/^\[all\]$/s//[all]\ndtoverlay=dwc2-foo/')
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

[ "$fails" -eq 0 ] && echo "r4-usb-otg: all cases passed ($SCRIPT)" || echo "r4-usb-otg: $fails case(s) failed ($SCRIPT)"
[ "$fails" -eq 0 ]
