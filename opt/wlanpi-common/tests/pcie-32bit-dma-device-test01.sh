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
# reboots; it prints a warning and waits 10 seconds for Ctrl-C first. The
# first run backs both up to /root/pcie-dma-test, installs a
# guard unit that restores them if a state takes more than MAX_BOOTS boots
# (a boot loop), and makes a volatile journal persistent so boots can be
# counted. --restore puts all of it back and reboots. Run --restore before
# upgrading wlanpi-common: restoring puts back the older startup script.
#
# For each state, once the device has been up SETTLE seconds (default 75):
#   - boots taken = 1 + the reboot the function predicted, and the last boot
#     asked for no reboot
#   - the overlay ends in the predicted state
#   - config.txt changed only in the managed [cm4] lines (below); board unchanged
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
# The lines the startup script manages, and the only ones this test edits or
# lets change, inside [cm4]: the overlay, active or commented, and the
# comment inserted with it (current or legacy text)
MANAGED='^[[:space:]]*#?dtoverlay=pcie-32bit-dma[[:space:]]*$|^# Allows (PCIe adapters with 32-bit DMA masks to work|MT7921K adapter to work with 64-bit kernel)$'

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
# FILE without the managed [cm4] lines, and without the blank line the
# startup script inserts after the overlay; everything else byte for byte
unmanaged() {
    awk -v re="$MANAGED" '
        /^\[/ { s = ($0 == "[cm4]") }
        s && $0 ~ re { drop = 1; next }
        drop && /^[[:space:]]*$/ { drop = 0; next }
        { drop = 0; print }' "$1"
}
failed_units() { systemctl --failed --no-legend --plain | awk '{print $1}' | sort; }
active_services() {
    local s
    for s in $SERVICES; do systemctl is-active -q "$s" && echo "$s"; done
    return 0
}
# Replace DEST with SRC through a verified temporary file next to it, so an
# interrupt leaves the old file or the new one, never a partial one. MODE is
# optional: the vfat boot partition takes none.
put_file() { # SRC DEST [MODE]
    local tmp="$2.pcie-dma-test"
    if [ -s "$1" ] && cp "$1" "$tmp" && { [ -z "${3:-}" ] || chmod "$3" "$tmp"; } &&
        cmp -s "$1" "$tmp" && mv -f "$tmp" "$2" && sync; then
        return 0
    fi
    rm -f "$tmp"
    return 1
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
        [ ! -e "$DROPIN" ] || { echo "FAIL: $DROPIN already exists"; return 1; }
        if [ -d "/var/log/journal/$(cat /etc/machine-id)" ]; then echo existed > "$B/journal"; else echo added > "$B/journal"; fi
        mkdir -p "${DROPIN%/*}" && printf '[Journal]\nStorage=persistent\n' > "$DROPIN" &&
            systemctl restart systemd-journald && journalctl --flush || { echo "FAIL: could not make the journal persistent"; return 1; }
    fi
    put_file "$script" "$S" 755 || { echo "FAIL: could not install $script"; return 1; }
    case $want in
        keep) cp "$C" "$B/want.txt" ;;
        absent) unmanaged "$B/config.txt" > "$B/want.txt" ;;
        on) unmanaged "$B/config.txt" | sed "s/^\[cm4\]$/&\n${ins}dtoverlay=pcie-32bit-dma/" > "$B/want.txt" ;;
        off) unmanaged "$B/config.txt" | sed "s/^\[cm4\]$/&\n${ins}#dtoverlay=pcie-32bit-dma/" > "$B/want.txt" ;;
    esac
    [ "$want" = keep ] || [ "$(state "$B/want.txt")" = "$want" ] || { echo "FAIL: could not build start state $want"; return 1; }
    put_file "$B/want.txt" "$C" || { echo "FAIL: could not write $C"; return 1; }
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
    label="config.txt changed only in the managed [cm4] lines"; ok cmp -s <(unmanaged "$B/start.txt") <(unmanaged "$C")
    label="board: $(board)"; ok [ "$(board)" = "$(cat "$B/board")" ]
    label="wlanpi-config-at-startup: $(systemctl show wlanpi-config-at-startup -p Result --value)"
    ok [ "$(systemctl show wlanpi-config-at-startup -p Result --value)" = success ]
    while read -r s; do systemctl is-active -q "$s" || down="$down $s"; done < "$B/active"
    label="active before the test, still active: $(tr '\n' ' ' < "$B/active")${down:+(down:$down)}"; ok [ -z "$down" ]
    label="$GUARD: $(systemctl show "$GUARD" -p Result --value)"; ok [ "$(systemctl show "$GUARD" -p Result --value)" = success ]
    new=$(comm -13 "$B/failed" <(failed_units) | tr '\n' ' ')
    label="no newly failed units ${new:+($new)}"; ok [ -z "$new" ]
    echo "  info: wifi ifaces=$(/usr/sbin/iw dev 2>/dev/null | grep -c Interface)"
    [ "$fails" -eq 0 ]
}

