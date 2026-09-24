#!/bin/bash
# Differential test for configure_pcie_32bit_dma: runs the candidate startup
# script next to the one that shipped on the last stable image and the one it
# replaces, on the same PCI bus and config.txt.
#
#   pcie-32bit-dma-parity-test01.sh           synthetic buses, every CM4 board
#   pcie-32bit-dma-parity-test01.sh --live    this device's bus, board and
#                                             config.txt (read-only, as root)
#
# References come from git. Outside a checkout (on a device), pass files:
#   SHIPPED=    wlanpi-common 1.1.40 (image v3.4.4, 30ed7ad). The M4 and M4+
#               branches each had an inline block; the Pro had none.
#   PREVIOUS=   wlanpi-common 1.1.59 (6e34cdf), configure_pcie_32bit_dma.
#   CANDIDATE=  defaults to ../wlanpi-config-at-startup.sh
#
# Each case checks:
#   I1  no card counted: the candidate leaves config.txt byte-identical and
#       requests no reboot
#   I2  the candidate gives the same result with and without lspci installed
#   I3  card present: the candidate is byte-identical to 1.1.59
#   I4  M4 or M4+, card present, not a QCA-only bus: the candidate matches
#       shipped 1.1.40 apart from the comment inserted with the overlay
# and attributes every difference from shipped to the change that made it.
# The references run with lspci installed, as on every image.
set -u
here=$(cd "$(dirname "$0")" && pwd)
CANDIDATE=${CANDIDATE:-$here/../wlanpi-config-at-startup.sh}
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
die() { echo "pcie-32bit-dma-parity: $*" >&2; exit 2; }

ref() { # ref FILE COMMIT OUT
    if [ -n "$1" ]; then
        cp "$1" "$3" || die "cannot read $1"
    else
        git -C "$here" show "$2:opt/wlanpi-common/wlanpi-config-at-startup.sh" > "$3" 2>/dev/null ||
            die "no git history for $2; pass SHIPPED= and PREVIOUS= files"
    fi
}
ref "${SHIPPED:-}" 30ed7ad "$T/shipped.sh"
ref "${PREVIOUS:-}" 6e34cdf "$T/previous.sh"
fn() { sed -n '/^configure_pcie_32bit_dma()/,/^}/p' "$1"; }
fn "$T/previous.sh" > "$T/previous.fn"
fn "$CANDIDATE" > "$T/candidate.fn"
# 1.1.40 block for one board, from its "Enable pcie-32bit-dma" comment to the
# "Disable RTC" step that follows it; only the hard-coded path is replaced.
block() {
    awk -v b="if [[ \"\$BOARD\" == \"$1\" ]]; then" '
        $0 == b { inb = 1; next }
        inb && /^fi$/ { exit }
        inb && /# Enable pcie-32bit-dma overlay for/ { p = 1 }
        inb && p && /# Disable RTC/ { exit }
        inb && p' "$T/shipped.sh" | sed 's#/boot/config.txt#"$CONFIG_FILE"#g'
}
# shellcheck disable=SC2016 # generated code, expanded when sourced
{
    echo 'configure_pcie_32bit_dma() {'
    echo 'case "$BOARD" in'
    echo '"Mcuzone M4")'; block "Mcuzone M4"; echo ';;'
    echo '"Mcuzone M4+")'; block "Mcuzone M4+"; echo ';;'
    echo 'esac'
    echo '}'
} > "$T/shipped.fn"
for f in shipped previous candidate; do
    grep -q 'dtoverlay=pcie-32bit-dma' "$T/$f.fn" || die "no pcie-32bit-dma logic in the $f script"
done
[ "$(grep -c 'lspci -nn' "$T/shipped.fn")" -eq 2 ] || die "expected an M4 and an M4+ block in the shipped script"

mkdir -p "$T/fake" "$T/none"
printf '#!/bin/sh\ncat "%s"\n' "$T/lspci.out" > "$T/fake/lspci"
printf '#!/bin/sh\necho "lspci: command not found" >&2\nexit 127\n' > "$T/none/lspci"
chmod +x "$T/fake/lspci" "$T/none/lspci"

