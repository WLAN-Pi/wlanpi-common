#!/bin/bash

WIRELESS_TOOLS="0"

stopInterfaces() {
  unset iface_list
  if [ -d '/sys/class/net' ]; then
    # refactor this for globs, but make sure it works across shells
    # shellcheck disable=2045
    for iface in $(ls -1 /sys/class/net)
    do
      if [ -f "/sys/class/net/${iface}/uevent" ]; then
        if grep -q 'DEVTYPE=wlan' "/sys/class/net/${iface}/uevent"
        then
          iface_list="${iface_list} ${iface}"
        fi
      fi
    done
  fi
  if [ "${WIRELESS_TOOLS}" = "1" ] && [ -x "$(command -v sort 2>&1)" ]; then
    for iface in $(iwconfig 2> /dev/null | sed -e 's/^\(\w*\)\s.*/\1/' -e '/^$/d'); do
      iface_list="${iface_list} ${iface}"
    done
    #                                           sort needs newline separated,   convert back after
    iface_list="$(printf "%s" "${iface_list}" | sed 's/ /\n/g' | sort -bu | sed ':a;N;$!ba;s/\n/ /g')"
  fi
  for wlaniface in ${iface_list}
  do
    sh -c "airmon-ng stop ${wlaniface}"
    sh -c "ifconfig ${wlaniface} up"
  done
}

stopInterfaces
