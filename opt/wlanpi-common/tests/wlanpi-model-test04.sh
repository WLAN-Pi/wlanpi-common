#!/bin/bash

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

assert_contains(){
    local needle=$1
    local haystack=$2
    local name=$3
    if printf '%s\n' "$haystack" | grep -q -F "$needle"; then
        echo "PASS: $name"
        ((tests_passed++))
    else
        echo "FAIL: $name (expected to find '$needle' in '$haystack')"
        ((tests_failed++))
    fi
}

assert_not_contains(){
    local needle=$1
    local haystack=$2
    local name=$3
    if printf '%s\n' "$haystack" | grep -q -F "$needle"; then
        echo "FAIL: $name (did not expect '$needle' in '$haystack')"
        ((tests_failed++))
    else
        echo "PASS: $name"
        ((tests_passed++))
    fi
}

printf 'Model\t\t: Raspberry Pi Compute Module 4 Rev 1.1\n' > "$TMPROOT/cpuinfo-cm4"
printf 'Model\t\t: Raspberry Pi 4 Model B Rev 1.4\n' > "$TMPROOT/cpuinfo-r4"
mkdir -p "$TMPROOT/dt/spi@7e204000/spidev@1"
printf 'spidev\0' > "$TMPROOT/dt/spi@7e204000/spidev@1/compatible"
printf '14,1,0\n' > "$TMPROOT/go-serial"
printf '1\n' > "$TMPROOT/pro-battery"

NO_OVERLAY="$TMPROOT/dt/spi@*/spidev@*/compatible"
NONE="$TMPROOT/none"
SILENT=9

mkdir "$TMPROOT/bin"
printf '#!/bin/sh\nexit 1\n' > "$TMPROOT/bin/lsusb"
printf '#!/bin/sh\ncat "%s/lspci.out" 2>/dev/null\n' "$TMPROOT" > "$TMPROOT/bin/lspci"
printf '#!/bin/sh\n[ -e "%s" ] && echo "50: 50 -- -- --"\nexit 0\n' "$TMPROOT/eeprom" > "$TMPROOT/bin/i2cdetect"
cat > "$TMPROOT/bin/timeout" <<TIMEOUT
#!/bin/sh
echo "\$*" >> "$TMPROOT/timeout.log"
case "\$*" in
    *"-E ^14,"*) [ "\$(grep -c -- '-E ^14,' "$TMPROOT/timeout.log")" -le "\${SERIAL_MISSES:-0}" ] && exit 124 ;;
esac
exec $(command -v timeout) "\$@"
TIMEOUT
chmod +x "$TMPROOT/bin/"*

serial_reads(){
    grep -c -- '-E ^14,' "$TMPROOT/timeout.log"
}

run_model(){
    : > "$TMPROOT/timeout.log"
    rm -f "$TMPROOT/eeprom" "$TMPROOT/platform-cache" "$TMPROOT/stderr"
    [ "${EEPROM:-0}" = 1 ] && touch "$TMPROOT/eeprom"
    [ -n "${CACHE:-}" ] && printf '%s\n' "$CACHE" > "$TMPROOT/platform-cache"
    if [ "${FULL:-0}" = 1 ]; then
        set --
    else
        set -- -b
    fi
    PATH="$TMPROOT/bin:$PATH" CPUINFO="${CPUINFO:-$TMPROOT/cpuinfo-cm4}" \
        PRO_BATTERY_PRESENT="${PRO:-$NONE}" GO_SERIAL="$TMPROOT/go-serial" \
        GO_DEVICE_INFO="${INFO:-$NONE}" MAX3421_COMPATIBLE_GLOB="${OVERLAY:-$NO_OVERLAY}" \
        PLATFORM_CACHE="$TMPROOT/platform-cache" PCI_DEVICES_DIR="${PCI_DEVICES_DIR:-$TMPROOT/pci}" \
        SERIAL_MISSES="${SERIAL_MISSES:-0}" \
        "$SCRIPT_NAME" "$@" 2>"$TMPROOT/stderr"
}


