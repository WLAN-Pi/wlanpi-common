#!/bin/sh
set -eu

SCRIPT=opt/wlanpi-common/wlanpi-power.sh
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cat >"$TMP/pinctrl" <<'EOF'
#!/bin/sh
case "$*" in
    "set 7,9 ip pu") exit "${SET_RC:-0}" ;;
    "lev 9") [ "${POE:-1}" = fail ] && exit 1; printf '%s\n' "${POE:-1}" ;;
    "lev 7") [ "${USB:-1}" = fail ] && exit 1; printf '%s\n' "${USB:-1}" ;;
    *) exit 2 ;;
esac
EOF
chmod +x "$TMP/pinctrl"

run() {
    expected=$1
    shift
    output=$(env PINCTRL="$TMP/pinctrl" "$@" sh "$SCRIPT")
    [ "$output" = "$expected" ]
}

run "Powered by PoE" env POE=0 USB=0
run "Powered by USB" env POE=1 USB=0
run "Powered by battery" env POE=1 USB=1

! env PINCTRL="$TMP/pinctrl" SET_RC=1 sh "$SCRIPT" >/dev/null 2>&1
! env PINCTRL="$TMP/pinctrl" POE=fail sh "$SCRIPT" >/dev/null 2>&1
! env PINCTRL="$TMP/pinctrl" POE=1 USB=fail sh "$SCRIPT" >/dev/null 2>&1
! env PINCTRL="$TMP/pinctrl" POE=2 USB=1 sh "$SCRIPT" >/dev/null 2>&1
