#!/bin/sh
# postinst undoes the old BE200 v92 firmware workaround (#129). Runs the
# postinst block against a scratch tree for each state a device can be in.
set -eu

block=$(sed -n '/^V92=/,/^$/p' debian/postinst)
[ -n "$block" ] || { echo "FAIL: v92 cleanup block not found in debian/postinst"; exit 1; }
! grep -q 'RUN+=.*92.ucode.disabled' debian/postinst
! grep -q 'ucode-92' debian/wlanpi-common.links

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
run() {
    rm -rf "${T:?}/lib" "${T:?}/etc"
    mkdir -p "$T/lib/firmware" "$T/etc/udev/rules.d"
    touch "$T/etc/udev/rules.d/50-iwlwifi-disable-v92.rules"
    # args: suffixes of the v92 files present; "plain" is the firmware file itself
    for f in "$@"; do
        [ "$f" = plain ] && f=""
        echo "$f" > "$T/lib/firmware/iwlwifi-gl-c0-fm-c0-92.ucode$f"
    done
    printf '%s\n' "$block" | sed "s#/lib/firmware#$T/lib/firmware#g; s#/etc/udev#$T/etc/udev#g" | sh
    [ ! -e "$T/etc/udev/rules.d/50-iwlwifi-disable-v92.rules" ]
    (cd "$T/lib/firmware" && ls | tr '\n' ' ')
}
fail=0
check() {
    got=$(run $2)
    if [ "$got" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got [$got] want [$3]"; fail=1; fi
}
V=iwlwifi-gl-c0-fm-c0-92.ucode
check "disabled by the old rule is restored" ".disabled" "$V "
check "disabled plus script backup: restored, backup dropped" ".disabled .original" "$V "
check "reinstalled by firmware package: stale copies dropped" "plain .disabled .original" "$V "
check "never disabled: untouched" "plain" "$V "
check "no v92 at all (non-BE200 firmware set): nothing created" "" ""
exit $fail
