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
# reboots. The first run backs both up to /root/pcie-dma-test, installs a
# guard unit that restores them if a state takes more than MAX_BOOTS boots
# (a boot loop), and makes a volatile journal persistent so boots can be
# counted. --restore puts all of it back and reboots. Do not upgrade
# wlanpi-common in between: --restore would put back the older script.
#
# For each state, once the device has been up SETTLE seconds (default 75):
#   - boots taken = 1 + the reboot the function predicted, and the last boot
#     asked for no reboot
#   - the overlay ends in the predicted state
#   - config.txt changed only in pcie-32bit-dma and blank lines; board unchanged
#   - wlanpi-config-at-startup succeeded; services active before the test are
#     active; no newly failed units
set -u
B=/root/pcie-dma-test
S=/opt/wlanpi-common/wlanpi-config-at-startup.sh
# Same choice as wlanpi-config-at-startup.sh
if [ -d /boot/firmware ]; then C=/boot/firmware/config.txt; else C=/boot/config.txt; fi
DROPIN=/etc/systemd/journald.conf.d/zz-pcie-dma-test.conf
GUARD=pcie-dma-test-guard.service
MAX_BOOTS=4
SERVICES="wlanpi-core wlanpi-fpms wlanpi-webui"
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
active_services() {
    local s
    for s in $SERVICES; do systemctl is-active -q "$s" && echo "$s"; done
    return 0
}
# Replace config.txt from a file, via a temporary file on the same filesystem
put_config() {
    [ -s "$1" ] && cp "$1" "$C.pcie-dma-test" && mv -f "$C.pcie-dma-test" "$C" && sync
}

dev_prep() { # SCRIPT STATE
    local script=$1 want=$2 rb
    case $want in keep | on | off | absent) ;; *) echo "FAIL: unknown state $want"; return 1 ;; esac
    [ -f "$C" ] && [ -w "$C" ] || { echo "FAIL: $C is missing or not writable"; return 1; }
    sed -n '/^configure_pcie_32bit_dma()/,/^}/p' "$script" | grep -q pcie-32bit-dma ||
        { echo "FAIL: $script has no configure_pcie_32bit_dma"; return 1; }
    # Back up once, completely, or not at all
    if [ ! -d "$B" ]; then
        rm -rf "$B.new"
        if ! { mkdir -m 700 "$B.new" && cp -a "$S" "$B.new/startup.sh" && cp "$C" "$B.new/config.txt" &&
            failed_units > "$B.new/failed" && active_services > "$B.new/active" && mv "$B.new" "$B"; }; then
            rm -rf "$B.new"; echo "FAIL: could not back up to $B"; return 1
        fi
    fi
    # Boot-loop guard: restores the backup if a state takes too many boots
    install -m755 "$0" "$B/test.sh" || return 1
    printf '[Unit]\nDescription=pcie-32bit-dma device test guard\nAfter=local-fs.target\nBefore=wlanpi-config-at-startup.service\n\n[Service]\nType=oneshot\nExecStart=/bin/bash %s/test.sh --device guard\n\n[Install]\nWantedBy=multi-user.target\n' "$B" > "/etc/systemd/system/$GUARD" &&
        systemctl daemon-reload && systemctl enable -q "$GUARD" || { echo "FAIL: could not install $GUARD"; return 1; }
    echo 0 > "$B/boots"
    if [ ! -e "$B/journal" ] && [ "$(systemd-analyze cat-config systemd/journald.conf | grep '^Storage=' | tail -1)" != Storage=persistent ]; then
        if [ -d "/var/log/journal/$(cat /etc/machine-id)" ]; then echo existed > "$B/journal"; else echo added > "$B/journal"; fi
        mkdir -p "${DROPIN%/*}" && printf '[Journal]\nStorage=persistent\n' > "$DROPIN" &&
            systemctl restart systemd-journald && journalctl --flush || { echo "FAIL: could not make the journal persistent"; return 1; }
    fi
    install -m755 "$script" "$S" && cmp -s "$script" "$S" || { echo "FAIL: could not install $script"; return 1; }
    case $want in
        keep) cp "$C" "$B/want.txt" ;;
        absent) without_overlay "$B/config.txt" > "$B/want.txt" ;;
        on) without_overlay "$B/config.txt" | sed "s/^\[cm4\]$/&\n${ins}dtoverlay=pcie-32bit-dma/" > "$B/want.txt" ;;
        off) without_overlay "$B/config.txt" | sed "s/^\[cm4\]$/&\n${ins}#dtoverlay=pcie-32bit-dma/" > "$B/want.txt" ;;
    esac
    [ "$want" = keep ] || [ "$(state "$B/want.txt")" = "$want" ] || { echo "FAIL: could not build start state $want"; return 1; }
    put_config "$B/want.txt" && cmp -s "$B/want.txt" "$C" || { echo "FAIL: could not write $C"; return 1; }
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
    local boots b n=0 log last=0 pr ps fails=0 new s down=""
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
    while read -r s; do systemctl is-active -q "$s" || down="$down $s"; done < "$B/active"
    label="active before the test, still active: $(tr '\n' ' ' < "$B/active")${down:+(down:$down)}"; ok [ -z "$down" ]
    new=$(comm -13 "$B/failed" <(failed_units) | grep -vx "$GUARD" | tr '\n' ' ')
    label="no newly failed units ${new:+($new)}"; ok [ -z "$new" ]
    echo "  info: wifi ifaces=$(/usr/sbin/iw dev 2>/dev/null | grep -c Interface)"
    [ "$fails" -eq 0 ]
}

