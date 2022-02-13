#!/usr/bin/env bash

# Script to import user's public key stored on github for password-less 
# access to a WLAN Pi
#
# Author : Nigel Bowden
#
# This script uses the ssh-import-id-gh command to import a user#s public
# key from their guthub account. An intercative CLI interface is provided
# for convenience
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

IMPORT_CMD=/usr/bin/ssh-import-id-gh
GITHUB_USERNAME=$2

# usage output
usage () {
        echo "Usage: wlanpi-gh-ssh-key [ gh_username ]"
        echo ""
        echo "  wlanpi-gh-ssh-key <gh_username> : import key for GitHub username provided"
        echo "  wlanpi-gh-ssh-key -i            : run interactive mode"
        echo "  wlanpi-gh-ssh-key -h            : show usage info"
        echo ""
        exit 0

}

get_username () {

    clear
    cat <<INTRO
#####################################################

           WLANPi GitHub SSH Key Import

This utility will import your public key from GitHub
to allow you SSH access to your WLAN Pi without having
to enter a username/password for each SSH session.

Before you can use this utility, you must set up your
public key on GitHub.

For more information on creating a public key on
GitHub, please visit the following link:

https://docs.github.com/en/authentication/connecting-to-github-with-ssh/adding-a-new-ssh-key-to-your-github-account

##################################################### 
INTRO

    read -p "Do you wish to continue? (y/n) : " yn

    if [[ ! $yn =~ [yY] ]]; then
        echo "OK, exiting."
        exit 1
    fi

    sleep 1
    read -p "Enter your github username : " GITHUB_USERNAME
   
    echo "Importing key..."

    if `$IMPORT_CMD $GITHUB_USERNAME`; then
      echo "Key imported."
    else
      echo "Key import failed. Check username is valid and a public key exists & try again."
      exit 1
    fi

    return
}

# case statements
case "$1" in
  -i)
        get_username
        ;;
  -h)
        usage
        ;;
  *)
        if [ "$1" == "" ]; then 
          echo "No username entered"
          usage
          exit1
        fi
        `$IMPORT_CMD $1`
        ;;
esac

exit 0
