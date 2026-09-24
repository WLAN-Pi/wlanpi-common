#!/bin/bash
# Behaviour test for configure_pcie_32bit_dma in wlanpi-config-at-startup.sh.
#
#   pcie-32bit-dma-test01.sh [SCRIPT]
#
# Runs against any version of the script, so two versions can be compared:
#   git show 6e34cdf:opt/wlanpi-common/wlanpi-config-at-startup.sh > /tmp/old.sh
#   diff <(pcie-32bit-dma-test01.sh /tmp/old.sh) <(pcie-32bit-dma-test01.sh)
#
# Each case gives both detection methods the same hardware: a fake
# /sys/bus/pci/devices tree and a fake `lspci -nn` built from one device list.
# The function runs under `set -e`, as it does at boot. Cases tagged [changed]
# are where the sysfs version intentionally differs from the lspci one
# (1.1.59); run against that version, exactly those fail.
set -u

SCRIPT=${1:-"$(dirname "$0")/../wlanpi-config-at-startup.sh"}
TMP=$(mktemp -d) || exit 2
trap 'rm -rf "$TMP"' EXIT
sed -n '/^configure_pcie_32bit_dma()/,/^}/p' "$SCRIPT" > "$TMP/function.sh"
[ -s "$TMP/function.sh" ] || { echo "configure_pcie_32bit_dma not found in $SCRIPT" >&2; exit 2; }
mkdir -p "$TMP/bin"

# config.txt as shipped (WLAN Pi Pro image), with the [cm4] overlay line
# absent, active or commented.
config() {
    local overlay=""
    case $1 in
        on) overlay=$'# Allows PCIe adapters with 32-bit DMA masks to work\ndtoverlay=pcie-32bit-dma\n' ;;
        off) overlay=$'# Allows PCIe adapters with 32-bit DMA masks to work\n#dtoverlay=pcie-32bit-dma\n' ;;
    esac
    cat <<EOF
arm_64bit=1
dtparam=act_led_trigger=heartbeat

[pi4]
kernel=wlanpi-kernel8.img

[cm4]
${overlay}
otg_mode=0
kernel=wlanpi-kernel8.img
dtoverlay=dwc2,dr_mode=otg
dtoverlay=disable-wifi
dtoverlay=disable-bt

[pi5]
kernel=wlanpi-kernel8.img

[cm5]
dtoverlay=dwc2,dr_mode=host
kernel=wlanpi-kernel8.img

[all]
EOF
}

