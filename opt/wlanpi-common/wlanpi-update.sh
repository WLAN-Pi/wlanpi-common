#!/bin/bash
#
# Updates the WLAN Pi software and packages
#
# Authors: Jiri Brejcha, jirka@jiribrejcha.net, @jiribrejcha
#          Adrian Granados, adrian@intuitibits.com, @adriangranados
#

# Check if the script is running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must run as root. Add \"sudo\" please".
   exit 1
fi

upgradable () {
    timeout 60 apt update > /dev/null 2>&1 && apt list --upgradable 2>/dev/null | grep upgradable || exit 1
}

upgrade_all () {
    apt -y upgrade
}

upgrade () {
    apt -y --only-upgrade install wlanpi-*
}

usage () {
  echo "Usage: wlanpi-update {-a | -h | -u}"
  echo ""
  echo "  wlanpi-update -a : upgrades all packages"
  echo "  wlanpi-update -h : show usage info"
  echo "  wlanpi-update -u : upgrades wlanpi-* packages"
  echo "  wlanpi-update : shows upgradable packages"
  echo ""
  exit 0
}

case "$1" in
  -a)
      upgrade_all
      ;;
  -u)
      upgrade
      ;;
  -h)
      usage
      ;;
  *)
      upgradable
      ;;
esac

exit 0
