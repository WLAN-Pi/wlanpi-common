#!/bin/bash
# Hardware test for configure_pcie_32bit_dma: boots a WLAN Pi with a given
# wlanpi-config-at-startup.sh and pcie-32bit-dma start state, and checks the
# real boot does what the script's function predicts on that device's bus.
# pcie-32bit-dma-parity-test01.sh compares those predictions with the shipped
# and previous scripts; this test ties them to real boots.
#
#   pcie-32bit-dma-device-test01.sh HOST SCRIPT STATE...   STATE: keep on off absent
#   pcie-32bit-dma-device-test01.sh HOST --restore
#
# HOST is an ssh destination that logs in without a prompt; set SSH (for
# example SSH="sshpass -e ssh") to change the client. SUDO_PASS is the sudo
# password, sent on stdin. SCRIPT must define configure_pcie_32bit_dma.
#
# Disruptive: installs SCRIPT over the packaged script, edits config.txt and
# reboots. The first run backs both up to /root/pcie-dma-test and, if the
# journal is volatile, makes it persistent so boots can be counted.
# --restore puts all of it back and reboots.
#
# For each state, once the device has been up SETTLE seconds (default 75):
#   - boots taken = 1 + the reboot the function predicted, and the last boot
#     asked for no reboot
#   - the overlay ends in the predicted state
#   - config.txt changed only in pcie-32bit-dma and blank lines; board unchanged
#   - wlanpi-config-at-startup succeeded; no newly failed units
set -u
B=/root/pcie-dma-test
S=/opt/wlanpi-common/wlanpi-config-at-startup.sh
C=/boot/firmware/config.txt
DROPIN=/etc/systemd/journald.conf.d/zz-pcie-dma-test.conf
ins='# Allows PCIe adapters with 32-bit DMA masks to work\n'

# ---- device side, run as root ----
board() { wlanpi-model | grep "Main board:" | cut -d ":" -f2 | xargs; }
state() {
    local s active
    s=$(awk '/^\[/{s=($0=="[cm4]")} s' "$1")
    active=$(grep -c '^[[:space:]]*dtoverlay=pcie-32bit-dma' <<< "$s")
    if [ "$active" -gt 1 ]; then echo dup
    elif [ "$active" -eq 1 ]; then echo on
    elif grep -q '^[[:space:]]*#dtoverlay=pcie-32bit-dma' <<< "$s"; then echo off
    else echo absent
    fi
}
without_overlay() { grep -v 'pcie-32bit-dma\|Allows .* to work' "$1"; }
# The enable path inserts a blank line with the overlay
significant() { without_overlay "$1" | grep -v '^[[:space:]]*$'; }
failed_units() { systemctl --failed --no-legend --plain | awk '{print $1}' | sort; }

dev_prep() { # SCRIPT STATE
    local script=$1 want=$2 rb
    sed -n '/^configure_pcie_32bit_dma()/,/^}/p' "$script" | grep -q pcie-32bit-dma ||
        { echo "FAIL: $script has no configure_pcie_32bit_dma"; return 1; }
    mkdir -p "$B"
    if [ ! -e "$B/startup.sh" ]; then
        cp -a "$S" "$B/startup.sh"
        cp -a "$C" "$B/config.txt"
        failed_units > "$B/failed"
    fi
    if [ ! -e "$B/journal" ] && [ "$(systemd-analyze cat-config systemd/journald.conf | grep '^Storage=' | tail -1)" != Storage=persistent ]; then
        if [ -d "/var/log/journal/$(cat /etc/machine-id)" ]; then echo existed > "$B/journal"; else echo added > "$B/journal"; fi
        mkdir -p "${DROPIN%/*}"
        printf '[Journal]\nStorage=persistent\n' > "$DROPIN"
        systemctl restart systemd-journald
        journalctl --flush
    fi
    install -m755 "$script" "$S"
    case $want in
        keep) ;;
        absent) without_overlay "$B/config.txt" > "$C" ;;
        on) without_overlay "$B/config.txt" | sed "s/^\[cm4\]$/&\n${ins}dtoverlay=pcie-32bit-dma/" > "$C" ;;
        off) without_overlay "$B/config.txt" | sed "s/^\[cm4\]$/&\n${ins}#dtoverlay=pcie-32bit-dma/" > "$C" ;;
        *) echo "FAIL: unknown state $want"; return 1 ;;
    esac
    sync
    [ "$want" = keep ] || [ "$(state "$C")" = "$want" ] || { echo "FAIL: could not set start state $want"; return 1; }
    cp "$C" "$B/start.txt"
    board > "$B/board"
    # What the installed function does on this bus with this config.txt
    cp "$C" "$B/predict.txt"
    rb=$(
        set -e
        CONFIG_FILE=$B/predict.txt REQUIRES_REBOOT=0 BOARD=$(cat "$B/board")
        export CONFIG_FILE REQUIRES_REBOOT BOARD
        debugger() { :; }
        log_reason() { :; }
        # shellcheck source=/dev/null
        source <(sed -n '/^configure_pcie_32bit_dma()/,/^}/p' "$S")
        case "$BOARD" in "Mcuzone M4" | "Mcuzone M4+" | "WLAN Pi Pro") configure_pcie_32bit_dma ;; esac
        echo "$REQUIRES_REBOOT"
    ) || { echo "FAIL: configure_pcie_32bit_dma aborted"; return 1; }
    echo "$rb $(state "$B/predict.txt")" > "$B/predict"
    tr -d - < /proc/sys/kernel/random/boot_id > "$B/mark"
    echo "start: board=$(cat "$B/board") overlay=$(state "$C") predicted: reboot=$rb overlay=$(state "$B/predict.txt")"
}