MODEL=$(SERIAL_MISSES=$SILENT INFO="$NONE" OVERLAY="$NO_OVERLAY" PRO="$NONE" CACHE="" run_model)
assert_eq "M4" "$MODEL" "first CM4 detection with no Go signals reports M4"
assert_eq "WLAN Pi M4" "$(cat "$TMPROOT/platform-cache")" "first detection writes the platform cache"
assert_eq "1" "$(serial_reads)" "first M4 detection reads the serial port once"

MODEL=$(SERIAL_MISSES=$SILENT CACHE="WLAN Pi Go" INFO="$NONE" OVERLAY="$NO_OVERLAY" PRO="$NONE" run_model)
assert_eq "Go" "$MODEL" "Go cache reports Go and skips detection"
assert_eq "0" "$(serial_reads)" "Go cache skips the serial read"
assert_eq "" "$(cat "$TMPROOT/stderr")" "Go cache does not warn"
assert_eq "WLAN Pi Go" "$(cat "$TMPROOT/platform-cache")" "Go cache is left unchanged"

MODEL=$(SERIAL_MISSES=$SILENT CACHE="WLAN Pi Pro" PRO="$NONE" INFO="$NONE" OVERLAY="$NO_OVERLAY" run_model)
assert_eq "Pro" "$MODEL" "Pro cache is trusted when the battery is absent"
assert_eq "0" "$(serial_reads)" "Pro cache skips the serial read"
assert_eq "" "$(cat "$TMPROOT/stderr")" "Pro cache does not warn"

MODEL=$(SERIAL_MISSES=$SILENT CACHE="WLAN Pi M4" PRO="$TMPROOT/pro-battery" INFO="$NONE" OVERLAY="$NO_OVERLAY" run_model)
assert_eq "M4" "$MODEL" "M4 cache is trusted when a Pro battery is present"
assert_eq "" "$(cat "$TMPROOT/stderr")" "M4 cache does not warn"

MODEL=$(SERIAL_MISSES=$SILENT CACHE="WLAN Pi R4" INFO="$NONE" OVERLAY="$NO_OVERLAY" PRO="$NONE" run_model)
assert_eq "R4" "$MODEL" "R4 cache on a CM4 is trusted without re-detection"
assert_eq "0" "$(serial_reads)" "R4 cache on a CM4 skips detection"
assert_eq "WLAN Pi R4" "$(cat "$TMPROOT/platform-cache")" "trusted R4 cache is not overwritten"

MODEL=$(SERIAL_MISSES=$SILENT CACHE="WLAN Pi M4" INFO="$NONE" OVERLAY="$NO_OVERLAY" PRO="$NONE" EEPROM=1 run_model)
assert_eq "M4" "$MODEL" "M4 cache is used even when an M4+ EEPROM is present"
assert_eq "0" "$(serial_reads)" "M4 cache skips EEPROM and serial probes"

MODEL=$(SERIAL_MISSES=$SILENT CACHE="not-a-model" INFO="$NONE" OVERLAY="$NO_OVERLAY" PRO="$NONE" run_model)
assert_eq "M4" "$MODEL" "unrecognized cache content is ignored and detection runs"
assert_eq "1" "$(serial_reads)" "unrecognized cache does not skip detection"
assert_eq "WLAN Pi M4" "$(cat "$TMPROOT/platform-cache")" "detection overwrites unrecognized cache content"

MODEL=$(CPUINFO="$TMPROOT/cpuinfo-r4" CACHE="" INFO="$NONE" OVERLAY="$NO_OVERLAY" PRO="$NONE" run_model)
assert_eq "R4" "$MODEL" "Pi 4 first detection reports R4"
assert_eq "WLAN Pi R4" "$(cat "$TMPROOT/platform-cache")" "Pi 4 first detection writes the platform cache"

MODEL=$(CPUINFO="$TMPROOT/cpuinfo-r4" CACHE="WLAN Pi R4" INFO="$NONE" OVERLAY="$NO_OVERLAY" PRO="$NONE" run_model)
assert_eq "R4" "$MODEL" "R4 cache on a Pi 4 reports R4"

