#!/bin/bash
###########################################################
# Description:
#
#  Test suite for the LLDP/CDP runtime files. Plants symlinks at the former
#  predictable /tmp paths and verifies the scripts neither read, truncate, nor
#  overwrite the target, and that no script writes to /tmp at all.
#
#  The producer scripts (cdpneigh.sh, lldpneigh.sh) refuse to run unless they
#  are root, so only the cleanup scripts are executed here.
#
###########################################################

# MODULE/VERSION/COMMENTS are documentation.
# shellcheck disable=SC2034
MODULE=networkinfo
VERSION=1.0.0
COMMENTS="networkinfo runtime directory test suite"
DIR="$(dirname "$0")/../networkinfo"

TMPROOT="$(mktemp -d)"
RUNTIME_DIR="$TMPROOT/run"
VICTIM="$TMPROOT/victim"
FORMER_NAMES=(lldpneigh.txt cdpneigh.txt lldpneightcpdump.cap cdpneightcpdump.cap)
declare -A SAVED=()

restore(){
    local name
    for name in "${FORMER_NAMES[@]}"; do
        rm -f "/tmp/$name"
        if [ -n "${SAVED[$name]:-}" ]; then
            mv "${SAVED[$name]}" "/tmp/$name"
        fi
    done
    rm -rf "$TMPROOT"
}
trap restore EXIT

# initialize tests passed/failed counters
tests_passed=0
tests_failed=0

assert_eq(){
    local expected=$1
    local actual=$2
    local name=$3
    if [ "$expected" == "$actual" ]; then
        echo "PASS: $name"
        ((tests_passed++))
    else
        echo "FAIL: $name (expected '$expected', got '$actual')"
        ((tests_failed++))
    fi
}

assert_ok(){
    local rc=$1
    local name=$2
    if [ "$rc" -eq 0 ]; then
        echo "PASS: $name"
        ((tests_passed++))
    else
        echo "FAIL: $name"
        ((tests_failed++))
    fi
}

assert_file(){
    local path=$1
    local name=$2
    if [ -f "$path" ]; then
        echo "PASS: $name"
        ((tests_passed++))
    else
        echo "FAIL: $name"
        ((tests_failed++))
    fi
}

# --- the scripts must not write to /tmp at all ---
for script in cdpneigh.sh lldpneigh.sh cdpcleanup.sh lldpcleanup.sh; do
    ! grep -q "/tmp/" "$DIR/$script"
    assert_ok $? "$script does not write to /tmp"
done

# --- plant symlinks at the former predictable paths ---
mkdir -p "$RUNTIME_DIR"
echo "do not touch" > "$VICTIM"
for name in "${FORMER_NAMES[@]}"; do
    if [ -e "/tmp/$name" ] || [ -L "/tmp/$name" ]; then
        SAVED[$name]="$TMPROOT/saved.$name"
        mv "/tmp/$name" "${SAVED[$name]}"
    fi
    ln -s "$VICTIM" "/tmp/$name"
done

# --- run the cleanup scripts, where the root service used to truncate ---
RUNTIME_DIR="$RUNTIME_DIR" "$DIR/lldpcleanup.sh" > /dev/null 2>&1
assert_ok $? "lldpcleanup.sh runs with RUNTIME_DIR"
RUNTIME_DIR="$RUNTIME_DIR" "$DIR/cdpcleanup.sh" > /dev/null 2>&1
assert_ok $? "cdpcleanup.sh runs with RUNTIME_DIR"

# --- the planted targets must be untouched ---
assert_eq "do not touch" "$(cat "$VICTIM")" "planted symlink target is not truncated"

# --- and the output must have landed in the runtime directory ---
assert_file "$RUNTIME_DIR/lldpneigh.txt" "lldpneigh.txt written to RUNTIME_DIR"
assert_file "$RUNTIME_DIR/cdpneigh.txt" "cdpneigh.txt written to RUNTIME_DIR"

# --- the runtime directory is private ---
assert_eq "700" "$(stat -c '%a' "$RUNTIME_DIR")" "RUNTIME_DIR is 0700"
assert_eq "600" "$(stat -c '%a' "$RUNTIME_DIR/lldpneigh.txt")" "lldpneigh.txt is 0600"

echo
echo "Tests passed: $tests_passed, failed: $tests_failed"
[ "$tests_failed" -eq 0 ]
