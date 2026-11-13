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

`wlanpi-model` identifies the platform (R4, R5, M4, M4+, Pro, Go) by a first-match sequence of hardware probes: the SoC from `/proc/cpuinfo`, then on a CM4 the Pro battery gauge, the M4+ EEPROM, a Go device-info file, the Go serial port, and the Go `max3421` overlay.

The detected platform is written to `/etc/wlanpi-model` on the first successful detection. On later boots, detection is skipped when that file exists and still matches this SoC family (Raspberry Pi 4, Raspberry Pi 5, or Compute Module 4). "Matches" is that cheap family check only; a cached Pro on any CM4 is treated as a match, even if the board is an M4.

These media moves are not supported and are not handled in code. They will apply the cached platform's settings on the wrong hardware and can break the device:

- Moving an SD card from a Pro to an M4, or from an M4 to a Pro
- Moving a Go CM4 (onboard eMMC; the Go has no microSD slot) to another platform

If a cheap check disagrees with a cached CM4 subtype (a Pro cache with no battery gauge, an M4 cache with a Pro battery, or a Go cache with no Go overlay and no Go device-info), `wlanpi-model` prints a warning and still uses the cache. Delete `/etc/wlanpi-model` to force a new detection. A family mismatch (for example an R4 cache on a CM4) is re-detected and the cache is overwritten.

`/home/.device-info/model` is not this cache. It is a Go identity file written by the Go image (`go-hw-machine-id`) onto the Go's eMMC, and `wlanpi-model` only uses it as a Go probe.

M.2 Wi-Fi cards are identified from `lspci` plus instantiation: a card is treated as present only when a network interface exists under its PCI device in sysfs. A card that enumerates in `lspci` but has no netdev (for example a BE200 that failed to load firmware) is reported as "enumerated, not instantiated".

## Installation

```bash
sudo apt update && sudo apt install wlanpi-common
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) and the [WLAN Pi developer documentation](https://github.com/WLAN-Pi/developers).

## License

See [LICENSE](LICENSE).
