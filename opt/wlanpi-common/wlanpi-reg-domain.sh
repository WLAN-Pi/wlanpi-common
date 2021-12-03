#!/usr/bin/env bash

# Script to get/set reg domain on WLAN Pi Pro
# Author : Nigel Bowden
#
# This script manipulates the REGDOMAIN field in the 
# REGDOMAIN file.
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

REG_DOMAIN_FILE=/etc/default/crda
VERSION=0.1.0
DOMAIN=$2
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

    echo "$err_str"
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
      err_report "File not found: ${filenme}"      
      exit 1
    fi

    debugger "($SCRIPT_NAME) File exists."
}

# return current domain from reg domain file
get_domain () {

    check_file_exists $REG_DOMAIN_FILE

    # target field: REGDOMAIN=GB
    debugger "Getting reg domain current value..."
    api_key=$(cat $REG_DOMAIN_FILE | grep REGDOMAIN | awk -F'=' '{print $2}')

    if [ "$?" != '0' ]; then
        err_report "Error extracting reg domain from $REG_DOMAIN_FILE"
        exit 1
    else
        debugger "Got reg domain: $api_key"
        echo $api_key
        exit 0
    fi
}

# set domain in reg domain file
set_domain () {

    check_file_exists $REG_DOMAIN_FILE

    debugger "Setting domain: $REG_DOMAIN_FILE"

    if [ -z "$DOMAIN" ]; then
       err_report "No domain passed to : set_domain()"
       exit 1
    fi
    
    # set the new key in the chat bot config file
     sed -i "s/REGDOMAIN=.*/REGDOMAIN=$DOMAIN/" "$REG_DOMAIN_FILE"

    if [ "$?" != '0' ]; then
        err_report "Error adding domain to $REG_DOMAIN_FILE"
        exit 1
    else
        debugger "Added domain value: $API_KEY"
        exit 0
    fi
}

# return help string that provides short-form overview
# of this command
help () {
    echo "Get or set the Wi-Fi registration domain"
}

# usage output
usage () {
        echo "Usage: reg-domain {-v | get | set | help}"
        echo ""
        echo "  wlanpi-reg-domain.sh -v : show script version"
        echo "  wlanpi-reg-domain.sh get: show current reg domain"
        echo "  wlanpi-reg-domain.sh set [domain str]: set reg domain"
        echo "  wlanpi-reg-domain.sh : show usage info"
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
  help)
        help
        ;;
  *)
        usage
        ;;
esac

exit 0