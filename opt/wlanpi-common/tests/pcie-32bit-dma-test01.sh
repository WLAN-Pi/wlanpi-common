#!/bin/bash
set -eu

SCRIPT="$(dirname "$0")/../wlanpi-config-at-startup.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
sed -n '/^configure_pcie_32bit_dma()/,/^}/p' "$SCRIPT" > "$TMP/function.sh"

cat > "$TMP/lspci" <<'EOF'
#!/bin/sh
printf '%s\n' "$PCI_DEVICES"
EOF
chmod +x "$TMP/lspci"

run_case() {
    expected_reboot=$1
    expected_line=$2
    pci_devices=$3
    config=$4
    printf '%s\n' "$config" > "$TMP/config.txt"
    CONFIG_FILE="$TMP/config.txt"
    REQUIRES_REBOOT=0
    PCI_DEVICES="$pci_devices"
    export CONFIG_FILE REQUIRES_REBOOT PCI_DEVICES
    PATH="$TMP:$PATH"
    debugger() { :; }
    # shellcheck source=/dev/null
    source "$TMP/function.sh"
    configure_pcie_32bit_dma
    [ "$REQUIRES_REBOOT" -eq "$expected_reboot" ]
    grep -q "^$expected_line$" "$CONFIG_FILE"
}

base_config=$'[cm4]\notg_mode=0\n[all]'
enabled_config=$'[cm4]\ndtoverlay=pcie-32bit-dma\n[all]'

run_case 1 'dtoverlay=pcie-32bit-dma' '04:00.0 0280: 14c3:0608' "$base_config"
run_case 0 'dtoverlay=pcie-32bit-dma' '04:00.0 0280: 14c3:0608' "$enabled_config"
run_case 1 '#dtoverlay=pcie-32bit-dma' '04:00.0 0280: 8086:272b' "$enabled_config"
run_case 0 'otg_mode=0' '04:00.0 0280: 8086:272b' "$base_config"
