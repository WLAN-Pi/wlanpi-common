# wlanpi-common

`wlanpi-common` provides shared scripts, utilities, and support files used across multiple WLAN-Pi packages. It is a dependency of `wlanpi-fpms` and other packages that need common network information, MOTD tips, and platform support files.

Previously, some of these files were bundled inside the `fpms` package. They were split out into this standalone package so that multiple consumers can depend on them without duplicating code. Some of these scripts will be merged to a more centralized provider in `wlanpi-core` in the future.

## Components

### Network Information Scripts

A collection of `networkinfo` scripts that provide:

- CDP/LLDP neighbour detection — identify the switch port and upstream device a WLAN Pi is connected to
- Public IP address display
- Internet reachability checks
- Ethernet LED blinking — trace an unknown cable to a switch port

These scripts are called by `wlanpi-fpms` to populate the front panel menu display.

### MOTD Tips

Tips shown after SSH login appear one per line in `/opt/wlanpi-common/motd-tips.txt`. Add new tips there — one tip per line.

### Platform detection

`wlanpi-model` identifies the platform by a first-match sequence of hardware probes, then writes the model to `/etc/wlanpi-model`. Later calls use that file if it exists; delete it to force a new detection. Moving the card or CM4 to a different device means a reflash.

`/home/.device-info/model` is a Go identity file, not this cache.

M.2 Wi-Fi cards come from `lspci`. A card with a netdev under its PCI device is listed as before. A card without a netdev is listed with three stages: PCI enumerated, driver bound (`/sys/bus/pci/devices/*/driver`), and netdev present.

## Installation

```bash
sudo apt update && sudo apt install wlanpi-common
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) and the [WLAN Pi developer documentation](https://github.com/WLAN-Pi/developers).

## License

See [LICENSE](LICENSE).