BE200='01:00.0 Network controller [0280]: Intel Corporation Wi-Fi 7(R) BE200 320MHz [8086:272b] (rev 1a)'
BE200_NAME='Intel Corporation Wi-Fi 7(R) BE200 320MHz [8086:272b] (rev 1a)'
mkdir -p "$TMPROOT/pci/0000:01:00.0"
printf '%s\n' "$BE200" > "$TMPROOT/lspci.out"

OUT=$(FULL=1 CPUINFO="$TMPROOT/cpuinfo-r4" CACHE="WLAN Pi R4" INFO="$NONE" OVERLAY="$NO_OVERLAY" PRO="$NONE" run_model)
assert_contains "M.2 Wi-Fi adapter:    $BE200_NAME" "$OUT" \
    "a BE200 in lspci is listed as an M.2 adapter"
assert_contains "PCI enumerated:      yes" "$OUT" \
    "an enumerated BE200 with no driver reports PCI enumerated yes"
assert_contains "driver bound:        no" "$OUT" \
    "an enumerated BE200 with no driver reports driver bound no"
assert_not_contains "firmware loaded:" "$OUT" \
    "firmware loaded is not reported"
assert_contains "netdev present:      no" "$OUT" \
    "an enumerated BE200 with no netdev reports netdev present no"
assert_not_contains "No Wi-Fi adapter" "$OUT" \
    "an enumerated but uninstantiated card is not reported as no adapter"

mkdir -p "$TMPROOT/drivers/iwlwifi"
ln -sfn "$TMPROOT/drivers/iwlwifi" "$TMPROOT/pci/0000:01:00.0/driver"
OUT=$(FULL=1 CPUINFO="$TMPROOT/cpuinfo-r4" CACHE="WLAN Pi R4" INFO="$NONE" OVERLAY="$NO_OVERLAY" PRO="$NONE" run_model)
assert_contains "M.2 Wi-Fi adapter:    $BE200_NAME" "$OUT" \
    "a bound BE200 without a netdev keeps the adapter name line"
assert_contains "PCI enumerated:      yes" "$OUT" \
    "a bound BE200 without a netdev reports PCI enumerated yes"
assert_contains "driver bound:        yes (iwlwifi)" "$OUT" \
    "a bound BE200 without a netdev reports the bound driver"
assert_not_contains "firmware loaded:" "$OUT" \
    "a bound BE200 without a netdev does not report firmware loaded"
assert_contains "netdev present:      no" "$OUT" \
    "a bound BE200 without a netdev reports netdev present no"
assert_not_contains "enumerated, not instantiated" "$OUT" \
    "the old single-label wording is not used"

mkdir -p "$TMPROOT/pci/0000:01:00.0/net/wlan0"
OUT=$(FULL=1 CPUINFO="$TMPROOT/cpuinfo-r4" CACHE="WLAN Pi R4" INFO="$NONE" OVERLAY="$NO_OVERLAY" PRO="$NONE" run_model)
assert_contains "M.2 Wi-Fi adapter:    $BE200_NAME" "$OUT" \
    "a BE200 with a netdev is reported as an M.2 adapter"
assert_not_contains "PCI enumerated:" "$OUT" \
    "an instantiated BE200 does not include stage lines"
assert_not_contains "firmware loaded:" "$OUT" \
    "an instantiated BE200 does not report firmware"
assert_not_contains "netdev present:" "$OUT" \
    "an instantiated BE200 does not report netdev stage"
assert_not_contains "not instantiated" "$OUT" \
    "an instantiated BE200 is not labelled as uninstantiated"

: > "$TMPROOT/lspci.out"
rm -rf "$TMPROOT/pci"
mkdir -p "$TMPROOT/pci"
OUT=$(FULL=1 CPUINFO="$TMPROOT/cpuinfo-r4" CACHE="WLAN Pi R4" INFO="$NONE" OVERLAY="$NO_OVERLAY" PRO="$NONE" run_model)
assert_contains "No Wi-Fi adapter" "$OUT" \
    "no PCI wireless devices reports no Wi-Fi adapter"

echo
echo "Tests passed: $tests_passed, failed: $tests_failed"
[ "$tests_failed" -eq 0 ]