# Everything or nothing: the backup is kept unless every step succeeds, and
# every step is safe to repeat, so a failed restore can be run again
dev_restore() {
    [ -d "$B" ] || { echo "nothing to restore"; return 0; }
    put_file "$B/startup.sh" "$S" "$(stat -c %a "$B/startup.sh")" || { echo "FAIL: could not restore $S; backup kept in $B"; return 1; }
    put_file "$B/config.txt" "$C" || { echo "FAIL: could not restore $C; backup kept in $B"; return 1; }
    systemctl disable -q "$GUARD" 2> /dev/null
    rm -f "/etc/systemd/system/$GUARD" && systemctl daemon-reload || { echo "FAIL: could not remove $GUARD; backup kept in $B"; return 1; }
    if [ -e "$B/journal" ]; then
        # Remove the journal files first, so the restarted journald does not reopen them
        rm -f "$DROPIN" && { [ ! -d "${DROPIN%/*}" ] || rmdir --ignore-fail-on-non-empty "${DROPIN%/*}"; } &&
            { [ "$(cat "$B/journal")" = existed ] || rm -rf "/var/log/journal/$(cat /etc/machine-id)"; } &&
            systemctl restart systemd-journald || { echo "FAIL: could not restore journald; backup kept in $B"; return 1; }
    fi
    rm -rf "$B"
    echo "restore complete"
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
    if ! { sh_ "cat > '$d/test.sh'" < "$0" && { [ -z "${SCRIPT:-}" ] || sh_ "cat > '$d/candidate.sh'" < "$SCRIPT"; }; }; then
        sh_ "rm -rf '$d'"; return 1
    fi
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

# Not a prompt, so unattended runs still work; the pause is the chance to cancel
warn() {
    local extra=""
    [ -z "${2:-}" ] || extra="  *  $2"$'\n'
    cat >&2 << EOF

  ************************************************************************
  *  WARNING: this test REBOOTS $HOST, possibly several times,
  *  and $1.
${extra}  *  Press Ctrl-C within 10 seconds to cancel. Nothing has been changed yet.
  ************************************************************************

EOF
    sleep 10
}

if [ "$1" = --restore ]; then
    warn "restores its startup script and config.txt"
    remote restore && reboot_and_settle
    exit
fi
SCRIPT=$1; shift
[ -r "$SCRIPT" ] || { echo "cannot read $SCRIPT"; exit 2; }
[ $# -ge 1 ] || usage
for want in "$@"; do
    case $want in keep | on | off | absent) ;; *) echo "unknown state: $want"; usage ;; esac
done
warn "replaces its startup script and edits config.txt until --restore" \
    "Run --restore before upgrading wlanpi-common."
fails=0
for want in "$@"; do
    echo "== $HOST $(basename "$SCRIPT") from $want"
    if remote prep @D@/candidate.sh "$want" && reboot_and_settle && remote check; then :; else fails=$((fails + 1)); fi
done
echo "$HOST: $(($# - fails))/$# states passed"
[ "$fails" -eq 0 ]
