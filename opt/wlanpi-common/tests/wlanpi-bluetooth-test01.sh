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
for tool in awk cat grep jq; do
    ln -s "$(command -v "$tool")" "$BIN/$tool" || exit 2
done

stub() {
    printf '#!/bin/bash\necho "%s $*" >> "$LOG"\n%s\n' "$1" "${2:-}" > "$BIN/$1"
    chmod +x "$BIN/$1"
}
stub bt-adapter "printf '[hci9]\n  Name: x\n  Alias: wlanpi-test [rw]\n'"
stub busctl 'cat "$FIXTURE"'
stub bt-device 'echo Done'
stub systemctl

# GetManagedObjects as busctl --json=short prints it: a dongle on hci0 and the
# onboard adapter on hci1, each with a paired device, plus an unpaired device
# and a child object without Device1 on hci1.
export FIXTURE="$TMP/objects.json"
dev() {
    printf '"/org/bluez/%s/dev_%s":{"org.bluez.Device1":{"Address":{"type":"s","data":"%s"},"Paired":{"type":"b","data":%s},"Adapter":{"type":"o","data":"/org/bluez/%s"}}}' \
        "$1" "${2//:/_}" "$2" "$3" "$1"
}
printf '{"type":"a{oa{sa{sv}}}","data":[{"/org/bluez":{"org.bluez.AgentManager1":{}},"/org/bluez/hci0":{"org.bluez.Adapter1":{}},"/org/bluez/hci1":{"org.bluez.Adapter1":{}},%s,%s,%s,"/org/bluez/hci1/dev_AA_00_00_00_00_02/fd0":{"org.bluez.MediaTransport1":{}}}]}\n' \
    "$(dev hci0 AA:00:00:00:00:01 true)" \
    "$(dev hci1 AA:00:00:00:00:02 true)" \
    "$(dev hci1 AA:00:00:00:00:03 false)" > "$FIXTURE"

export LOG="$TMP/calls.log"
failed=0
check() {
    local name=$1 adapter=$2 mac=$3 out expected_out expected_log
    : > "$LOG"
    out=$(PATH="$BIN" "$BASH" "$SCRIPT" 2>&1)
    expected_out="Removing previously paired Bluetooth devices: $mac
Done
Ready for you to connect:
1. Open Bluetooth settings on your mobile device
2. Connect to wlanpi-test in 30 seconds from now"
    expected_log="bt-adapter -a $adapter -i
busctl --json=short call org.bluez / org.freedesktop.DBus.ObjectManager GetManagedObjects
bt-device -a $adapter -r $mac
systemctl start bt-timedpair"
    if [ "$out" = "$expected_out" ] && [ "$(cat "$LOG")" = "$expected_log" ]; then
        echo "PASS: $name"
    else
        echo "FAIL: $name"
        printf -- '--- output\n%s\n--- calls\n%s\n' "$out" "$(cat "$LOG")"
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

exit "$failed"