# Everything or nothing: the backup is kept unless both files are back
dev_restore() {
    [ -d "$B" ] || { echo "nothing to restore"; return 0; }
    cp -a "$B/startup.sh" "$S" && cmp -s "$B/startup.sh" "$S" || { echo "FAIL: could not restore $S; backup kept in $B"; return 1; }
    put_config "$B/config.txt" && cmp -s "$B/config.txt" "$C" || { echo "FAIL: could not restore $C; backup kept in $B"; return 1; }
    systemctl disable -q "$GUARD" 2> /dev/null
    rm -f "/etc/systemd/system/$GUARD"
    systemctl daemon-reload
    if [ -e "$B/journal" ]; then
        rm -f "$DROPIN"
        rmdir --ignore-fail-on-non-empty "${DROPIN%/*}" 2> /dev/null
        systemctl restart systemd-journald
        [ "$(cat "$B/journal")" = existed ] || rm -rf "/var/log/journal/$(cat /etc/machine-id)"
    fi
    rm -rf "$B"
    echo "restored startup script and config.txt"
}

# Runs before wlanpi-config-at-startup on every boot while the test is set up
dev_guard() {
    local n
    n=$(($(cat "$B/boots" 2> /dev/null || echo 0) + 1))
    echo "$n" > "$B/boots"
    [ "$n" -gt "$MAX_BOOTS" ] || return 0
    echo "boot $n since the last start state (limit $MAX_BOOTS): restoring the backup"
    dev_restore
}

if [ "${1:-}" = --device ]; then
    shift
    case $1 in
        prep) dev_prep "$2" "$3" ;;
        check) dev_check ;;
        restore) dev_restore ;;
        guard) dev_guard ;;
        reboot) systemd-run --on-active=2 systemctl reboot > /dev/null 2>&1 ;;
    esac
    exit
fi

# ---- controller side ----
usage() { sed -n '8,9p' "$0" | sed 's/^# //'; exit 2; }
[ $# -ge 2 ] || usage
HOST=$1; shift
read -r -a SSH_CMD <<< "${SSH:-ssh}"
SETTLE=${SETTLE:-75}
sh_() { "${SSH_CMD[@]}" -o ConnectTimeout=5 -- "$HOST" "$@"; }
# remote ARGS: this file (and SCRIPT, if set) staged in a private directory
# on HOST, run there as root; the sudo password goes on stdin
remote() {
    local d
    d=$(sh_ 'mktemp -d') && [ -n "$d" ] || return 1
    sh_ "cat > '$d/test.sh'" < "$0" || return 1
    [ -z "${SCRIPT:-}" ] || sh_ "cat > '$d/candidate.sh'" < "$SCRIPT" || return 1
    sh_ "sudo -S -p '' bash '$d/test.sh' --device ${*//@D@/$d}; rc=\$?; rm -rf '$d'; exit \$rc" <<< "${SUDO_PASS:-}"
}
reboot_and_settle() {
    local u
    remote reboot || return 1
    sleep 20
    for _ in $(seq 1 90); do
        u=$(sh_ 'cut -d. -f1 /proc/uptime' 2> /dev/null) && [ -n "$u" ] && [ "$u" -ge "$SETTLE" ] && return 0
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
[ $# -ge 1 ] || usage
for want in "$@"; do
    case $want in keep | on | off | absent) ;; *) echo "unknown state: $want"; usage ;; esac
done
fails=0
for want in "$@"; do
    echo "== $HOST $(basename "$SCRIPT") from $want"
    if remote prep @D@/candidate.sh "$want" && reboot_and_settle && remote check; then :; else fails=$((fails + 1)); fi
done
echo "$HOST: $(($# - fails))/$# states passed"
[ "$fails" -eq 0 ]
