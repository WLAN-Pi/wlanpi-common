#!/bin/bash
#
# Updates the WLAN Pi software and packages
#
# Authors: Jiri Brejcha, jirka@jiribrejcha.net, @jiribrejcha
#          Adrian Granados, adrian@intuitibits.com, @adriangranados
#

upgradable_wlanpi () {
    echo "Checking for updates ..."
    updates=`sudo apt update 2>&1`
    if echo $updates | grep --quiet -E "Err|Fail"; then
        error "Error: Failed to check for available updates"
        exit 1
    else
        sudo apt list --upgradable 2>/dev/null | grep upgradable | grep "wlanpi-" || { echo "All WLAN Pi packages are up-to-date"; exit 0; }

        while true; do
            read -p "Do you want to upgrade all of the above WLAN Pi packages? (y/n) " yn
            case $yn in
	        [yY] ) upgrade_wlanpi;
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
    sudo apt -y --only-upgrade install wlanpi-*
}

usage () {
    echo "Usage: wlanpi-update {-a | -h | -u | no option}"
    echo ""
    echo "Options:"
    echo "  -a            Upgrades all packages including WLAN Pi and non-WLAN Pi ones"
    echo "  -h or --help  Shows this usage info"
    echo "  -u            Upgrades WLAN Pi only packages"
    echo "  no option     Upgrades WLAN Pi only packages"
    echo ""
    exit 0
}

case "$1" in
    ""|-u)
        upgradable_wlanpi
        ;;
    -a)
        upgrade_all
        ;;
    -h|--help)
        usage
        ;;
    *)
        echo "Error: Invalid option"
        exit 1
        ;;
esac

exit 0