# run FN OUT BIN: FN's configure_pcie_32bit_dma on a copy of start.txt, with
# BIN (if set) first in PATH; prints "exit-code reboot-flag"
run() {
    cp "$T/start.txt" "$T/$2"
    (
        set -e
        [ -z "$3" ] || PATH="$3:$PATH"
        CONFIG_FILE="$T/$2" PCI_DEVICES_DIR=$PCI REQUIRES_REBOOT=0
        export CONFIG_FILE PCI_DEVICES_DIR REQUIRES_REBOOT
        debugger() { :; }
        log_reason() { :; }
        # shellcheck source=/dev/null
        source "$T/$1.fn"
        configure_pcie_32bit_dma
        echo "$REQUIRES_REBOOT" > "$T/rb"
    )
    echo "$? $(cat "$T/rb" 2>/dev/null || echo -)"
    rm -f "$T/rb"
}
same() { [ "$1" = "$2" ] && cmp -s "$T/$3" "$T/$4"; }
norm() { grep -vxE '# Allows (MT7921K adapter to work with 64-bit kernel|PCIe adapters with 32-bit DMA masks to work)' "$T/$1"; }
# Overlay state inside [cm4]: on, off, absent, or dup (more than one active)
state() {
    local s active
    s=$(awk '/^\[/{s=($0=="[cm4]")} s' "$T/$1")
    active=$(grep -c '^[[:space:]]*dtoverlay=pcie-32bit-dma' <<< "$s")
    if [ "$active" -gt 1 ]; then echo dup
    elif [ "$active" -eq 1 ]; then echo on
    elif grep -q '^[[:space:]]*#dtoverlay=pcie-32bit-dma' <<< "$s"; then echo off
    else echo absent
    fi
}

