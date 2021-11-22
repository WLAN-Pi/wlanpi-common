#!/usr/bin/env bash

# Script to get/set WLAN Pi Pro hostname
# Author : Nigel Bowden
#
# This script is uses the following linux commands
# to get and set the hostname:
#
#  - /usr/bin/hostnamectl set-hostname <hostname> (sets the hostname in /etc/hostname)
#  - /usr/bin/hostname (gets current hostname)
#  - sed -i 's/oldname/newname/g' /etc/hosts
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

HOSTNAME_SCRIPT=/usr/bin/hostname
HOSTNAMECTL_SCRIPT=/usr/bin/hostnamectl
HOSTS_FILE=/etc/hosts
SCRIPT_NAME=$(echo ${0##*/})
VERSION=0.1.0
HOSTNAME=$2
DEBUG=0

# just in case we need to debug this script:
debugger() {
    if [ "$DEBUG" != '0' ];then
      echo $1
    fi
}

# check if config file exists
check_file_exists() {

    debugger "($SCRIPT_NAME) Checking file exists: $1"

    filename=$1

    if [ ! -e "${filename}" ] ; then
      err_str="($SCRIPT_NAME) File not found: ${filenme}"
      echo $err_string
      logger $err_string
      exit 1
    fi

    debugger "($SCRIPT_NAME) File exists."
}

# return current API key value from chat bot config file
get_hostname() {

    # check we have correct hostname script filename
    check_file_exists $HOSTNAME_SCRIPT

    debugger "($SCRIPT_NAME) Getting hostname..."
    hostname=$($HOSTNAME_SCRIPT 2>&1)
    if [ "$?" != '0' ]; then
        err_string="($SCRIPT_NAME) Hostname command failed: $hostname"
        echo $err_string
        logger $err_string
        exit 1
    else
        debugger "($SCRIPT_NAME) Hostname value: $hostname"
        echo $hostname
        exit 0
    fi
}

# set API key value for chat bot in config file
set_hostname() {

    new_hostname=$HOSTNAME
    current_hostname=$($HOSTNAME_SCRIPT)

    # check we have correct hostnamectl script filename
    check_file_exists $HOSTNAMECTL_SCRIPT

    # check we have correct hosts filename
    check_file_exists $HOSTS_FILE

    debugger "($SCRIPT_NAME) Setting hostname with hostname ctl cmd to: $new_hostname"
    debugger "($SCRIPT_NAME) Current hostname: $current_hostname"
    debugger "($SCRIPT_NAME) New hostname: $new_hostname"

    # set hostname in /etc/hostname with hostnamectl commmand
    err=$($HOSTNAMECTL_SCRIPT set-hostname $new_hostname 2>&1)
    if [ "$?" != '0' ]; then
        err_string="($SCRIPT_NAME) Hostname set command failed: $err"
        debugger "$err_string"
        logger $err_string
        exit 1
    else
        debugger "($SCRIPT_NAME) Set hostname with hostnamectl to : $new_hostname"
    fi

    debugger "($SCRIPT_NAME) Setting hostname in file $HOSTS_FILE"
    

    # substitue the existing hostname in /etc/hosts (if it exists)
    sed -i "s/${current_hostname}/${new_hostname}/g" $HOSTS_FILE
    
    if [ "$?" != '0' ]; then
        err_string="($SCRIPT_NAME) Error updating hostname in $HOSTS_FILE"
        echo $err_string
        logger $err_string
        exit 1
    else
        debugger "($SCRIPT_NAME) Swapped out hostname OK in $HOSTS_FILE to : $new_hostname"
    fi

    debugger "($SCRIPT_NAME) Hostname set OK"
    exit 0
}

# return help string that provides short-form overview
# of this command
help () {
    echo "Get or set the hostname of a WLAN Pi Pro"
}

# usage output
usage () {
        echo "Usage: hostname.sh {-v | get | set | help}"
        echo ""
        echo "  hostname.sh -v : show current script version"
        echo "  hostname.sh get: show current hostname"
        echo "  hostname.sh set [hostname_str]: set hostname"
        echo "  hostname.sh : show usage info"
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
        get_hostname
        ;;
  set)
        set_hostname
        ;;
  help)
        help
        ;;
  *)
        usage
        ;;
esac

exit 0