# Devices are "domain:bus:slot.fn=vendor:device/class[!missing]". "/class"
# may be left out (no class file, class 0000 in lspci), and "!vendor" or
# "!device" leaves that sysfs file out (a device vanishing mid-read); lspci,
# which reads config space, still lists it.
hardware() {
    local lspci=$1 entry slot ids vendor device class missing
    shift
    rm -rf "$TMP/pci"
    mkdir -p "$TMP/pci"
    : > "$TMP/lspci.out"
    for entry in "$@"; do
        missing=""
        case $entry in *!*) missing=${entry#*!}; entry=${entry%%!*} ;; esac
        slot=${entry%%=*}
        ids=${entry#*=}
        vendor=${ids%%:*}
        ids=${ids#*:}
        device=${ids%%/*}
        class=""
        [ "$ids" = "$device" ] || class=${ids#*/}
        mkdir -p "$TMP/pci/$slot"
        [ "$missing" = vendor ] || echo "0x$vendor" > "$TMP/pci/$slot/vendor"
        [ "$missing" = device ] || echo "0x$device" > "$TMP/pci/$slot/device"
        [ -z "$class" ] || echo "$class" > "$TMP/pci/$slot/class"
        c=${class:-0x000000}
        echo "${slot#0000:} Device class [${c:2:4}]: Vendor Device [$vendor:$device]" >> "$TMP/lspci.out"
    done
    if [ "$lspci" = yes ]; then
        printf '#!/bin/sh\ncat "%s"\n' "$TMP/lspci.out" > "$TMP/bin/lspci"
    else
        printf '#!/bin/sh\necho "lspci: command not found" >&2\nexit 127\n' > "$TMP/bin/lspci"
    fi
    chmod +x "$TMP/bin/lspci"
}

# Overlay state inside [cm4]: on, off, absent, or dup (more than one active).
cm4() { awk '/^\[/{s=($0=="[cm4]")} s' "$1"; }
state() {
    local active
    active=$(cm4 "$1" | grep -c '^[[:space:]]*dtoverlay=pcie-32bit-dma$')
    if [ "$active" -gt 1 ]; then echo dup
    elif [ "$active" -eq 1 ]; then echo on
    elif cm4 "$1" | grep -q '^[[:space:]]*#dtoverlay=pcie-32bit-dma$'; then echo off
    else echo absent
    fi
}

fails=0
# check NAME OVERLAY LSPCI WANT_REBOOT WANT_STATE DEVICE...
check() {
    local name=$1 overlay=$2 lspci=$3 want_reboot=$4 want_state=$5 got_reboot got_state rc note=""
    shift 5
    hardware "$lspci" "$@"
    config "$overlay" > "$TMP/config.txt"
    cp "$TMP/config.txt" "$TMP/before.txt"
    got_reboot=$(
        set -e
        PATH="$TMP/bin:$PATH"
        CONFIG_FILE="$TMP/config.txt"
        PCI_DEVICES_DIR="$TMP/pci"
        REQUIRES_REBOOT=0
        export CONFIG_FILE PCI_DEVICES_DIR REQUIRES_REBOOT
        debugger() { :; }
        log_reason() { return 1; } # logger can fail early in boot; must not abort
        # shellcheck source=/dev/null
        source "$TMP/function.sh"
        configure_pcie_32bit_dma
        echo "$REQUIRES_REBOOT"
    )
    # Not `) || ...`: bash ignores set -e inside a subshell that is part of a
    # || list, which would hide an abort.
    rc=$?
    [ "$rc" -eq 0 ] || got_reboot="aborted(rc=$rc)"
    got_state=$(state "$TMP/config.txt")
    # Nothing outside [cm4] may change; a no-op must leave the file untouched.
    if ! diff -q <(awk '/^\[/{s=($0=="[cm4]")} !s' "$TMP/before.txt") \
        <(awk '/^\[/{s=($0=="[cm4]")} !s' "$TMP/config.txt") >/dev/null; then
        note=" (changed outside [cm4])"
    elif [ "$got_reboot" = 0 ] && ! cmp -s "$TMP/before.txt" "$TMP/config.txt"; then
        note=" (file changed without a reboot)"
    fi
    if [ "$got_reboot" = "$want_reboot" ] && [ "$got_state" = "$want_state" ] && [ -z "$note" ]; then
        printf 'PASS  %-52s reboot=%s overlay=%s\n' "$name" "$got_reboot" "$got_state"
    else
        printf 'FAIL  %-52s reboot=%s overlay=%s%s, want reboot=%s overlay=%s\n' \
            "$name" "$got_reboot" "$got_state" "$note" "$want_reboot" "$want_state"
        fails=$((fails + 1))
    fi
}

root=0000:00:00.0=14e4:2711/0x060400
# Pro: PCIe switch plus the onboard VL805 USB controller, always present
pro="$root 0000:01:00.0=12d8:2404/0x060400 0000:02:01.0=12d8:2404/0x060400 0000:02:02.0=12d8:2404/0x060400 0000:02:03.0=12d8:2404/0x060400 0000:03:00.0=1106:3483/0x0c0330"
qca=17cb:1107/0x028000
mt7921e=14c3:0608/0x028000
be200=8086:272b/0x028000

# shellcheck disable=SC2086 # $pro is a device list
{
check "M4 WCN785x, overlay absent"                absent yes 1 on     $root 0000:01:00.0=$qca
check "M4 WCN785x, overlay on"                    on     yes 0 on     $root 0000:01:00.0=$qca
check "M4 WCN785x, overlay commented"             off    yes 1 on     $root 0000:01:00.0=$qca
check "M4 mt7921e, overlay absent"                absent yes 1 on     $root 0000:01:00.0=$mt7921e
check "M4+ BE200, overlay on"                     on     yes 1 off    $root 0000:01:00.0=$be200
check "M4+ BE200, overlay commented"              off    yes 0 off    $root 0000:01:00.0=$be200
check "M4+ BE200, overlay absent"                 absent yes 0 absent $root 0000:01:00.0=$be200
check "Pro 2x mt7921e, overlay commented"         off    yes 1 on     $pro 0000:04:00.0=$mt7921e 0000:05:00.0=$mt7921e
check "Pro 2x mt7921e, overlay on"                on     yes 0 on     $pro 0000:04:00.0=$mt7921e 0000:05:00.0=$mt7921e
check "Pro 2x BE200, overlay on"                  on     yes 1 off    $pro 0000:04:00.0=$be200 0000:05:00.0=$be200
check "Pro BE200 + mt7921e, overlay on"           on     yes 0 on     $pro 0000:04:00.0=$be200 0000:05:00.0=$mt7921e
check "MT7922 (14c3:0616), overlay absent"        absent yes 1 on     $root 0000:01:00.0=14c3:0616/0x028000
check "MT7925e (14c3:7925), overlay absent"       absent yes 1 on     $root 0000:01:00.0=14c3:7925/0x028000
check "listed ID with class 0x0200, absent"       absent yes 1 on     $root 0000:01:00.0=14c3:0616/0x020000
check "unlisted NIC (0x0200), overlay on"         on     yes 1 off    $root 0000:01:00.0=10ec:8125/0x020000
check "NVMe (0x0108), overlay on"                 on     yes 1 off    $root 0000:01:00.0=144d:a808/0x010802
check "listed ID without class file, absent"      absent yes 1 on     $root 0000:01:00.0=17cb:1107
check "unlisted ID without class file, on"        on     yes 1 off    $root 0000:01:00.0=10ec:8125
check "M.2 empty or link down, overlay on [changed]" on  yes 0 on     $root
check "M.2 empty or link down, overlay commented" off    yes 0 off    $root
check "M.2 empty or link down, overlay absent"    absent yes 0 absent $root
check "Pro, no radio cards, overlay on [changed]" on     yes 0 on     $pro
check "no lspci, M4 WCN785x, overlay on [changed]" on    no  0 on     $root 0000:01:00.0=$qca
check "no lspci, M4 WCN785x, absent [changed]"    absent no  1 on     $root 0000:01:00.0=$qca
check "no lspci, M4+ BE200, overlay on"           on     no  1 off    $root 0000:01:00.0=$be200
check "PCIe USB card in M4 (0x0c03), overlay on"  on     yes 1 off    $root 0000:01:00.0=1912:0014/0x0c0330
check "Pro BE200 x2 + onboard VL805 only, on"     on     yes 1 off    $pro 0000:04:00.0=$be200 0000:05:00.0=$be200
check "WCN785x vendor file unreadable, on"        on     yes 0 on     $root "0000:01:00.0=$qca!vendor"
check "WCN785x device file unreadable, on"        on     yes 0 on     $root "0000:01:00.0=$qca!device"
check "no PCI devices at all, overlay on [changed]" on   yes 0 on
}

[ "$fails" -eq 0 ] && echo "pcie-32bit-dma: all cases passed ($SCRIPT)" || echo "pcie-32bit-dma: $fails case(s) failed ($SCRIPT)"
[ "$fails" -eq 0 ]
