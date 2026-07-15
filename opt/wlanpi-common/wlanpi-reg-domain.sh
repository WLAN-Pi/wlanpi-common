#!/usr/bin/env bash

# Script to get/set reg domain and country code on WLAN Pi Pro
# Author : Nigel Bowden
#
# This script gets/sets the Wi-Fi regulatory domain using the cfg80211
# kernel subsystem (via iw). crda and its /etc/default/crda config file
# were removed in Debian bookworm, so the domain is now:
#   - applied immediately with "iw reg set XX"
#   - persisted across reboots via a cfg80211 module option in
#     /etc/modprobe.d, which the kernel applies when cfg80211 loads
# The matching country_code is also written into any installed hostapd
# mode configs (Hotspot / Wi-Fi Console / Server).
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

# Define ANSI colour codes
ORANGE='\033[0;33m'
RED='\033[0;31m'
GREEN='\033[0;32m'
NO_COLOUR='\033[0m'

# Persist the domain via a cfg80211 module option. cfg80211 reads
# ieee80211_regdom when it loads, which replaces the old crda mechanism.
REGDOMAIN_MODPROBE_FILE="/etc/modprobe.d/wlanpi-regdomain.conf"
HOTSPOT_FILE="/etc/wlanpi-hotspot/conf/hostapd.conf"
WCONSOLE_FILE="/etc/wlanpi-wconsole/conf/hostapd.conf"
SERVER_FILE="/etc/wlanpi-server/conf/hostapd.conf"
VERSION=0.2.0
DOMAIN=$2
NO_PROMPT=$3
SCRIPT_NAME=$(echo ${0##*/})
DEBUG=0

# just in case we need to debug this script:
debugger() {
    if [ "$DEBUG" != '0' ];then
      echo $1
    fi
}

err_report() {
    err_str="$1"

    echo "Error: $err_str"
    logger "($SCRIPT_NAME) $err_str - Error!"
    debugger "($SCRIPT_NAME) $err_str - Error!"

    return 0
}

# return the currently active regulatory domain from cfg80211
get_domain () {

    if ! command -v iw >/dev/null 2>&1; then
        err_report "iw command not found; cannot read regulatory domain"
        exit 1
    fi

    # "iw reg get" prints the global self-managed domain first, e.g.:
    #   global
    #   country US: DFS-FCC
    # An unconfigured system reports "country 00" (the world domain).
    debugger "Getting reg domain current value via iw..."
    current_domain=$(iw reg get 2>/dev/null | awk '/^country/ {print $2; exit}' | tr -d ':')

    if [ -z "$current_domain" ] || [ "$current_domain" = "00" ]; then
        debugger "No reg domain configured yet."
        echo "No reg domain configured yet. Configure one using \"sudo wlanpi-reg-domain set XX\", where XX represents the country code."
        exit 0
    else
        debugger "Got reg domain: $current_domain"
        echo "$current_domain"
        exit 0
    fi
}

# poll until the running regulatory domain matches the requested one.
# "iw reg set" is asynchronous, and the kernel silently ignores a country
# code that wireless-regdb has no rules for (leaving reg at "00"), so this
# is how we confirm the change actually took effect.
wait_for_domain () {
    want="$1"
    tries=0
    while [ "$tries" -lt 10 ]; do
        got=$(iw reg get 2>/dev/null | awk '/^country/ {print $2; exit}' | tr -d ':')
        if [ "$got" = "$want" ]; then
            return 0
        fi
        tries=$((tries + 1))
        sleep 0.2
    done
    return 1
}

# handle privilege escalation for set operations
handle_privileges() {
    if [[ $EUID -ne 0 ]]; then
        case "$1" in
            set)
                echo "Setting the regulatory domain requires elevated privileges."
                exec sudo "$0" "$@"
                ;;
        esac
    fi
}

# update the hostapd country_code for an installed mode, if present
update_hostapd_country () {
    conf_file="$1"
    mode_name="$2"

    # Mode packages are optional; only touch a config that is installed.
    if [ ! -e "$conf_file" ]; then
        debugger "Skipping $mode_name; $conf_file not present."
        return 0
    fi

    debugger "Setting country code for $mode_name: $conf_file"
    if ! sed -i "s/country_code=.*/country_code=$DOMAIN/" "$conf_file"; then
        err_report "Error adding country code to $conf_file"
        exit 1
    fi
    debugger "Added country code $DOMAIN to $conf_file"
}

# set the regulatory domain
set_domain () {

    if [ -z "$DOMAIN" ]; then
       err_report "No country code provided"
       exit 1
    fi

    # ensure domain is uppercase
    DOMAIN="${DOMAIN^^}"

    # validate: an ISO 3166-1 alpha-2 country code (two letters)
    if ! [[ "$DOMAIN" =~ ^[A-Z]{2}$ ]]; then
        err_report "Invalid country code: '$DOMAIN' (expected two letters, e.g. US, GB, DE)"
        exit 1
    fi

    if ! command -v iw >/dev/null 2>&1; then
        err_report "iw command not found; cannot set regulatory domain"
        exit 1
    fi

    # apply immediately to the running system
    debugger "Applying reg domain via iw: $DOMAIN"
    if ! iw reg set "$DOMAIN"; then
        err_report "Failed to submit regulatory domain $DOMAIN via iw"
        exit 1
    fi

    # confirm the kernel actually accepted the code before persisting anything,
    # so we never leave a bogus value in the config that "sticks" on reboot
    if ! wait_for_domain "$DOMAIN"; then
        err_report "Regulatory domain did not apply as $DOMAIN; it may not exist in wireless-regdb. Nothing was changed."
        exit 1
    fi

    # persist across reboots via the cfg80211 module option (replaces crda)
    debugger "Persisting reg domain to $REGDOMAIN_MODPROBE_FILE"
    if ! echo "options cfg80211 ieee80211_regdom=$DOMAIN" > "$REGDOMAIN_MODPROBE_FILE"; then
        err_report "Error writing $REGDOMAIN_MODPROBE_FILE"
        exit 1
    fi

    # set the matching country code in any installed hostapd mode configs
    update_hostapd_country "$HOTSPOT_FILE" "Hotspot mode"
    update_hostapd_country "$WCONSOLE_FILE" "Wi-Fi Console mode"
    update_hostapd_country "$SERVER_FILE" "Server mode"

    if ! grep -q "classic" /etc/wlanpi-state; then
        echo "Please switch your WLAN Pi to the Classic mode for the Hotspot and Wi-Fi Console new country code to take effect."
    fi

    # only show reboot prompt in interactive mode (when --no-prompt was not used)
    if [ "$NO_PROMPT" != "--no-prompt" ]; then
        while true; do
            read -p "A reboot is required. Reboot now? (Y/n) " yn
            case $yn in
                [yY]|"" ) reboot;
                    break;;
                [nN] ) echo -e "${RED}Warning: Wi-Fi might not work fully until you reboot!${NO_COLOUR}";
                       exit 0;;
                * ) echo "Error: Invalid response";;
            esac
        done
    fi
}

# usage output
usage () {
        echo "Gets or sets the Wi-Fi RF regulatory domain"
        echo ""
        echo "Usage: wlanpi-reg-domain {get | set | -h | --help | -v}"
        echo ""
        echo "Options:"
        echo "  get           Shows current reg domain"
        echo "  set DOMAIN    Sets RF regulatory domain"
        echo "  -h            Shows usage info"
        echo "  --help        Shows usage info"
        echo "  -v            Shows script version"
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
        get_domain
        ;;
  set)
        handle_privileges "set"
        set_domain
        ;;
  -h|--help|help|"")
        usage
        ;;
  *)
        echo "Error: Invalid option"
        exit 1
        ;;
esac

exit 0
