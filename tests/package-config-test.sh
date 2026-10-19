#!/bin/sh
set -eu

grep -q 'groupadd --system' debian/postinst
grep -q 'usermod --append --groups gpio,spi wlanpi' debian/postinst
grep -q 'udevadm trigger --subsystem-match=gpio --subsystem-match=gpiomem --subsystem-match=spidev' debian/postinst
grep -q 'raspi-utils-core' debian/control
! grep -R '/usr/bin/raspi-gpio' opt/
grep -q 'User=wlanpi' usr/lib/systemd/system/irtt.service.d/wlanpi-common.conf
grep -q 'irtt.service.d/wlanpi-common.conf' debian/wlanpi-common.install
grep -q '^usr/lib/systemd/network/usb0.network ' debian/wlanpi-common.install
grep -q '^usr/lib/udev/rules.d/90-wlanpi-usb-otg.rules ' debian/wlanpi-common.install
grep -q 'TEST!="/usr/bin/usb-ethernet-gadget.sh"' usr/lib/udev/rules.d/90-wlanpi-usb-otg.rules
grep -q '^Address=198.18.42.1/24$' usr/lib/systemd/network/usb0.network
grep -q 'udevadm trigger --action=add --subsystem-match=udc' debian/postinst