LISTED="14c3:0608|14c3:0616|14c3:7925|17cb:1107"
# Hardware facts for DEVS ("slot=vendor:device/class", class "-" if missing),
# worked out independently of the scripts under test
facts() {
    local e id c
    match=0 card=0 qca=0 mtk=0
    for e in "${DEVS[@]}"; do
        id=${e#*=}; c=${id#*/}; id=${id%%/*}
        [[ $id =~ ^($LISTED)$ ]] && match=1
        [ "$id" = 17cb:1107 ] && qca=1
        [[ $id =~ ^14c3:(0608|0616|7925)$ ]] && mtk=1
        [[ $c == 0x0604* ]] && continue
        [ "$id" = 1106:3483 ] && [ "$BOARD" = "WLAN Pi Pro" ] && continue
        card=1
    done
}

n=0 fails=0 identical=0
declare -A why
# check LABEL: one case for BOARD, DEVS, PCI, LSPCI_BIN and start.txt
check() {
    local s p c c2 bad="" reason=""
    n=$((n + 1))
    s=$(run shipped out.s "$LSPCI_BIN")
    p=$(run previous out.p "$LSPCI_BIN")
    c=$(run candidate out.c "$LSPCI_BIN")
    c2=$(run candidate out.c2 "$T/none")
    facts
    same "$c" "$c2" out.c out.c2 || bad="$bad I2"
    if [ $card -eq 0 ] && [ $match -eq 0 ]; then
        { [ "$c" = "0 0" ] && cmp -s "$T/start.txt" "$T/out.c"; } || bad="$bad I1"
    else
        same "$c" "$p" out.c out.p || bad="$bad I3"
        if [ "$BOARD" != "WLAN Pi Pro" ] && ! { [ $qca -eq 1 ] && [ $mtk -eq 0 ]; }; then
            { [ "$c" = "$s" ] && cmp -s <(norm out.c) <(norm out.s); } || bad="$bad I4"
        fi
    fi
    if same "$c" "$s" out.c out.s; then
        identical=$((identical + 1))
    elif [ $card -eq 0 ] && [ $match -eq 0 ]; then reason="#118 no card: overlay left alone"
    elif [ "$BOARD" = "WLAN Pi Pro" ]; then reason="#105 Pro overlay now managed"
    elif [ $qca -eq 1 ] && [ $mtk -eq 0 ]; then reason="6151244/#85 QCA 17cb:1107 listed"
    elif [ "$c" = "$s" ] && cmp -s <(norm out.c) <(norm out.s); then reason="#105 inserted comment text"
    else bad="$bad unattributed"
    fi
    [ -z "$reason" ] || why[$reason]=$((${why[$reason]:-0} + 1))
    if [ -n "${LIVE:-}" ]; then
        printf '%-8s shipped: reboot=%s overlay=%-6s  1.1.59: reboot=%s overlay=%-6s  candidate: reboot=%s overlay=%-6s %s\n' \
            "$1" "${s#* }" "$(state out.s)" "${p#* }" "$(state out.p)" "${c#* }" "$(state out.c)" "${reason:+($reason)}"
    fi
    if [ -n "$bad" ]; then
        fails=$((fails + 1))
        [ $fails -le 20 ] && echo "FAIL$bad: board=$BOARD config=$1 bus=${DEVS[*]:-empty} shipped=[$s] 1.1.59=[$p] candidate=[$c] no-lspci=[$c2]"
    fi
}

if [ "${1:-}" = --live ]; then
    [ "$(id -u)" -eq 0 ] || die "--live needs root: wlanpi-model reads i2c to tell the M4+"
    LIVE=1 PCI=/sys/bus/pci/devices LSPCI_BIN=""
    BOARD=$(wlanpi-model | grep "Main board:" | cut -d ":" -f2 | xargs)
    DEVS=()
    for d in "$PCI"/*; do
        [ -r "$d/vendor" ] || continue
        c=$(cat "$d/class" 2>/dev/null) || c=-
        DEVS+=("${d##*/}=$(sed 's/^0x//' "$d/vendor"):$(sed 's/^0x//' "$d/device")/$c")
    done
    cfg=${CONFIG_FILE:-/boot/firmware/config.txt}
    echo "board: $BOARD | bus: ${DEVS[*]:-empty} | config: $cfg"
    case "$BOARD" in
        "Mcuzone M4" | "Mcuzone M4+" | "WLAN Pi Pro") ;;
        *) echo "board $BOARD does not run configure_pcie_32bit_dma; nothing to compare"; exit 0 ;;
    esac
    ins='# Allows PCIe adapters with 32-bit DMA masks to work\n'
    for CV in as-is absent on off; do
        case $CV in
            as-is) cp "$cfg" "$T/start.txt" ;;
            absent) grep -v 'pcie-32bit-dma\|Allows .* to work' "$cfg" > "$T/start.txt" ;;
            on) grep -v 'pcie-32bit-dma\|Allows .* to work' "$cfg" | sed "s/^\[cm4\]$/&\n${ins}dtoverlay=pcie-32bit-dma/" > "$T/start.txt" ;;
            off) grep -v 'pcie-32bit-dma\|Allows .* to work' "$cfg" | sed "s/^\[cm4\]$/&\n${ins}#dtoverlay=pcie-32bit-dma/" > "$T/start.txt" ;;
        esac
        # The start state must be what it claims (a config.txt with no [cm4]
        # section cannot hold one)
        [ "$CV" = as-is ] || [ "$(state start.txt)" = "$CV" ] || die "could not build the $CV start state from $cfg"
        check "$CV"
    done
