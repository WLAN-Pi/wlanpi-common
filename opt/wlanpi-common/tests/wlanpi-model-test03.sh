#!/bin/bash
# wlanpi-model-test03.sh (no arguments): tests wlanpi-model.sh CM4 detection of the Go, M4+, and M4

SCRIPT_NAME="$(dirname "$0")/../wlanpi-model.sh"

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

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

printf 'Model\t\t: Raspberry Pi Compute Module 4 Rev 1.1\n' > "$TMPROOT/cpuinfo"
mkdir -p "$TMPROOT/dt/spi@7e204000/max3421@0" "$TMPROOT/dt/spi@7e204000/spidev@1"
printf 'maxim,max3421\0' > "$TMPROOT/dt/spi@7e204000/max3421@0/compatible"
printf 'spidev\0' > "$TMPROOT/dt/spi@7e204000/spidev@1/compatible"
printf '14,1,0\n' > "$TMPROOT/go-serial"
printf 'Go\n' > "$TMPROOT/go-model"
printf '1\n' > "$TMPROOT/pro-battery"

WITH_OVERLAY="$TMPROOT/dt/spi@*/*/compatible"
NO_OVERLAY="$TMPROOT/dt/spi@*/spidev@*/compatible"
SILENT=9
NONE="$TMPROOT/none"

mkdir "$TMPROOT/bin"
printf '#!/bin/sh\nexit 1\n' > "$TMPROOT/bin/lsusb"
cp "$TMPROOT/bin/lsusb" "$TMPROOT/bin/lspci"
printf '#!/bin/sh\n[ -e "%s" ] && echo "50: 50 -- -- --"\nexit 0\n' "$TMPROOT/eeprom" > "$TMPROOT/bin/i2cdetect"
cat > "$TMPROOT/bin/timeout" <<EOF
#!/bin/sh
echo "\$*" >> "$TMPROOT/timeout.log"
case "\$*" in
    *"-E ^14,"*) [ "\$(grep -c -- '-E ^14,' "$TMPROOT/timeout.log")" -le "\${SERIAL_MISSES:-0}" ] && exit 124 ;;
esac
exec $(command -v timeout) "\$@"
EOF
chmod +x "$TMPROOT/bin/"*

detect(){
    : > "$TMPROOT/timeout.log"
    rm -f "$TMPROOT/eeprom"
    [ "${EEPROM:-0}" = 1 ] && touch "$TMPROOT/eeprom"
    MODEL=$(PATH="$TMPROOT/bin:$PATH" CPUINFO="$TMPROOT/cpuinfo" \
        PRO_BATTERY_PRESENT="${PRO:-$NONE}" GO_SERIAL="$TMPROOT/go-serial" GO_DEVICE_INFO="${INFO:?}" \
        MAX3421_COMPATIBLE_GLOB="${OVERLAY:?}" "$SCRIPT_NAME" -b 2>/dev/null)
}

serial_reads(){
    grep -c -- '-E ^14,' "$TMPROOT/timeout.log"
}

SERIAL_MISSES=$SILENT INFO="$TMPROOT/go-model" OVERLAY="$NO_OVERLAY" detect
assert_eq "Go" "$MODEL" "Go device-info reports Go when the serial port is silent"
assert_eq "0" "$(serial_reads)" "Go device-info skips the serial read"

INFO="$NONE" OVERLAY="$NO_OVERLAY" detect
assert_eq "Go" "$MODEL" "Go serial answer reports Go"

SERIAL_MISSES=2 INFO="$NONE" OVERLAY="$WITH_OVERLAY" detect
assert_eq "Go" "$MODEL" "Go overlay without device-info reports Go on the third serial read"
assert_eq "3" "$(serial_reads)" "Go overlay without device-info reads the serial port three times"

SERIAL_MISSES=$SILENT INFO="$NONE" OVERLAY="$WITH_OVERLAY" detect
assert_eq "M4" "$MODEL" "Go overlay with a silent serial port reports M4"
assert_eq "3" "$(serial_reads)" "Go overlay with a silent serial port stops after three reads"

SERIAL_MISSES=$SILENT INFO="$NONE" OVERLAY="$NO_OVERLAY" detect
assert_eq "M4" "$MODEL" "no Go signals report M4"
assert_eq "1" "$(serial_reads)" "M4 reads the serial port once"

INFO="$NONE" OVERLAY="$NO_OVERLAY" EEPROM=1 detect
assert_eq "M4+" "$MODEL" "M4+ EEPROM wins over a Go serial answer"
assert_eq "0" "$(serial_reads)" "M4+ EEPROM skips the serial read"

INFO="$TMPROOT/go-model" OVERLAY="$WITH_OVERLAY" EEPROM=1 detect
assert_eq "M4+" "$MODEL" "M4+ EEPROM wins over Go storage"

PRO="$TMPROOT/pro-battery" INFO="$TMPROOT/go-model" OVERLAY="$WITH_OVERLAY" EEPROM=1 detect
assert_eq "Pro" "$MODEL" "Pro battery wins over the M4+ EEPROM and Go signals"

echo
echo "Tests passed: $tests_passed, failed: $tests_failed"
[ "$tests_failed" -eq 0 ]
