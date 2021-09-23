#!/bin/bash

#Author: Jiri Brejcha, jirka@jiribrejcha.net
#Sends current WLAN Pi IP address and other useful details to you in a Telegram message. Requires internet connection.

#----------------------------------------------------------
# READ THIS FIRST
#
# Add your Telegram API key to this configuration file manually:
# sudo nano /etc/networkinfo/telegrambot.conf
#
# Or by running this command once. Replace "xxx" with your key and remove the leading "#":
# sudo bash -c 'echo "TELEGRAM_API_KEY=xxx" >> /etc/networkinfo/telegrambot.conf'
#----------------------------------------------------------

CONFIG_PATH="/etc/networkinfo/"
CONFIG_FILE="/etc/networkinfo/telegrambot.conf"

#Check if the script is running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

[ ! -d "$CONFIG_PATH" ] && sudo mkdir "$CONFIG_PATH"

if [ ! -f "$CONFIG_FILE" ]; then
  bash -c "echo '#Uncomment the line below and replace xxx with your Telegram API key' >> $CONFIG_FILE"
  bash -c "echo '#TELEGRAM_API_KEY=xxx' >> $CONFIG_FILE"
  chmod 660 "$CONFIG_FILE"
fi

#Load configuration file
source "$CONFIG_FILE"

#Do not continue if Port Blinker is running. We don't want to spam you with Telegram messages every time eth0 goes up. 
PORTBLINKERRUNNING=$(ps aux | grep "portblinker.sh" | grep -v "defunct" | grep -v "grep")
if [ "$PORTBLINKERRUNNING" ] ; then
  echo "Error: Port Blinker is running on eth0 and will generate many Telegram messages. Stopping Telegram bot."
  logger "networkinfo telegrambot: Error - Stop Port Blinker first to avoid receiving many Telegram messages"
  exit 1
fi

#Got the API key?
if [ -z "$TELEGRAM_API_KEY" ]; then
  echo "Error: No Telegram API key found"
  echo "Add your Telegram API key to this configuration file:"
  echo "sudo nano /etc/networkinfo/telegrambot.conf"
  logger "networkinfo telegrambot: Error - No API key found!"
  exit 1 
fi

