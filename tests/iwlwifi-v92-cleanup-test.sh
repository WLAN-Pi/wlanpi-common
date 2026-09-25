#!/bin/sh
# postinst undoes the old BE200 v92 firmware workaround (#129). Runs the
# marked postinst block against a scratch tree for each state a device can be in.
set -eu

[ "$(grep -c '^# BEGIN iwlwifi v92 cleanup$' debian/postinst)" = 1 ] &&
    [ "$(grep -c '^# END iwlwifi v92 cleanup$' debian/postinst)" = 1 ] ||
    { echo "FAIL: v92 cleanup markers missing or repeated in debian/postinst"; exit 1; }
block=$(sed -n '/^# BEGIN iwlwifi v92 cleanup$/,/^# END iwlwifi v92 cleanup$/p' debian/postinst)
! grep -q 'RUN+=.*92.ucode.disabled' debian/postinst
! grep -q 'ucode-92' debian/wlanpi-common.links

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
V=iwlwifi-gl-c0-fm-c0-92.ucode
# run SUFFIX...: create each v92 file (suffix "plain" is the firmware itself,
# its content is the suffix name), run the block, print "name=content ...".
run() {
    rm -rf "${T:?}/lib" "${T:?}/etc"
    mkdir -p "$T/lib/firmware" "$T/etc/udev/rules.d"
    touch "$T/etc/udev/rules.d/50-iwlwifi-disable-v92.rules"
    for f in "$@"; do
        s=$f; [ "$f" = plain ] && s=""
        echo "$f" > "$T/lib/firmware/$V$s"
    done
    printf '%s\n' "$block" | sed "s#/lib/firmware#$T/lib/firmware#g; s#/etc/udev#$T/etc/udev#g" | sh
    if [ -e "$T/etc/udev/rules.d/50-iwlwifi-disable-v92.rules" ]; then
        echo "udev-rule-left"
        return
    fi
    for f in "$T/lib/firmware"/*; do
        [ -e "$f" ] || continue
        printf '%s=%s ' "${f##*/}" "$(cat "$f")"
    done
}
fail=0
check() {
    name=$1 want=$2; shift 2
    got=$(run "$@")
    if [ "$got" = "$want" ]; then echo "PASS $name"; else echo "FAIL $name: got [$got] want [$want]"; fail=1; fi
}
check "disabled by the old rule is restored" "$V=.disabled " .disabled
check "disabled plus script backup: restored, backup dropped" "$V=.disabled " .disabled .original
check "reinstalled by firmware package: kept, stale copies dropped" "$V=plain " plain .disabled .original
check "never disabled: untouched" "$V=plain " plain
check "only the script backup: left alone" "$V.original=.original " .original
check "no v92 at all: nothing created" ""
exit $fail
