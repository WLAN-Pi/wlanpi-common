#!/bin/bash

# Author: Jiri Brejcha
# This script is only used by WLAN Pi development team. You have been warned!

# Define ANSI colour codes
ORANGE='\033[0;33m'
RED='\033[0;31m'
GREEN='\033[0;32m'
NO_COLOUR='\033[0m'

usage() {
    echo "Usage: $0 [-option] [parameter]"
    echo
    echo "Options:"
    echo "  -a           Performs apt update and apt upgrade of all packages"
    echo "  -d           Adds WLAN Pi packagecloud/dev repository"
    echo "  -l           Lists all installed WLAN Pi packages and their versions"
    echo "  -u PARAM     Uninstalls completely a specified package and all files (more than apt purge)"
    echo "  -f PARAM     Watch live contents changes of a file"
    echo "  -s PARAM     Watch live service log"
    echo "  -h           Display this help message"
    echo
    echo -e "${RED}Warning: This script is only used by WLAN Pi development team!${NO_COLOUR}"
    echo
  exit 1
}

add_packagecloud_dev(){
    curl -s "https://packagecloud.io/install/repositories/wlanpi/dev/script.deb.sh" | sudo bash
}

watch_service_log() {
    # Check if service is running
    if ! systemctl is-active --quiet "$1"; then
        echo "Service is not running."
        return 1
    fi
    journalctl -u "$1" -f
}

watch_file_contents(){
    file_to_watch="$1"
    if [[ ! -f "$file_to_watch" ]]; then
        echo "File does not exist: $file_to_watch"
        exit 1
    fi
    # Start tailing the file with the -F (follow) option
    tail -F "$file_to_watch" | while read -r line; do
        echo "$line"
        # Add additional processing here if needed
    done
}

upgrade_all_packages(){
    sudo apt update && sudo apt upgrade -y
}

list_wlanpi_packages(){
    sudo apt list --installed | grep "wlanpi"
}

purge_grafana(){
    sudo service grafana-server.service stop
    sudo apt purge wlanpi-grafana
    sudo apt purge grafana
    sudo rm -r /opt/wlanpi-grafana/
    sudo rm -r /etc/wlanpi-grafana/
    sudo rm -r /var/lib/grafana/
}

build_package(){
    sudo dpkg-buildpackage -us -uc
}

# Parse command line arguments
while getopts ":ab:s:f:dluh" opt; do
  case $opt in
    a)
      # Handle option -a
      upgrade_all_packages
     ;;
    b)
      # Handle option -b
      build_package
      ;;
    d)
      # Add packagecloud/dev repo
      add_packagecloud_dev
      ;;
    l)
      # Handle option -l
      list_wlanpi_packages
      ;;
    h)
      # Display usage information and exit
      usage
      ;;
    s)
      # Watch service log
      watch_service_log "$OPTARG"
      ;;
    f)
      # Watch file contents
      watch_file_contents "$OPTARG"
      ;;
    \?)
      # Handle invalid options
      echo "Invalid option: -$OPTARG"
      exit 1
      ;;
    :)
      # Handle options that require parameters
      echo "Option -$OPTARG requires a parameter."
      exit 1
      ;;
  esac
done

# Check if no options were set, then execute usage function
if [ "$OPTIND" -eq 1 ]; then
  usage
fi

# Shift command line arguments so that non-option arguments can be processed
shift $((OPTIND-1))

# Process non-option arguments here (if any)

# Example: Print remaining arguments
if [ $# -gt 0 ]; then
  echo "Non-option arguments:"
  for arg in "$@"; do
    echo "$arg"
  done
fi
