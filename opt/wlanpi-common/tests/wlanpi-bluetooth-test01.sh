#!/bin/bash
# Behaviour test for wlanpi-bluetooth.sh adapter choice and pairing removal.
#
#   wlanpi-bluetooth-test01.sh [SCRIPT]
#
# Runs the script with only stubs and the text tools it needs on PATH, and
# checks which adapter it reads the alias from and removes pairings on.
set -u

SCRIPT=${1:-"$(dirname "$0")/../wlanpi-bluetooth.sh"}
TMP=$(mktemp -d) || exit 2
trap 'rm -rf "$TMP"' EXIT
BIN="$TMP/bin"
mkdir -p "$BIN"
for tool in awk cat grep; do
    ln -s "$(command -v "$tool")" "$BIN/$tool" || exit 2
done

stub() {
    printf '#!/bin/bash\necho "%s $*" >> "$LOG"\n%s\n' "$1" "${2:-}" > "$BIN/$1"
    chmod +x "$BIN/$1"
}
stub bt-adapter "printf '[hci9]\n  Name: x\n  Alias: wlanpi-test [rw]\n'"
stub systemctl

# BlueZ's objects as busctl tree --list prints them: a dongle on hci0 and the
# onboard adapter on hci1, each with a paired device, plus an unpaired device
# and a device's child object on hci1. PAIRED_OBJECTS lists the paired ones.
# Not TREE or PAIRED: the script under test sets those.
export TREE_FILE="$TMP/tree" PAIRED_OBJECTS="$TMP/paired"
printf '%s\n' / /org /org/bluez /org/bluez/hci0 /org/bluez/hci0/dev_AA_00_00_00_00_01 \
    /org/bluez/hci1 /org/bluez/hci1/dev_AA_00_00_00_00_02 /org/bluez/hci1/dev_AA_00_00_00_00_02/fd0 \
    /org/bluez/hci1/dev_AA_00_00_00_00_03 > "$TREE_FILE"
printf '%s\n' /org/bluez/hci0/dev_AA_00_00_00_00_01 /org/bluez/hci1/dev_AA_00_00_00_00_02 > "$PAIRED_OBJECTS"
busctl_stub() {
    stub busctl "case \$1 in
    tree) ${1:-cat \"\$TREE_FILE\"} ;;
    get-property) ${2:-grep -qx \"\$3\" \"\$PAIRED_OBJECTS\" && echo 'b true' || echo 'b false'} ;;
    call) ${3:-:} ;;
esac"
}
busctl_stub

export LOG="$TMP/calls.log"
failed=0
check() {
    local name=$1 adapter=$2 mac=$3 path out expected_out expected_log
    path="/org/bluez/$adapter/dev_${mac//:/_}"
    : > "$LOG"
    out=$(PATH="$BIN" "$BASH" "$SCRIPT" 2>&1)
    expected_out="Removing previously paired Bluetooth devices: $mac
Ready for you to connect:
1. Open Bluetooth settings on your mobile device
2. Connect to wlanpi-test in 30 seconds from now"
    expected_log="bt-adapter -a $adapter -i
busctl tree --list org.bluez
$(grep "^/org/bluez/$adapter/dev_[^/]*$" "$TREE_FILE" | sed 's/^/busctl get-property org.bluez /; s/$/ org.bluez.Device1 Paired/' |
        sed "\#$path #a busctl call org.bluez /org/bluez/$adapter org.bluez.Adapter1 RemoveDevice o $path")
systemctl start bt-timedpair"
    if [ "$out" = "$expected_out" ] && [ "$(cat "$LOG")" = "$expected_log" ]; then
        echo "PASS: $name"
    else
        echo "FAIL: $name"
        printf -- '--- output\n%s\n--- calls\n%s\n--- expected calls\n%s\n' "$out" "$(cat "$LOG")" "$expected_log"
        failed=1
    fi
}

adapter_stub() {
    printf '#!/bin/sh\n%s\n' "$1" > "$BIN/wlanpi-bt-adapter"
    chmod +x "$BIN/wlanpi-bt-adapter"
}

adapter_stub 'echo hci1'
check "wlanpi-bt-adapter picks hci1" hci1 AA:00:00:00:00:02

adapter_stub 'exit 1'
check "no adapter from wlanpi-bt-adapter falls back to hci0" hci0 AA:00:00:00:00:01

rm "$BIN/wlanpi-bt-adapter"
check "missing wlanpi-bt-adapter falls back to hci0" hci0 AA:00:00:00:00:01

# A failed lookup or removal must stop before the pairing window opens, and a
# failed window must not report ready.
check_fails() {
    local name=$1 error=$2 window=${3:-0} out rc
    : > "$LOG"
    out=$(PATH="$BIN" "$BASH" "$SCRIPT" 2>&1)
    rc=$?
    if [ "$rc" != 0 ] && [[ $out == *"Error: $error"* ]] && [[ $out != *Ready* ]] &&
        [ "$(grep -c '^systemctl' "$LOG")" = "$window" ]; then
        echo "PASS: $name"
    else
        echo "FAIL: $name (rc=$rc)"
        printf -- '--- output\n%s\n--- calls\n%s\n' "$out" "$(cat "$LOG")"
        failed=1
    fi
}

busctl_stub 'exit 1'
check_fails "busctl tree failure stops" "could not list Bluetooth devices"
busctl_stub "" 'exit 1'
check_fails "unreadable device stops" "could not read /org/bluez/hci0/dev_AA_00_00_00_00_01"
busctl_stub "[ -e \"\$TREE_FILE.once\" ] && exit 1; : > \"\$TREE_FILE.once\"; cat \"\$TREE_FILE\"" 'exit 1'
check_fails "unreadable device stops when BlueZ can't be listed again" "could not read /org/bluez/hci0/dev_AA_00_00_00_00_01"
busctl_stub "" "" 'exit 1'
check_fails "removal failure stops" "could not remove AA:00:00:00:00:01"
busctl_stub
stub systemctl 'exit 1'
check_fails "bt-timedpair start failure is reported" "could not make Bluetooth discoverable" 1
stub systemctl

# A device BlueZ drops between the listing and the read is skipped.
DROPPED=/org/bluez/hci0/dev_AA_00_00_00_00_09
busctl_stub "[ -e \"\$TREE_FILE.listed\" ] || { : > \"\$TREE_FILE.listed\"; echo $DROPPED; }; cat \"\$TREE_FILE\"" \
    "[ \"\$3\" = $DROPPED ] && exit 1; grep -qx \"\$3\" \"\$PAIRED_OBJECTS\" && echo 'b true' || echo 'b false'"
: > "$LOG"
out=$(PATH="$BIN" "$BASH" "$SCRIPT" 2>&1)
rc=$?
if [ "$rc" = 0 ] && [[ $out == *"devices: AA:00:00:00:00:01"*Ready* ]] &&
    [ "$(grep -c '^busctl tree' "$LOG")" = 2 ] && grep -q '^systemctl start bt-timedpair$' "$LOG"; then
    echo "PASS: device dropped since the listing is skipped"
else
    echo "FAIL: device dropped since the listing is skipped (rc=$rc)"
    printf -- '--- output\n%s\n--- calls\n%s\n' "$out" "$(cat "$LOG")"
    failed=1
fi

exit "$failed"
