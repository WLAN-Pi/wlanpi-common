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
DEBUG=0

# just in case we need to debug this script:
debugger() {
    if [ "$DEBUG" != '0' ];then
      echo $1
    fi
}

# check if config file exists
check_file_exists() {

    debugger "Checking reg domain file exists..."

    if [ ! -e "${REG_DOMAIN_FILE}" ] ; then
      err_str="Reg domain file not found: ${REG_DOMAIN_FILE}"
      echo $err_string
      logger $err_string
      exit 1
    fi

    debugger "File exists."
}

# return current domain from reg domain file
get() {

    check_file_exists

    # target field: REGDOMAIN=GB
    debugger "Getting reg domain current value..."
    api_key=$(cat $REG_DOMAIN_FILE | grep REGDOMAIN | awk -F'=' '{print $2}')
    if [ "$?" != '0' ]; then
        err_string="Error extracting reg domain from $REG_DOMAIN_FILE"
        echo $err_string
        logger $err_string
        exit 1
    else
        debugger "Got reg domain: $api_key"
        echo $api_key
        exit 0
    fi
}

# set domain in reg domain file
set() {

    check_file_exists

    debugger "Setting domain: $REG_DOMAIN_FILE"
    
    # set the new key in the chat bot config file
     sed -i "s/REGDOMAIN=.*/REGDOMAIN=$DOMAIN/" "$REG_DOMAIN_FILE"

    if [ "$?" != '0' ]; then
        err_string="Error adding domain to $REG_DOMAIN_FILE"
        echo $err_string
        logger $err_string
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
        echo "  reg-domain -v : show script version"
        echo "  reg-domain get: show current reg domain"
        echo "  reg-domain set [domain str]: set reg domain"
        echo "  reg-domain : show usage info"
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
        get
        ;;
  set)
        set
        ;;
  help)
        help
        ;;
  *)
        usage
        ;;
esac

exit 0