dev_check() {
    local boots b n=0 log last=0 pr ps fails=0 new
    boots=$(journalctl --list-boots --no-pager | awk -v m="$(cat "$B/mark")" 'f {print $2} $2 == m {f = 1}')
    for b in $boots; do
        n=$((n + 1))
        log=$(journalctl -b "$b" -u wlanpi-config-at-startup -o cat --no-pager)
        last=0; grep -q 'rebooting now' <<< "$log" && last=1
        echo "  boot $n (${b:0:8}): $(grep -m1 '^Applying' <<< "$log" || echo 'no Applying line') | reboot requested: $last"
    done
    read -r pr ps < "$B/predict"
    ok() { if "$@"; then echo "  PASS: $label"; else echo "  FAIL: $label"; fails=$((fails + 1)); fi; }
    label="boots: $n, predicted $((1 + pr))"; ok [ "$n" -eq $((1 + pr)) ]
    label="last boot asked for no reboot"; ok [ "$last" -eq 0 ]
    label="overlay: $(state "$C"), predicted $ps"; ok [ "$(state "$C")" = "$ps" ]
    label="config.txt changed only in pcie-32bit-dma and blank lines"; ok cmp -s <(significant "$B/start.txt") <(significant "$C")
    label="board: $(board)"; ok [ "$(board)" = "$(cat "$B/board")" ]
    label="wlanpi-config-at-startup: $(systemctl show wlanpi-config-at-startup -p Result --value)"
    ok [ "$(systemctl show wlanpi-config-at-startup -p Result --value)" = success ]
    new=$(comm -13 "$B/failed" <(failed_units) | tr '\n' ' ')
    label="no newly failed units ${new:+($new)}"; ok [ -z "$new" ]
    echo "  info: wifi ifaces=$(/usr/sbin/iw dev 2>/dev/null | grep -c Interface) core/fpms/webui=$(systemctl is-active wlanpi-core wlanpi-fpms wlanpi-webui | tr '\n' ' ')"
    [ "$fails" -eq 0 ]
}

dev_restore() {
    [ -e "$B/startup.sh" ] || { echo "nothing to restore"; return 0; }
    cp -a "$B/startup.sh" "$S"
    cp -a "$B/config.txt" "$C"
    sync
    if [ -e "$B/journal" ]; then
        rm -f "$DROPIN"
        rmdir --ignore-fail-on-non-empty "${DROPIN%/*}"
        systemctl restart systemd-journald
        [ "$(cat "$B/journal")" = existed ] || rm -rf "/var/log/journal/$(cat /etc/machine-id)"
    fi
    rm -rf "$B"
    echo "restored startup script and config.txt; rebooting"
}

if [ "${1:-}" = --device ]; then
    shift
    case $1 in
        prep) dev_prep "$2" "$3" ;;
        check) dev_check ;;
        restore) dev_restore ;;
        reboot) systemd-run --on-active=2 systemctl reboot > /dev/null 2>&1 ;;
        uptime) cut -d. -f1 /proc/uptime ;;
    esac
    exit
fi

# ---- controller side ----
[ $# -ge 2 ] || { sed -n '8,9p' "$0" | sed 's/^# //'; exit 2; }
HOST=$1; shift
read -r -a SSH_CMD <<< "${SSH:-ssh}"
SETTLE=${SETTLE:-75}
sh_() { "${SSH_CMD[@]}" -o ConnectTimeout=5 "$HOST" "$@"; }
remote() { # remote ARGS: this file on HOST, as root; the password goes on stdin
    sh_ "cat > /tmp/pcie-dma-test.sh" < "$0" &&
        sh_ "sudo -S -p '' bash /tmp/pcie-dma-test.sh --device $*" <<< "${SUDO_PASS:-}"
}
reboot_and_settle() {
    local u
    remote reboot || return 1
    sleep 20
    for _ in $(seq 1 90); do
        u=$(remote uptime 2> /dev/null) && [ -n "$u" ] && [ "$u" -ge "$SETTLE" ] && return 0
        sleep 5
    done
    echo "FAIL: $HOST did not come back"; return 1
}

if [ "$1" = --restore ]; then
    remote restore && reboot_and_settle
    exit
fi
SCRIPT=$1; shift
[ -r "$SCRIPT" ] || { echo "cannot read $SCRIPT"; exit 2; }
fails=0
for want in "$@"; do
    echo "== $HOST $(basename "$SCRIPT") from $want"
    if sh_ "cat > /tmp/pcie-dma-candidate.sh" < "$SCRIPT" && remote prep /tmp/pcie-dma-candidate.sh "$want" &&
        reboot_and_settle && remote check; then :; else fails=$((fails + 1)); fi
done
echo "$HOST: $(($# - fails))/$# states passed"
[ "$fails" -eq 0 ]
