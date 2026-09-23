#!/bin/sh
set -eu

grep -q 'groupadd --system' debian/postinst
grep -q 'usermod --append --groups gpio,spi wlanpi' debian/postinst
grep -q 'udevadm trigger --subsystem-match=gpio --subsystem-match=gpiomem --subsystem-match=spidev' debian/postinst
grep -q 'raspi-utils-core' debian/control
! grep -R '/usr/bin/raspi-gpio' opt/
grep -q 'User=wlanpi' usr/lib/systemd/system/irtt.service.d/wlanpi-common.conf
grep -q 'irtt.service.d/wlanpi-common.conf' debian/wlanpi-common.install
