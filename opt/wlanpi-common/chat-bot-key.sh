#!/usr/bin/env bash

# Script to get/set wlanpi-chat-bot API key
# Author : Nigel Bowden
#
# This script is used to manipulate and report the 
# API key of the wlanpi-chat-bot feature.
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

CHAT_BOT_ROOT=/opt/wlanpi-chat-bot
CONFIG_FILE=$CHAT_BOT_ROOT/etc/config.json
VERSION=0.1.0
API_KEY=$2
DEBUG=0

# just in case we need to debug this script:
debugger() {
    if [ "$DEBUG" != '0' ];then
      echo $1
    fi
}

# check if config file exists
check_file_exists() {

    debugger "Checking config file exists..."

    if [ ! -e "${CONFIG_FILE}" ] ; then
      err_str="Chat-bot config file not found: ${CONFIG_FILE}"
      echo $err_string
      logger $err_string
      exit 1
    fi

    debugger "File exists."
}

# return current API key value from chat bot config file
get() {

    check_file_exists

    # target field: "bot_token": "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
    debugger "Getting token current value..."
    api_key=$(cat $CONFIG_FILE | grep bot_token | awk -F'"' '{print $4}')
    if [ "$?" != '0' ]; then
        err_string="Error extracting chat-bot API key from $CONFIG_FILE"
        echo $err_string
        logger $err_string
        exit 1
    else
        debugger "Got token value: $api_key"
        echo $api_key
        exit 0
    fi
}

# set API key value for chat bot in config file
set() {

    check_file_exists

    debugger "Setting API key in file: $CONFIG_FILE"
    
    # set the new key in the chat bot config file
     sed -i "s/\"bot_token\":\s*\".*\"\s*,/\"bot_token\": \"$API_KEY\",/" "$CONFIG_FILE"

    if [ "$?" != '0' ]; then
        err_string="Error adding chat-bot API key to $CONFIG_FILE"
        echo $err_string
        logger $err_string
        exit 1
    else
        debugger "Added token value: $API_KEY"
        exit 0
    fi
}

# return help string that provides short-form overview
# of this command
help () {
    echo "Get or set the API key for your chat-bot"
}

# usage output
usage () {
        echo "Usage: chat-bot-key.sh {-v | get | set | help}"
        echo ""
        echo "  chat-bot-key.sh -v : show script version"
        echo "  chat-bot-key.sh get: show current API key"
        echo "  chat-bot-key.sh set [api str]: set API key"
        echo "  chat-bot-key.sh : show usage info"
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
