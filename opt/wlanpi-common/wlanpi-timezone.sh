#!/usr/bin/env bash

# Script to get/set timezone on WLAN Pi Pro
# Author : Nigel Bowden
#
# This script uses the timedatectl command to 
# get and set the device timezone.
#
# Cmds:
#  - List all timezones: timedatectl list-timezones | grep .
#  - Get current timezone: timedatectl | grep zone | awk '{print $3}'
#  - Set timezone: timedatectl set-timezone Europe/London
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

TIMEDATECTL=/usr/bin/timedatectl
VERSION=0.1.0
TZ=$2
SCRIPT_NAME=$(echo ${0##*/})
DEBUG=0

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
      err_report "File not found: ${filename}"      
      exit 1
    fi

    debugger "($SCRIPT_NAME) File exists."
}

# return current timezone info
get_tz() {

    check_file_exists $TIMEDATECTL

    debugger "Getting TZ value..."

    # get TZ (note that if fails, $tz contains error output)
    tz=$($TIMEDATECTL | grep zone | awk '{print $3}'  2>&1)
    if [ "$?" != '0' ]; then
        err_report "Error getting TZ: $tz"
        exit 1
    else
        debugger "Got TZ: $tz"
        echo $tz
        exit 0
    fi
}

# set timezone
set_tz() {

    check_file_exists $TIMEDATECTL

    debugger "Setting timezone..."

    if [ -z "$TZ" ]; then
       err_report "No timezone passed to : set_timezone()"
       exit 1
    fi
    
    # set the timezone
    err_msg=$($TIMEDATECTL set-timezone $TZ 2>&1)

    if [ "$?" != '0' ]; then
        err_report "Error setting timezone: $err_msg"
        exit 1
    else
        debugger "Updated TZ"
        exit 0
    fi
}

# list timezones available
list() {

    check_file_exists $TIMEDATECTL

    debugger "Getting TZ list..."

    # get TZ list (note that if fails, $tz contains error output)
    tz_list=$($TIMEDATECTL list-timezones  2>&1)
    if [ "$?" != '0' ]; then
        err_report "Error getting TZ list: $tz"
        exit 1
    else
        debugger "Got TZ List: $tz"
        echo "$tz_list"
        exit 0
    fi
}

# return help string that provides short-form overview
# of this command
help () {
    echo "Get or set the device timezone and list all timezones"
}

# usage output
usage () {
        echo "Usage: timezone {-v | get | set | list | help}"
        echo ""
        echo "  wlanpi-timezone.sh -v : show script version"
        echo "  wlanpi-timezone.sh get: show current reg domain"
        echo "  wlanpi-timezone.sh set [api str]: set reg domain"
        echo "  wlanpi-timezone.sh list : get all available timezones"
        echo "  wlanpi-timezone.sh : show usage info"
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
        get_tz
        ;;
  set)
        set_tz
        ;;
  list)
        list
        ;;
  help)
        help
        ;;
  *)
        usage
        ;;
esac

exit 0
