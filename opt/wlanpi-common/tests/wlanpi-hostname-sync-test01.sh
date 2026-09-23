#!/bin/bash
# Offline test for sync_hosts in wlanpi-hostname.sh; no root or device needed.
set -eu

SCRIPT="$(dirname "$0")/../wlanpi-hostname.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
sed -n '/^hosts_maps() {/,/^}/p; /^sync_hosts() {/,/^}/p' "$SCRIPT" > "$TMP/function.sh"
# shellcheck source=/dev/null
source "$TMP/function.sh"
debugger() { :; }
err_report() { echo "$1"; }
export SCRIPT_NAME=sync-test
HOSTS_FILE="$TMP/hosts"
failures=0

# run_case NAME OLD NEW INPUT EXPECTED (INPUT/EXPECTED use printf %b escapes)
run_case() {
    printf '%b' "$4" > "$HOSTS_FILE"
    (sync_hosts "$2" "$3") > "$TMP/out" 2>&1 || true
    if [ "$(cat "$HOSTS_FILE")" == "$(printf '%b' "$5")" ]; then
        echo "ok   $1"
    else
        echo "FAIL $1"; echo "  got: $(cat "$HOSTS_FILE")"; cat "$TMP/out"
        failures=$((failures + 1))
    fi
}

base='127.0.0.1\tlocalhost\n::1\t\tlocalhost ip6-localhost\n'
local_line='127.0.0.1 wlanpi.local\n'

run_case "repair stale line (interrupted rename)" wlanpi-087 wlanpi-087 \
    "${base}\n127.0.1.1\t\twlanpi\n${local_line}" "${base}\n127.0.1.1\t\twlanpi-087\n${local_line}"
run_case "rename default" wlanpi wlanpi-087 \
    "${base}127.0.1.1\t\twlanpi\n${local_line}" "${base}127.0.1.1\t\twlanpi-087\n${local_line}"
run_case "no change when correct" wlanpi-087 wlanpi-087 \
    "127.0.1.1\twlanpi-087\n" "127.0.1.1\twlanpi-087"
run_case "append when missing" wlanpi foo "${base}" "${base}127.0.1.1\t\tfoo"
run_case "fqdn and alias renamed" pi lab1 \
    "127.0.1.1 pi.example.org pi\n" "127.0.1.1 lab1.example.org lab1"
run_case "prefix is not a match" wlanpi wlanpi-087 \
    "127.0.1.1 wlanpi-3e4 wlanpi\n" "127.0.1.1 wlanpi-3e4 wlanpi-087"
run_case "repeated old name" old new "127.0.1.1 old old\n" "127.0.1.1 new new"
run_case "stale line keeps aliases and comment" wlanpi-087 wlanpi-087 \
    "127.0.1.1 appliance alias # local\n" "127.0.1.1 wlanpi-087 alias # local"
run_case "name in comment does not count" wlanpi-087 wlanpi-087 \
    "127.0.1.1 wlanpi # was wlanpi-087\n" "127.0.1.1 wlanpi-087 # was wlanpi-087"
run_case "fqdn of new name gets short name" wlanpi-087 wlanpi-087 \
    "127.0.1.1 wlanpi-087.example\n" "127.0.1.1 wlanpi-087.example wlanpi-087"
run_case "second 127.0.1.1 line already correct" old new \
    "127.0.1.1 stale\n127.0.1.1 new\n" "127.0.1.1 stale\n127.0.1.1 new"
run_case "only the first stale line is rewritten" a b \
    "127.0.1.1 x\n127.0.1.1 y\n" "127.0.1.1 b\n127.0.1.1 y"
run_case "other addresses untouched" wlanpi keith \
    "127.0.0.1 wlanpi\n127.0.1.1 wlanpi\n" "127.0.0.1 wlanpi\n127.0.1.1 keith"
run_case "bare 127.0.1.1 line" old new "127.0.1.1\n" "127.0.1.1\t\tnew"

# A no-change run must not replace the file.
printf '127.0.1.1\tfoo\n' > "$HOSTS_FILE"
before=$(stat -c '%i %y %z' "$HOSTS_FILE")
sync_hosts foo foo
if [ "$before" == "$(stat -c '%i %y %z' "$HOSTS_FILE")" ]; then
    echo "ok   no-change run leaves the file alone"
else
    echo "FAIL no-change run replaced the file"; failures=$((failures + 1))
fi

# An edit keeps the file mode and leaves no temporary files behind.
chmod 644 "$HOSTS_FILE"
sync_hosts foo bar
if [ "$(stat -c %a "$HOSTS_FILE")" == 644 ] && [ "$(find "$TMP" -name 'hosts.*' | wc -l)" -eq 0 ]; then
    echo "ok   edit keeps mode and cleans up"
else
    echo "FAIL edit changed mode or left a temporary file"; failures=$((failures + 1))
fi

echo "failures: $failures"
exit "$failures"
