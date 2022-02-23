#!/bin/bash

# Author: Jiri Brejcha, jirka@jiribrejcha.net, @jiribrejcha
# This cable finder tool for WLAN Pi Pro repeatedly bounces eth0 down and up so that you can find the respective port on the switch by watching the switch port LEDs.

# Default number of down & up cycles if not specified explicitly otherwise
COUNT=5
# Default interface name if not specified explicitly otherwise
INTERFACE="eth0"
# Use colors in output by default
COLOR="yes"
VERSION="2.0.1"
SCRIPT_NAME="$(basename "$0")"

# Check if the script is running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must run as root. Add \"sudo\" please".
   exit 1
fi

usage(){
    echo "This cable finder tool for WLAN Pi Pro repeatedly bounces eth0 down and up so that you can find the respective port on the switch by watching the switch port LEDs."
    echo
    echo "With no arguments passed, it bounces eth0 until stopped by CRTL+C."
    echo
    echo "Usage:"
    echo "  $SCRIPT_NAME -c <number-of-cycles>"
    echo "  $SCRIPT_NAME -t <timeout-in-seconds>"
    echo "  $SCRIPT_NAME [options]"
    echo
    echo "Options:"
    echo "  -v, --version   Show version"
    echo "  -h, --help      Show this screen"
    echo "  -i <interface>  Interface to bounce"
    echo "  --no-color      Disable color in the output"
    echo
    exit 0
}

version(){
    echo "$VERSION"
    exit 0
}

NUMBER_OF_PROCESSES=$(pidof -x "portblinker.sh" | wc -w)
if [ "$NUMBER_OF_PROCESSES" -ge "3" ]; then
  echo "Error: Port Blinker is already running"
  exit 1
fi

trap execute_on_int INT

# Execute these commands when user presses CTRL+C or stops the process
execute_on_int(){
  ethtool -s "$INTERFACE" speed 1000
  sudo dhclient eth0 > /dev/null 2>&1 &
  echo ""
  echo "Stopping now"
  exit 0
}

blink_nonstop(){
  echo "Interface: $INTERFACE"
  while true; do
    if  [ "$COLOR" == "yes" ]; then
      echo -e "\e[91m100 Mbps\033[0m"
    else
      echo "100 Mbps"
    fi
    ethtool -s "$INTERFACE" speed 100
    sleep 6
    if  [ "$COLOR" == "yes" ]; then
      echo -e "\e[92m1 Gbps\033[0m"
    else
      echo "1 Gbps"
    fi
    ethtool -s "$INTERFACE" speed 1000
    sleep 6
  done
}

blink_n_times(){
  echo "Interface: $INTERFACE"
  COUNT=$1
  for (( c=1; c<="$COUNT"; c++ ))
  do
    if  [ "$COLOR" == "yes" ]; then
      echo -e "\e[91m100 Mbps\033[0m"
    else
      echo "100 Mbps"
    fi
    ethtool -s "$INTERFACE" speed 100
    sleep 6
    if  [ "$COLOR" == "yes" ]; then
      echo -e "\e[92m1 Gbps\033[0m"
    else
      echo "1 Gbps"
    fi
    ethtool -s "$INTERFACE" speed 1000
    sleep 6
  done
  sudo dhclient eth0 > /dev/null 2>&1 &
}

blink_n_seconds(){
  echo "Interface: $INTERFACE"
  timeout --foreground $1 bash <<EOF
  while true; do
    if  [ "$COLOR" == "yes" ]; then
      echo -e "\e[91m100 Mbps\033[0m"
    else
      echo "100 Mbps"
    fi
    ethtool -s "$INTERFACE" speed 100
    sleep 6
    if  [ "$COLOR" == "yes" ]; then
      echo -e "\e[92m1 Gbps\033[0m"
    else
      echo "1 Gbps"
    fi
    ethtool -s "$INTERFACE" speed 1000
    sleep 6
  done
EOF
ethtool -s "$INTERFACE" speed 1000
sudo dhclient eth0 > /dev/null 2>&1 &
}

# Was any interface name passed as an argument
if [[ "$*" == *'-i '* ]]; then
    INTERFACE=$(echo $@ | grep -o '\-i .*' | cut -d " " -f2)
fi

# Was --no-color argument used
if [[ "$*" == *'--no-color'* ]]; then
    COLOR="no"
fi

# Parse arguments
while [ "$1" != "" ]; do
  case $1 in
      -c | --count)          shift
                             blink_n_times $1
                             exit
                             ;;
      -t | --timeout)        shift
                             blink_n_seconds $1
                             exit
                             ;;
      -h | --help)           usage ;;
      -v | --version)        version ;;
      * )
  esac
  shift
done

# Default behaviour when script is executed without arguments
# blink_n_times "$COUNT"
blink_nonstop

exit 0