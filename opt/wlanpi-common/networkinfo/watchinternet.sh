#!/bin/bash

#Author: Jiri Brejcha, jirka@jiribrejcha.net
#Monitors internet connection

CURRENTLY="offline"
PREVIOUSLY="offline"
DIRECTORY="/usr/share/fpms/BakeBit/Software/Python/scripts/networkinfo"
LOG_FILE="/tmp/watchinternet.log"
DEFAULT_GATEWAY_IP=$(ip route show | grep "default via" | cut -d " " -f3)

function gone_online {
echo -e "\e[92mWLAN Pi is now online\033[0m"
logger "networkinfo watchinternet: WLAN Pi is now online"
"$DIRECTORY"/telegrambot.sh &
log_online 2>/dev/null >> "$LOG_FILE"
}

function gone_offline {
echo -e "\e[91mWLAN Pi is now offline\033[0m"
logger "networkinfo watchinternet: WLAN Pi is now offline"
log_offline 2>/dev/null >> "$LOG_FILE"
}

function log_online {
  echo "===================================================="
  date +"WLAN Pi is now online - %a %d %b %Y %T %Z"
  echo "===================================================="
  echo ""
  echo ""
}

function log_offline {
  echo "====================================================="
  date +"WLAN Pi is now offline - %a %d %b %Y %T %Z"
  echo "====================================================="
  echo ""
  echo "--- Ping gateway -----------------------------"
  ping -c 1 "$DEFAULT_GATEWAY_IP"
  echo ""
  echo "--- Ping icmp.canireachthe.net ---------------"
  ping -c 1 icmp.canireachthe.net 2>&1
  echo ""
  echo "--- IP address -------------------------------"
  ip a
  echo ""
  echo "--- ethtool eth0 -----------------------------"
  ethtool eth0 2>&1
  echo ""
  echo "--- ethtool eth1 -----------------------------"
  ethtool eth1 2>&1
  echo ""
  echo "--- iwconfig ---------------------------------"
  iwconfig 2>&1
  echo ""
  echo "--- IP routing table -------------------------"
  ip route show
  echo ""
  echo "--- DNS servers ------------------------------"
  cat /etc/resolv.conf
  echo ""
  echo ""
}

while true; do

  #Current default route interface
  DEFAULT_ROUTE_CURRENTLY=$(ip route show | grep "default via" | cut -d " " -f5)

  if [[ "$DEFAULT_ROUTE_CURRENTLY" != "$DEFAULT_ROUTE_PREVIOUSLY" ]] && [[ "$DEFAULT_ROUTE_CURRENTLY" ]]; then
    echo "-------------------------------"
    date
    echo "Default route via: $DEFAULT_ROUTE_CURRENTLY"
  fi

  if nc -z -w 3 canireachthe.net 443 2>/dev/null; then
    CURRENTLY="online"
  else
    CURRENTLY="offline"
 fi

  #WLAN Pi is now online
  if [[ "$CURRENTLY" == "online" ]] && [[ "$PREVIOUSLY" == "offline" ]]; then
    gone_online
  fi

  #WLAN Pi is now offline
  if [[ "$CURRENTLY" == "offline" ]] && [[ "$PREVIOUSLY" == "online" ]]; then
    gone_offline
  fi

  PREVIOUSLY="$CURRENTLY"
  DEFAULT_ROUTE_PREVIOUSLY="$DEFAULT_ROUTE_CURRENTLY"
  sleep 3
done


