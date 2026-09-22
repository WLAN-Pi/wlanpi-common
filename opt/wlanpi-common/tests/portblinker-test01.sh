#!/bin/bash
###########################################################
# Description:
#
#  Test suite for portblinker.sh confirm(): the skip flag, non-interactive
#  callers, and the accept/decline paths on a terminal.
#
#  Uses script(1) to allocate a pty; the terminal cases are skipped when it is
#  not available.
#
###########################################################

# MODULE/VERSION/COMMENTS are documentation, and ASSUME_YES/INTERFACE are read
# by the extracted confirm() function, which shellcheck cannot see across files.
# shellcheck disable=SC2034
MODULE=portblinker.sh
VERSION=1.0.0
COMMENTS="portblinker.sh test suite to validate the confirmation prompt"
SCRIPT_NAME="$(dirname "$0")/../networkinfo/$MODULE"

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT
sed -n '/^confirm()/,/^}/p' "$SCRIPT_NAME" > "$TMPROOT/confirm.sh"

# Runs confirm() in a fresh shell with the given ASSUME_YES.
cat > "$TMPROOT/run.sh" <<EOF
#!/bin/bash
INTERFACE=eth0
ASSUME_YES="\$1"
# shellcheck source=/dev/null
. "$TMPROOT/confirm.sh"
confirm
EOF
chmod +x "$TMPROOT/run.sh"

# initialize tests passed/failed counters
tests_passed=0
tests_failed=0

assert_rc(){
    local expected=$1
    local actual=$2
    local name=$3
    if [ "$expected" == "$actual" ]; then
        echo "PASS: $name"
        ((tests_passed++))
    else
        echo "FAIL: $name (expected rc $expected, got $actual)"
        ((tests_failed++))
    fi
}

# --- no terminal: never prompt ---
"$TMPROOT/run.sh" no < /dev/null
assert_rc 0 $? "no terminal means no prompt"

# --- on a terminal ---
if command -v script &> /dev/null; then
    printf 'n\n' | script -qec "$TMPROOT/run.sh no" /dev/null > /dev/null 2>&1
    assert_rc 1 $? "declining aborts"

    printf 'y\n' | script -qec "$TMPROOT/run.sh no" /dev/null > /dev/null 2>&1
    assert_rc 0 $? "accepting proceeds"

    # declining with -y must not abort: the prompt is skipped
    printf 'n\n' | script -qec "$TMPROOT/run.sh yes" /dev/null > /dev/null 2>&1
    assert_rc 0 $? "-y skips the prompt on a terminal"
else
    echo "SKIP: script(1) not available, terminal cases not run"
fi

echo
echo "Tests passed: $tests_passed, failed: $tests_failed"
[ "$tests_failed" -eq 0 ]
