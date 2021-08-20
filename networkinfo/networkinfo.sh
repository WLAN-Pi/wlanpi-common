#!/bin/bash

#Author: Jiri Brejcha, jirka@jiribrejcha.net
#Monitors syslog for eth0 up and down events and triggers networkinfo scripts like CDP, LLDP, internet watchdog

DIRECTORY="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

#Check if the script is running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

#Start neighbour detection immediately after this service starts
#pgrep cdpneigh.sh | xargs sudo pkill -P 2>/dev/null
#pgrep lldpneigh.sh | xargs sudo pkill -P 2>/dev/null
#sleep 2
#"$DIRECTORY"/lldpneigh.sh &
#"$DIRECTORY"/cdpneigh.sh &
#Start monitoring internet connectivity immediately after the WLAN Pi boots up
#"$DIRECTORY"/watchinternet.sh &

#Monitor up/down status changes of eth0 and execute neighbour detection or cleanup
tail -fn0 /var/log/messages |
while read -r line
do
  case "$line" in
  *".ethernet eth0: Link is Up"*)
    logger "networkinfo script: eth0 went up"
    #Kill any running instances of the CDP and LLDP scripts
    pgrep cdpneigh.sh | xargs sudo pkill -P 2>/dev/null
    pgrep lldpneigh.sh | xargs sudo pkill -P 2>/dev/null
    #Execute neighbour detection scripts
    sleep 4 
    "$DIRECTORY"/lldpneigh.sh &
    "$DIRECTORY"/cdpneigh.sh &
  ;;
  *".ethernet eth0: Link is Down"*)
    logger "networkinfo script: eth0 went down"
    #Kill any running instances of the CDP and LLDP scripts
    pgrep cdpneigh.sh | xargs sudo pkill -P 2>/dev/null
    pgrep lldpneigh.sh | xargs sudo pkill -P 2>/dev/null
    #Execute cleanup scripts
    "$DIRECTORY"/lldpcleanup.sh
    "$DIRECTORY"/cdpcleanup.sh
  ;;
  *)
  esac
done
