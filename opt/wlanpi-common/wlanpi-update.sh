#!/bin/bash
#
# Updates the WLAN Pi software and packages
#
# Authors: Jiri Brejcha, jirka@jiribrejcha.net, @jiribrejcha
#          Adrian Granados, adrian@intuitibits.com, @adriangranados
#

WLAN_PI_PACKAGES='wlanpi-|iw|scandump'

number_of_upgradeable () {
    sudo apt update >/dev/null 2>&1 && sudo apt list --upgradeable 2>/dev/null | grep -c -E "$WLAN_PI_PACKAGES" && exit 0
}


image_upgrade_check () {
    LATEST_IMAGE=$(curl -s -i 'https://github.com/WLAN-Pi/pi-gen/releases/latest' | grep 'location' | grep -oP 'v\K\d+\.\d+\.\d+\b')
    CURRENT_IMAGE=$(grep -oP 'VERSION=\K\d+\.\d+\.\d+' /etc/wlanpi-release)
    echo "Current image: $CURRENT_IMAGE"
    echo "Latest image: $LATEST_IMAGE"


    # Split versions into arrays
    IFS='.' read -r -a latest_parts <<< "$LATEST_IMAGE"
    IFS='.' read -r -a current_parts <<< "$CURRENT_IMAGE"

    # Compare each component of the versions
    for i in {0..2}; do
        if (( "${latest_parts[$i]:-0}" > "${current_parts[$i]:-0}" )); then
            echo "New software image is available for download"
            exit 0
        elif (( "${latest_parts[$i]:-0}" < "${current_parts[$i]:-0}" )); then
            echo "You are running a bleeding edge release"
            exit 0
        fi
    done
    echo "You are running the latest stable release"
}

list_upgradeable_wlanpi () {
    echo "Checking for updates ..."
    updates=`sudo apt update 2>&1`
    if echo $updates | grep --quiet -E "Err|Fail"; then
        echo "Error: Failed to check for available updates"
        exit 1
    else
        sudo apt list --upgradeable 2>/dev/null | grep "upgradable" | grep -E "$WLAN_PI_PACKAGES" || { echo "All WLAN Pi packages are up-to-date"; exit 0; }

        while true; do
            read -p "Do you want to upgrade all of the above WLAN Pi packages? (Y/n) " yn
            case $yn in
	        [yY] | "" ) upgrade_wlanpi;
                    break;;
                [nN] ) echo "Exiting ...";
                    exit 0;;
                * ) echo "Error: Invalid response";;
            esac
         done

    fi
}

upgrade_all () {
    echo "Checking for updates ..."
    sudo apt update
    echo "Upgrading all packages ..."
    sudo apt -y upgrade
}

upgrade_wlanpi () {
    sudo apt -y --only-upgrade install "wlanpi-*" iw scandump
}

usage () {
    echo "Usage: wlanpi-update {-a | -h | -u | no option}"
    echo ""
    echo "Options:"
    echo "  -a            Upgrades all packages including WLAN Pi and non-WLAN Pi ones"
    echo "  -h or --help  Shows this usage info"
    echo "  -u            Upgrades WLAN Pi only packages"
    echo "  -c            Returns number of upgradeable WLAN Pi packages"
    echo "  -i            Checks if there is a newer WLAN Pi image available for download"
    echo "  no option     Upgrades WLAN Pi only packages"
    echo ""
    exit 0
}

case "$1" in
    ""|-u)
        list_upgradeable_wlanpi
        ;;
    -a)
        upgrade_all
        ;;
    -c)
        number_of_upgradeable
        ;;
    -h|--help)
        usage
        ;;
    -i)
        image_upgrade_check
        ;;
    *)
        echo "Error: Invalid option"
        exit 1
        ;;
esac

exit 0