else
    PCI=$T/pci LSPCI_BIN=$T/fake
    conf() {
        local pre='arm_64bit=1\n\n[pi4]\nkernel=wlanpi-kernel8.img\n\n' post='otg_mode=0\ndtoverlay=dwc2,dr_mode=otg\n\n[pi5]\nkernel=wlanpi-kernel8.img\n\n[all]\n'
        local c='# Allows PCIe adapters with 32-bit DMA masks to work\n'
        case $1 in
            absent) printf "${pre}[cm4]\n${post}" ;;
            on) printf "${pre}[cm4]\n${c}dtoverlay=pcie-32bit-dma\n\n${post}" ;;
            off) printf "${pre}[cm4]\n${c}#dtoverlay=pcie-32bit-dma\n\n${post}" ;;
            dup) printf "${pre}[cm4]\ndtoverlay=pcie-32bit-dma\ndtoverlay=pcie-32bit-dma\n${post}" ;;
            indent) printf "${pre}[cm4]\n  dtoverlay=pcie-32bit-dma\n${post}" ;;
            indent-off) printf "${pre}[cm4]\n  #dtoverlay=pcie-32bit-dma\n${post}" ;;
            off-and-on) printf "${pre}[cm4]\n#dtoverlay=pcie-32bit-dma\ndtoverlay=pcie-32bit-dma\n${post}" ;;
            in-all) printf "${pre}[cm4]\n${post}dtoverlay=pcie-32bit-dma\n" ;;
            no-cm4) printf "${pre}otg_mode=0\n\n[all]\n" ;;
            no-cm4-on) printf "${pre}[all]\ndtoverlay=pcie-32bit-dma\n" ;;
        esac
    }
    bus() {
        local e slot ids vd v d c
        rm -rf "$PCI"; mkdir -p "$PCI"; : > "$T/lspci.out"
        for e in "$@"; do
            slot=${e%%=*}; ids=${e#*=}; vd=${ids%%/*}; c=${ids#*/}; v=${vd%%:*}; d=${vd#*:}
            mkdir -p "$PCI/$slot"
            echo "0x$v" > "$PCI/$slot/vendor"
            echo "0x$d" > "$PCI/$slot/device"
            [ "$c" = - ] || echo "$c" > "$PCI/$slot/class"
            [ "$c" = - ] && c=0x000000
            echo "${slot#0000:} Class [${c:2:4}]: Vendor Device [$v:$d]" >> "$T/lspci.out"
        done
    }
    # Cards: QCA WCN785x, MT7921K, MT7922, MT7925, BE200, NIC, NVMe, VL805 USB,
    # Renesas USB, and a listed and an unlisted ID without a class file
    pool=(17cb:1107/0x028000 14c3:0608/0x028000 14c3:0616/0x028000 14c3:7925/0x028000 8086:272b/0x028000
        10ec:8125/0x020000 144d:a808/0x010802 1106:3483/0x0c0330 1912:0014/0x0c0330 17cb:1107/- 10ec:8125/-)
    root="0000:00:00.0=14e4:2711/0x060400"
    # Pro: PCIe switch and onboard VL805, as on the hardware; cards at 04 and 05
    pro="$root 0000:01:00.0=12d8:2404/0x060400 0000:02:01.0=12d8:2404/0x060400 0000:02:02.0=12d8:2404/0x060400 0000:02:03.0=12d8:2404/0x060400 0000:03:00.0=1106:3483/0x0c0330"
    sets=("")
    for ((i = 0; i < ${#pool[@]}; i++)); do
        sets+=("${pool[i]}")
        for ((j = i; j < ${#pool[@]}; j++)); do sets+=("${pool[i]} ${pool[j]}"); done
    done
    for base in none root pro; do
        for extra in "${sets[@]}"; do
            [ $base = none ] && [ -n "$extra" ] && continue
            DEVS=()
            # shellcheck disable=SC2206 # device lists split on spaces
            case $base in root) DEVS=($root) ;; pro) DEVS=($pro) ;; esac
            k=4
            for x in $extra; do DEVS+=("0000:0$k:00.0=$x"); k=$((k + 1)); done
            bus "${DEVS[@]}"
            for BOARD in "Mcuzone M4" "Mcuzone M4+" "WLAN Pi Pro"; do
                for CV in absent on off dup indent indent-off off-and-on in-all no-cm4 no-cm4-on; do
                    conf "$CV" > "$T/start.txt"
                    check "$CV"
                done
            done
        done
    done
fi

echo "cases: $n, candidate identical to shipped 1.1.40: $identical"
for r in "${!why[@]}"; do echo "  differs from shipped, $r: ${why[$r]}"; done | sort
if [ "$fails" -eq 0 ]; then
    echo "pcie-32bit-dma parity: all invariants hold"
else
    echo "pcie-32bit-dma parity: $fails case(s) failed"
fi
[ "$fails" -eq 0 ]
