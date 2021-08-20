#!/bin/bash

#Author: Jiri Brejcha, jirka@jiribrejcha.net
#This is a cable finder tool. Cycles eth0 down and up repeatedly so that you can find the respective port on the switch by watching the switch port LEDs.

#Default number of down & up cycles if not specified explicitly otherwise
COUNT=5
#Default interface name if not specified explicitly otherwise
INTERFACE="eth0"
#Uses colors in output by default
COLOR="yes"

usage(){
  echo "Usage: $0 [[-c NUMBER_OF_CYCLES ] | [-t TIMEOUT_IN_SECONDS] | [-i INTERFACE_NAME] [-h] | --no-color]"
  echo ""
  echo "By default blinks until stopped by CRTL+C."
}

NUMBER_OF_PROCESSES=$(pidof -x "portblinker.sh" | wc -w)
if [ "$NUMBER_OF_PROCESSES" -ge "3" ]; then
  echo "Error: Port Blinker is already running"
  exit 1
fi

trap execute_on_int INT

execute_on_int(){
  sudo dhclient eth0 &
  echo ""
  echo "Stopping now"
  exit 0
}

blink_nonstop(){
  echo "Interface: $INTERFACE"
  while true; do
    if  [ "$COLOR" == "yes" ]; then
      echo -e "\e[91mDown\033[0m"
    else
      echo "Down"
    fi
    sudo ifconfig "$INTERFACE" down
    sleep 3
    if  [ "$COLOR" == "yes" ]; then
      echo -e "\e[92mUp\033[0m"
    else
      echo "Up"
    fi
    sudo ifconfig "$INTERFACE" up
    sleep 7
  done
}

blink_n_times(){
  echo "Interface: $INTERFACE"
  COUNT=$1
  for (( c=1; c<="$COUNT"; c++ ))
  do
    if  [ "$COLOR" == "yes" ]; then
      echo -e "\e[91mDown\033[0m"
    else
      echo "Down"
    fi
    sudo ifconfig "$INTERFACE" down
    sleep 3
    if  [ "$COLOR" == "yes" ]; then
      echo -e "\e[92mUp\033[0m"
    else
      echo "Up"
    fi
    sudo ifconfig "$INTERFACE" up
    sleep 7
  done
  sudo dhclient eth0 &
}

blink_n_seconds(){
  echo "Interface: $INTERFACE"
  timeout --foreground $1 bash <<EOF
  while true; do
    if  [ "$COLOR" == "yes" ]; then
      echo -e "\e[91mDown\033[0m"
    else
      echo "Down"
    fi
    sudo ifconfig "$INTERFACE" down
    sleep 3
    if  [ "$COLOR" == "yes" ]; then
      echo -e "\e[92mUp\033[0m"
    else
      echo "Up"
    fi
    sudo ifconfig "$INTERFACE" up
    sleep 7
  done
EOF
sudo dhclient eth0 &
}

#If an incomplete argument (complete argument is 2 strings separated by space) was provided display usage, with the exception of --no-color
if [ "$#" -eq 1 ] && [[ "$*" != *'--no-color'* ]]; then
  usage
  exit
fi

#Was any interface name passed as an argument
if [[ "$*" == *'-i '* ]]; then
    INTERFACE=$(echo $@ | grep -o '\-i .*' | cut -d " " -f2)
fi

#Was --no-color argument used
if [[ "$*" == *'--no-color'* ]]; then
    COLOR="no"
fi

#Parse arguments
while [ "$1" != "" ]; do
  case $1 in
      -c | --count )          shift
                              blink_n_times $1
                              exit
                              ;;
      -t | --timeout )        shift
                              blink_n_seconds $1
                              exit
                              ;;
      -h | --help )           usage
                              exit
                                ;;
      * )
  esac
  shift
done

#Default behaviour when script is executed without arguments
#blink_n_times "$COUNT"
blink_nonstop

exit 0
