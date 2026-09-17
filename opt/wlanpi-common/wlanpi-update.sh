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


RELEASE_URL='https://github.com/WLAN-Pi/pi-gen/releases/latest'

# Normalize a version string so it can be compared with dpkg --compare-versions:
# - strip a leading "v" (old semver tags: v3.4.4)
# - strip a trailing "-CODENAME" (calver tags: 26.02-Cortado, 26.08-dev.5-Cortado)
# - map prerelease markers so dev < rc < final (Debian ~ ordering)
# Emits nothing if the result is not a valid version.
normalize_version () {
    local v=$1
    v=${v#v}
    v=${v%-[A-Za-z]*}
    v=${v/-dev./~dev.}
    v=${v/-rc./~rc.}
    if [[ "$v" =~ ^[0-9]+(\.[0-9]+)*((~dev|~rc)\.[0-9]+)?$ ]]; then
        echo "$v"
    fi
}

# Echo the update status for a latest/current version pair (both normalized)
image_upgrade_status () {
    local latest=$1
    local current=$2
    if dpkg --compare-versions "$latest" gt "$current"; then
        echo "New software image is available for download"
    elif dpkg --compare-versions "$latest" lt "$current"; then
        echo "You are running a bleeding edge release"
    else
        echo "You are running the latest stable release"
    fi
}

image_upgrade_check () {
    LATEST_TAG=$(curl --max-time 10 -s -o /dev/null -w '%{redirect_url}' "$RELEASE_URL")
    LATEST_TAG=${LATEST_TAG##*/}
    if [ -z "$LATEST_TAG" ]; then
        echo "Error: Unable to check for new software image"
        return 1
    fi

    CURRENT_IMAGE=$(grep '^VERSION=' /etc/wlanpi-release | head -n1 | cut -d= -f2-)
    if [ -z "$CURRENT_IMAGE" ]; then
        echo "Error: Unable to read current image version"
        return 1
    fi

    LATEST_VERSION=$(normalize_version "$LATEST_TAG")
    CURRENT_VERSION=$(normalize_version "$CURRENT_IMAGE")
    if [ -z "$LATEST_VERSION" ] || [ -z "$CURRENT_VERSION" ]; then
        echo "Error: Invalid image version"
        return 1
    fi

    echo "Current image: $CURRENT_IMAGE"
    echo "Latest image: ${LATEST_TAG#v}"
    image_upgrade_status "$LATEST_VERSION" "$CURRENT_VERSION"
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

# Run the CLI only when executed directly, so the script can be sourced by tests
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
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
            exit $?
            ;;
        *)
            echo "Error: Invalid option"
            exit 1
            ;;
    esac

    exit 0
fi
