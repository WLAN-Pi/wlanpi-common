#!/bin/bash

# Updates the WLAN Pi software and packages

# Author: Jiri Brejcha, jirka@jiribrejcha.net, @jiribrejcha

# Check if the script is running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must run as root. Add \"sudo\" please".
   exit 1
fi

# Upgrade packages
sudo apt update && sudo apt upgrade
