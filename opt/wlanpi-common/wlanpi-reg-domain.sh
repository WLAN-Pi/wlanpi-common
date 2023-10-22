#!/usr/bin/env bash

# Script to get/set reg domain and country code on WLAN Pi Pro
# Author : Nigel Bowden
#
# This script manipulates the REGDOMAIN field in the REGDOMAIN file
#
# Return values:
#
#   Zero = success (e.g. exit 0)
#   Non-Zero = fail (e.g. exit 1) (Note: Echo failure string before exit)
#
# Logging:
#   Log faiures to syslog
#

# fail on script errors
set -e

# Define ANSI colour codes
ORANGE='\033[0;33m'
RED='\033[0;31m'
GREEN='\033[0;32m'
NO_COLOUR='\033[0m'

REG_DOMAIN_FILE="/etc/default/crda"
HOTSPOT_FILE="/etc/wlanpi-hotspot/conf/hostapd.conf"
WCONSOLE_FILE="/etc/wlanpi-wconsole/conf/hostapd.conf"
SERVER_FILE="/etc/wlanpi-server/conf/hostapd.conf"
VERSION=0.1.2
DOMAIN=$2
NO_PROMPT=$3
SCRIPT_NAME=$(echo ${0##*/})
DEBUG=0

# check if the script is running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must run as root. Add \"sudo\" please".
   exit 1
fi

# just in case we need to debug this script:
debugger() {
    if [ "$DEBUG" != '0' ];then
      echo $1
    fi
}

err_report() {
    err_str="$1"

    echo "Error: $err_str"
    logger "($SCRIPT_NAME) $err_str - Error!"
    debugger "($SCRIPT_NAME) $err_str - Error!"

    return 0
}

# check if file exists
check_file_exists() {

    debugger "($SCRIPT_NAME) Checking file exists: $1"

    if [ -z "$1" ]; then
       err_report "No filename passed to : check_file_exists()"
       exit 1
    fi

    filename=$1

    if [ ! -e "${filename}" ] ; then
      err_report "File not found: ${filename}"
      exit 1
    fi

    debugger "($SCRIPT_NAME) File exists."
}

# return current domain from reg domain file
get_domain () {

    check_file_exists $REG_DOMAIN_FILE

    # target field: REGDOMAIN=GB
    debugger "Getting reg domain current value..."
    crda_domain=$(cat $REG_DOMAIN_FILE | grep 'REGDOMAIN=' | awk -F'=' '{print $2}')

    if [ "$?" != "0" ]; then
        err_report "Error extracting reg domain from $REG_DOMAIN_FILE"
        exit 1
    fi

    if [ -z "$crda_domain" ]; then
        debugger "No reg domain configured yet."
        echo "No reg domain configured yet. Configure one using \"sudo wlanpi-reg-domain set XX\", where XX represents the country code."
        exit 0
    else
        debugger "Got reg domain: $crda_domain"
        echo "$crda_domain"
        exit 0
    fi
}

# set domain in reg domain file
set_domain () {

    check_file_exists $REG_DOMAIN_FILE

    debugger "Setting domain: $REG_DOMAIN_FILE"

    if [ -z "$DOMAIN" ]; then
       err_report "No country code provided"
       exit 1
    fi

    # set the new reg domain in the config file
     sed -i "s/REGDOMAIN=.*/REGDOMAIN=$DOMAIN/" "$REG_DOMAIN_FILE"

    if [ "$?" != '0' ]; then
        err_report "Error adding domain to $REG_DOMAIN_FILE"
        exit 1
    else
        debugger "Added domain $DOMAIN to $REG_DOMAIN_FILE"
    fi

    # set the new country code for Hotspot mode
    check_file_exists "$HOTSPOT_FILE"
    debugger "Setting country code for Hotspot mode: $HOTSPOT_FILE"
    sed -i "s/country_code=.*/country_code=$DOMAIN/" "$HOTSPOT_FILE"
    if [ "$?" != '0' ]; then
        err_report "Error adding country code to $HOTSPOT_FILE"
        exit 1
    else
        debugger "Added country code $DOMAIN to $HOTSPOT_FILE"
    fi

    # set the new country code for Wi-Fi Console mode
    check_file_exists "$WCONSOLE_FILE"
    debugger "Setting country code for Wi-Fi Console mode: $WCONSOLE_FILE"
    sed -i "s/country_code=.*/country_code=$DOMAIN/" "$WCONSOLE_FILE"
    if [ "$?" != '0' ]; then
        err_report "Error adding country code to $WCONSOLE_FILE"
        exit 1
    else
        debugger "Added country code $DOMAIN to $WCONSOLE_FILE"
    fi

    # set the new country code for Server mode
    check_file_exists "$SERVER_FILE"
    debugger "Setting country code for Server mode: $SERVER_FILE"
    sed -i "s/country_code=.*/country_code=$DOMAIN/" "$SERVER_FILE"
    if [ "$?" != '0' ]; then
        err_report "Error adding country code to $SERVER_FILE"
        exit 1
    else
        debugger "Added country code $DOMAIN to $SERVER_FILE"
    fi

    if ! grep -q "classic" /etc/wlanpi-state; then
        echo "Please switch your WLAN Pi to the Classic mode for the Hotspot and Wi-Fi Console new country code to take effect."
    fi

    if [ "$NO_PROMPT" == "--no-prompt" ]; then
        reboot
    else
        while true; do
            read -p "A reboot is required. Reboot now? (Y/n) " yn
            case $yn in
                [yY]|"" ) reboot;
                    break;;
                [nN] ) echo -e "${RED}Warning: Wi-Fi might not work fully until you reboot!${NO_COLOUR}";
                       exit 0;;
                * ) echo "Error: Invalid response";;
            esac
        done
    fi
}

# usage output
usage () {
        echo "Gets or sets the Wi-Fi RF regulatory domain"
        echo ""
        echo "Usage: wlanpi-reg-domain {get | set | -h | --help | -v}"
        echo ""
        echo "Options:"
        echo "  get           Shows current reg domain"
        echo "  set DOMAIN    Sets RF regulatory domain"
        echo "  -h            Shows usage info"
        echo "  --help        Shows usage info"
        echo "  -v            Shows script version"
        echo ""
        exit 0
}

debugger "--- Debug on ---"

# case statements
case "$1" in
  -v)
        echo "$VERSION"
        ;;
  get)
        get_domain
        ;;
  set)
        set_domain
        ;;
  -h|--help|help|"")
        usage
        ;;
  *)
        echo "Error: Invalid option"
        exit 1
        ;;
esac

exit 0
