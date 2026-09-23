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

ok()   { echo "ok   $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }

# run_case NAME OLD NEW INPUT EXPECTED: sync_hosts must exit 0 and leave
# exactly EXPECTED (INPUT/EXPECTED use printf %b escapes).
run_case() {
    printf '%b' "$4" > "$HOSTS_FILE"
    printf '%b' "$5" > "$TMP/expected"
    if (sync_hosts "$2" "$3") > "$TMP/out" 2>&1 && cmp -s "$HOSTS_FILE" "$TMP/expected"; then
        ok "$1"
    else
        fail "$1"; echo "  got: $(cat -A "$HOSTS_FILE")"; cat "$TMP/out"
    fi
}

base='127.0.0.1\tlocalhost\n::1\t\tlocalhost ip6-localhost\n'
local_line='127.0.0.1 wlanpi.local\n'

run_case "repair stale line (interrupted rename)" wlanpi-087 wlanpi-087 \
    "${base}\n127.0.1.1\t\twlanpi\n${local_line}" "${base}\n127.0.1.1\t\twlanpi-087\n${local_line}"
run_case "rename default" wlanpi wlanpi-087 \
    "${base}127.0.1.1\t\twlanpi\n${local_line}" "${base}127.0.1.1\t\twlanpi-087\n${local_line}"
run_case "no change when correct" wlanpi-087 wlanpi-087 \
    "127.0.1.1\twlanpi-087\n" "127.0.1.1\twlanpi-087\n"
run_case "no change when correct without final newline" wlanpi-087 wlanpi-087 \
    "127.0.1.1\twlanpi-087" "127.0.1.1\twlanpi-087"
run_case "append when missing" wlanpi foo "${base}" "${base}127.0.1.1\t\tfoo\n"
run_case "fqdn and alias renamed" pi lab1 \
    "127.0.1.1 pi.example.org pi\n" "127.0.1.1 lab1.example.org lab1\n"
run_case "prefix is not a match" wlanpi wlanpi-087 \
    "127.0.1.1 wlanpi-3e4 wlanpi\n" "127.0.1.1 wlanpi-3e4 wlanpi-087\n"
run_case "repeated old name" old new "127.0.1.1 old old\n" "127.0.1.1 new new\n"
run_case "stale line keeps aliases and comment" wlanpi-087 wlanpi-087 \
    "127.0.1.1 appliance alias # local\n" "127.0.1.1 wlanpi-087 alias # local\n"
run_case "name in comment does not count" wlanpi-087 wlanpi-087 \
    "127.0.1.1 wlanpi # was wlanpi-087\n" "127.0.1.1 wlanpi-087 # was wlanpi-087\n"
run_case "fqdn of new name gets short name" wlanpi-087 wlanpi-087 \
    "127.0.1.1 wlanpi-087.example\n" "127.0.1.1 wlanpi-087.example wlanpi-087\n"
run_case "second 127.0.1.1 line already correct" old new \
    "127.0.1.1 stale\n127.0.1.1 new\n" "127.0.1.1 stale\n127.0.1.1 new\n"
run_case "only the first stale line is rewritten" a b \
    "127.0.1.1 x\n127.0.1.1 y\n" "127.0.1.1 b\n127.0.1.1 y\n"
run_case "other addresses untouched" wlanpi keith \
    "127.0.0.1 wlanpi\n127.0.1.1 wlanpi\n" "127.0.0.1 wlanpi\n127.0.1.1 keith\n"
run_case "bare 127.0.1.1 line" old new "127.0.1.1\n" "127.0.1.1\t\tnew\n"
run_case "numeric names compare as strings" 1 01 "127.0.1.1 alias 1\n" "127.0.1.1 alias 01\n"

# A no-change run must not replace the file.
printf '127.0.1.1\tfoo\n' > "$HOSTS_FILE"
before=$(stat -c '%i %y %z' "$HOSTS_FILE")
if sync_hosts foo foo && [ "$before" == "$(stat -c '%i %y %z' "$HOSTS_FILE")" ]; then
    ok "no-change run leaves the file alone"
else
    fail "no-change run replaced the file"
fi

# An edit keeps mode and group and leaves no temporary files behind.
chmod 640 "$HOSTS_FILE"
group=$(id -G | tr ' ' '\n' | grep -vx "$(id -g)" | head -1 || true)
[ -z "$group" ] || chgrp "$group" "$HOSTS_FILE"
before=$(stat -c '%a %u %g' "$HOSTS_FILE")
if sync_hosts foo bar && [ "$before" == "$(stat -c '%a %u %g' "$HOSTS_FILE")" ] &&
   [ -z "$(find "$TMP" -name 'hosts.*')" ]; then
    ok "edit keeps mode and ownership ($before) and cleans up"
else
    fail "edit changed mode/ownership or left a temporary file"
fi

# A failed or wrong rewrite must fail and leave the file as it was.
# fail_case NAME AWK_BODY: AWK_BODY replaces the rewriting awk (OLD is only set for it).
fail_case() {
    printf '127.0.1.1\tfoo\n' > "$HOSTS_FILE"
    cp "$HOSTS_FILE" "$TMP/expected"
    eval "awk() { if [ -n \"\${OLD:-}\" ]; then $2; else command awk \"\$@\"; fi; }"
    if ! (sync_hosts foo bar) > "$TMP/out" 2>&1 && cmp -s "$HOSTS_FILE" "$TMP/expected"; then
        ok "$1"
    else
        fail "$1"
    fi
    unset -f awk
}
fail_case "failed rewrite leaves the file unchanged" "return 1"
fail_case "truncated rewrite is rejected before replacing" "echo 127.0.0.1 localhost"

echo "failures: $failures"
exit "$failures"
