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
# networkd must know usb0.network before the trigger creates usb0.
reload_line=$(grep -n 'networkctl reload' debian/postinst | cut -d: -f1)
trigger_line=$(grep -n 'udevadm trigger --action=add --subsystem-match=udc' debian/postinst | cut -d: -f1)
[ "$reload_line" -lt "$trigger_line" ]
grep -qx 'net.ipv4.conf.all.arp_ignore = 1' usr/lib/sysctl.d/90-wlanpi.conf
grep -qx 'kernel.panic = 10' usr/lib/sysctl.d/90-wlanpi.conf
grep -qx 'usr/lib/sysctl.d/90-wlanpi.conf usr/lib/sysctl.d/' debian/wlanpi-common.install
grep -q '/usr/lib/systemd/systemd-sysctl /usr/lib/sysctl.d/90-wlanpi.conf' debian/postinst
