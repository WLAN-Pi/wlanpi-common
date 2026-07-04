# wlanpi-common

`wlanpi-common` provides shared scripts, utilities, and support files used across multiple WLAN-Pi packages. It is a dependency of `wlanpi-fpms` and other packages that need common network information, MOTD tips, and platform support files.

Previously, these files were bundled inside the `fpms` package. They were split out into this standalone package so that multiple consumers can depend on them without duplicating code.

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

## Installation

```bash
sudo apt update && sudo apt install wlanpi-common
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) and the [WLAN Pi developer documentation](https://github.com/WLAN-Pi/developers).

## License

See [LICENSE](LICENSE).
