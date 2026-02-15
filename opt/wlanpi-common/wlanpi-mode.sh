#!/usr/bin/env bash

# Script to get/set WLAN Pi mode
# Author : Nigel Bowden
#
# This script is uses the following scripts to change modes
#  - /opt/wlanpi-hotspot/hotspot_switcher
#  - /opt/wlanpi-hotspot/server_switcher
#
# To get the current mode, the followign file is read:
#  - /etc/wlanpi-state
#
# States available:
#  - classic
#  - hotspot
#  - server
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

DEBUG=0
STATUS_FILE="/etc/wlanpi-state"
MODE=""
SCRIPT_NAME=$(echo ${0##*/})

HOTSPOT_SWITCHER="/opt/wlanpi-hotspot/hotspot_switcher"
SERVER_SWITCHER="/opt/wlanpi-server/server_switcher"
CONFIRM_REQ=$3

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
      err_report "File not found: ${filename}"
      exit 1
    fi

    debugger "($SCRIPT_NAME) File exists."
}

check_yn() {

    if [ "$CONFIRM_REQ" == "-q" ]; then
        return
    fi
    
    read -p "* The WLAN Pi will now reboot and switch modes. Do you wish to continue? (y/n) : " yn

    if [[ $yn =~ [yY] ]]; then
        echo "* OK, proceeding with mode switch."
    else
        echo "* OK, mode switch terminated."
        exit 1
    fi
}

# get current mode
get_current_mode() {

    if [ -f "$STATUS_FILE" ]; then
        # read mode file
        MODE=$(cat $STATUS_FILE | head -n 1 | xargs)
    else
        err_report "* Unable to find mode status file. Exiting."
        exit 1
    fi
}

# CLI commands
get_mode() {
    get_current_mode
    echo "* Current mode: $MODE"
}

set_mode() {

    # check we have one arg passed
    if [ $# -eq 0 ]; then
        err_report "* This command requires the required mode as an argument."
        exit 1
    fi

    NEW_MODE=$1

    # check new mode is valid
    if [[ ! $NEW_MODE =~ (classic|hotspot|server) ]]; then
        echo "* Invalid mode requested : $NEW_MODE"
        exit 1
    fi

    # get current mode (sets $MODE)
    get_current_mode

    # check if we're already in the requested mode
    if [ "$MODE" == "$NEW_MODE" ]; then
        echo "* Already in $MODE mode."
        exit 1
    fi

    # if not in classic mode, check that requested mode is classic mode
    if [ "$MODE" != "classic" ] && [ "$NEW_MODE" != "classic" ]; then
        echo "* Must switch to classic mode before switching to $NEW_MODE mode. (current mode: $MODE)"
        exit 1
    fi

    case "$NEW_MODE" in 
    hotspot)
            echo "* Switching from classic to hotspot mode"
            check_yn
            `$HOTSPOT_SWITCHER on`
            ;;
    server)
            echo "* Switching from classic to server mode"
            check_yn
            `$SERVER_SWITCHER on`
            ;;
    classic)
            case "$MODE" in
            hotspot)
                    echo "* Switching from hotspot to classic mode";
                    check_yn;
                    `$HOTSPOT_SWITCHER off`
                    ;;
            server)
                    echo "* Switching from server to classic mode";
                    check_yn;
                    `$SERVER_SWITCHER off`
                    ;;
            classic)
                    echo "* Already in classic mode."
                    ;;
            esac
            ;;
    *)
        usage
        ;;   
    esac
    }                   


# usage output
usage () {
        echo "Usage: wlanpi-mode.sh { get | set | help }"
        echo ""
        echo "  wlanpi-mode.sh get: show current mode"
        echo "  wlanpi-mode.sh set [ classic | hotspot | server ]"
        echo "  wlanpi-mode.sh set [ classic | hotspot | server ] [ -q ] (quiet switch)"
        echo "  wlanpi-mode.sh : show usage info"
        echo ""
        exit 0

}

debugger "--- Debug on ---"

# case statements
case "$1" in
  get)
        get_mode
        ;;
  set)
        set_mode $2
        ;;
  help)
        usage
        ;;
  *)
        usage
        ;;
esac

exit 0