#Get Chat ID - for this to work you have to send a Telegram message to the bot first from your laptop or phone
if [ -z "$TELEGRAM_CHAT_ID" ] || [ "$TELEGRAM_CHAT_ID" == "null" ]; then
  TELEGRAM_CHAT_ID=$(curl -s -X GET https://api.telegram.org/bot"$TELEGRAM_API_KEY"/getUpdates | jq -r ".result[0].message.chat.id")
  if [ -z "$TELEGRAM_CHAT_ID" ] || [ "$TELEGRAM_CHAT_ID" == "null" ]; then
    echo "Error: Telegram Chat ID not found. Send a Telegram message with any text to the bot. This is mandatory!"
    logger "networkinfo telegrambot: Error - No Chat ID found!"
    exit 1
  else
    bash -c "echo TELEGRAM_CHAT_ID=\"$TELEGRAM_CHAT_ID\" >> $CONFIG_FILE"
  fi
fi

logger "networkinfo telegrambot: Collecting data"

#Collect all data
ETH0SPEED=$(ethtool eth0 2>/dev/null | grep -q "Link detected: yes" && ethtool eth0 2>/dev/null | grep "Speed" | sed 's/....$//' | cut -d ' ' -f2  || echo "disconnected")
ETH0DUPLEX=$(ethtool eth0 2>/dev/null | grep -q "Link detected: yes" && ethtool eth0 2>/dev/null | grep "Duplex" | cut -d ' ' -f 2 || echo "disconnected")
HOSTNAME=$(hostname)
UPTIME=$(uptime -p | cut -c4-)
MODE=$(cat /etc/wlanpi-state)
ETH0IP=$(ip a | grep "eth0" | grep "inet" | grep -v "secondary" | head -n1 | cut -d '/' -f1 | cut -d ' ' -f6)
UPLINK=$(ip route show | grep "default via" | cut -d " " -f5)
UPLINKIP=$(ip a | grep "$UPLINK" | grep "inet" | grep -v "secondary" | head -n1 | cut -d '/' -f1 | cut -d ' ' -f6)
NEIGHBOUR=$(grep -q "Name:" /tmp/lldpneigh.txt 2>/dev/null && cat /tmp/lldpneigh.txt | sed 's/^Name:/Connected to:/g' | sed 's/^Desc:/Port description:/g' | sed 's/^IP:/Neighbour IP:/g' | sed -z 's/\n/%0A/g')
if [ -z "$NEIGHBOUR" ]; then
  NEIGHBOUR=$(grep -q "Name:" /tmp/cdpneigh.txt 2>/dev/null && cat /tmp/cdpneigh.txt | sed 's/^Name:/Connected to:/g' | sed 's/^Port:/Port description:/g' | sed 's/^IP:/Neighbour IP:/g' |sed 's/^SW:/Software version:/g' | sed -z 's/\n/%0A/g')
fi

#Get public IP data
DATAINJSON=$(timeout 3 curl -s 'ifconfig.co/json')
PUBLICIP=$(echo "$DATAINJSON" | jq -r '.ip')
PUBLICIPCOUNTRY=$(echo "$DATAINJSON" | jq -r '.country')
PUBLICIPASNORG=$(echo "$DATAINJSON" | jq -r '.asn_org')
PUBLICIPHOSTNAME=$(echo "$DATAINJSON" | jq -r '.hostname')
PUBLICIPASN=$(echo "$DATAINJSON" | jq -r '.asn')

if [ -z "$ETH0IP" ]; then
  CURRENTIP="$UPLINKIP"
else
  CURRENTIP="$ETH0IP"
fi

#Compose the message
TEXT=""
TEXT+="%f0%9f%9f%a2 <b>$HOSTNAME is now online</b> %0A"
if [ "$ETH0IP" ]; then
  TEXT+="Eth0 IP address: <code>$ETH0IP</code> %0A"
fi
if [[ "$ETH0SPEED" == "disconnected" ]]; then
  TEXT+="Eth0 is down %0A"
else
  TEXT+="Eth0 speed: $ETH0SPEED %0A"
  TEXT+="Eth0 duplex: $ETH0DUPLEX %0A"
fi
TEXT+="WLAN Pi mode: $MODE %0A"
TEXT+="Uptime: $UPTIME %0A"

if [ ! -z "$NEIGHBOUR" ]; then
  TEXT+="%0A"
  TEXT+="$NEIGHBOUR"
fi

TEXT+="%0A"
TEXT+="Uplink to internet: $UPLINK %0A"
if [[ "$UPLINK" != "eth0" ]]; then
  TEXT+="Local $UPLINK IP address: $UPLINKIP %0A"
fi
TEXT+="Public IP: <code>$PUBLICIP</code>, <code>$PUBLICIPHOSTNAME</code> %0A"

if [ ! -z "$CURRENTIP" ]; then
  TEXT+="%0A"
  TEXT+="Web interface: http://$CURRENTIP %0A"
  #TEXT+="Web console: https://$CURRENTIP:9090 %0A"
  TEXT+="SSH: <code>ssh://wlanpi@$CURRENTIP</code> %0A"
  #TEXT+="Copy file to TFTP server: copy flash:filename tftp://$CURRENTIP %0A"
fi

#Try using this instead for complex text
#curl --data chat_id=12345678 --data-urlencode "text=Some complex text $25 78%"  "https://api.telegram.org/bot0000000:KEYKEYKEYKEYKEYKEY/sendMessage"

#Send message
TELEGRAM_RESPONSE=$(timeout 5 curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_API_KEY/sendMessage?chat_id=$TELEGRAM_CHAT_ID&parse_mode=html&text=$TEXT" | jq '.ok')

if [ "$TELEGRAM_RESPONSE" == "true" ]; then
  echo "Telegram message successfully sent"
  logger "networkinfo telegrambot: Message successfully sent"
else
  echo "Error: Failed to send Telegram message"
  logger "networkinfo telegrambot: Error - Failed to send message"
  exit 1
fi
