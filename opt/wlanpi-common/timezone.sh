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
DEBUG=0

# just in case we need to debug this script:
debugger() {
    if [ "$DEBUG" != '0' ];then
      echo $1
    fi
}

# check if config file exists
check_file_exists() {

    debugger "Checking timedatectl file exists where we expect to find it..."

    if [ ! -e "${TIMEDATECTL}" ] ; then
      err_str="timedatectl file not found: ${REG_DOMAIN_FILE}"
      echo $err_string
      logger $err_string
      exit 1
    fi

    debugger "File exists."
}

# return current timezone info
get() {

    check_file_exists

    debugger "Getting TZ value..."

    # get TZ (note that if fails, $tz contains error output)
    tz=$(timedatectl | grep zone | awk '{print $3}'  2>&1)
    if [ "$?" != '0' ]; then
        err_string="Error getting TZ: $tz"
        echo $err_string
        logger $err_string
        exit 1
    else
        debugger "Got TZ: $tz"
        echo $tz
        exit 0
    fi
}

# set domain in reg domain file
set() {

    check_file_exists

    debugger "Setting timezone..."
    
    # set the timezone
    err_msg=$(timedatectl set-timezone $TZ 2>&1)

    if [ "$?" != '0' ]; then
        err_string="Error setting timezone: $err_msg"
        echo "$err_string"
        logger $err_string
        exit 1
    else
        debugger "Updated TZ"
        exit 0
    fi
}

# list timezones available
list() {

    check_file_exists

    debugger "Getting TZ list..."

    # get TZ list (note that if fails, $tz contains error output)
    tz_list=$(timedatectl list-timezones | grep .  2>&1)
    if [ "$?" != '0' ]; then
        err_string="Error getting TZ list: $tz"
        echo $err_string
        logger $err_string
        exit 1
    else
        debugger "Got TZ List: $tz"
        echo $tz_list
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
        echo "  timezone -v : show script version"
        echo "  timezone get: show current reg domain"
        echo "  timezone set [api str]: set reg domain"
        echo "  timezone list : get all available timezones"
        echo "  timezone : show usage info"
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
