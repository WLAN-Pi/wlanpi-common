#!/usr/bin/env bash

# Script to get/set WLAN Pi Pro hostname
# Author : Nigel Bowden
#
# This script is uses the following linux commands
# to get and set the hostname:
#
#  - /usr/bin/hostnamectl set-hostname <hostname> (sets the hostname in /etc/hostname)
#  - /usr/bin/hostname (gets current hostname)
#  - awk to update the 127.0.1.1 line of /etc/hosts
#  - /usr/bin/systemctl restart avahi-daemon (for new hostname to take effect)
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
SYSTEMCTL_SCRIPT=/usr/bin/systemctl
HOSTS_FILE=/etc/hosts
SCRIPT_NAME=$(echo ${0##*/})
VERSION=0.1.0
HOSTNAME=$2
DEBUG=0

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

# return current API key value from chat bot config file
get_hostname() {

    # check we have correct hostname script filename
    check_file_exists $HOSTNAME_SCRIPT

    debugger "($SCRIPT_NAME) Getting hostname..."
    hostname=$($HOSTNAME_SCRIPT 2>&1)
    if [ "$?" != '0' ]; then
        err_report "Hostname command failed: $hostname"
        exit 1
    else
        debugger "($SCRIPT_NAME) Hostname value: $hostname"
        echo $hostname
        exit 0
    fi
}

# Succeed if a 127.0.1.1 line in /etc/hosts lists $1 as a name (not in a comment).
hosts_maps() {
    NAME=$1 awk '/^[ \t]*127\.0\.1\.1([ \t#]|$)/ { sub(/#.*/, "")
        for (i = 2; i <= NF; i++) if ($i == ENVIRON["NAME"]) found = 1 }
        END { exit !found }' "$HOSTS_FILE"
}

# Point 127.0.1.1 in /etc/hosts at the new hostname. Only 127.0.1.1 lines are
# edited, names are compared whole and outside comments, other names on the
# line are kept, and the file is only replaced (atomically) when it changes:
#   1. a 127.0.1.1 line already lists the new name: no change
#   2. rename: replace the old name, and old.domain with new.domain
#   3. stale line (e.g. an interrupted rename): replace its first name
#   4. no 127.0.1.1 line: append one
sync_hosts() {
    local old=$1 new=$2 tmp

    if ! tmp=$(mktemp "$HOSTS_FILE.XXXXXX"); then
        err_report "Cannot create a temporary file next to $HOSTS_FILE"
        exit 1
    fi
    if ! OLD=$old NEW=$new awk '
        function parse(line,    c, rest) {
            c = index(line, "#")
            comment = c ? substr(line, c) : ""
            rest = c ? substr(line, 1, c - 1) : line
            n = 0
            while (match(rest, /[^ \t]+/)) {
                sep[n] = substr(rest, 1, RSTART - 1)
                tok[n++] = substr(rest, RSTART, RLENGTH)
                rest = substr(rest, RSTART + RLENGTH)
            }
            trail = rest
        }
        function build(    k, s) {
            for (k = 0; k < n; k++) s = s sep[k] tok[k]
            return s trail comment
        }
        { L[NR] = $0 }
        /^[ \t]*127\.0\.1\.1([ \t#]|$)/ { ip[++nip] = NR }
        END {
            old = ENVIRON["OLD"]; new = ENVIRON["NEW"]
            for (j = 1; j <= nip; j++) {
                parse(L[ip[j]])
                for (k = 1; k < n; k++) if (tok[k] == new) have = 1
            }
            if (!have && old != "" && old != new) {
                for (j = 1; j <= nip; j++) {
                    parse(L[ip[j]]); changed = 0
                    for (k = 1; k < n; k++) {
                        if (tok[k] == old) { tok[k] = new; changed = have = 1 }
                        else if (index(tok[k], old ".") == 1) {
                            tok[k] = new substr(tok[k], length(old) + 1); changed = 1
                        }
                    }
                    if (changed) L[ip[j]] = build()
                }
            }
            if (!have && nip) {
                parse(L[ip[1]])
                if (n < 2) { sep[1] = "\t\t"; tok[1] = new; n = 2 }
                else if (index(tok[1], new ".") == 1) tok[1] = tok[1] " " new
                else tok[1] = new
                L[ip[1]] = build(); have = 1
            }
            for (i = 1; i <= NR; i++) print L[i]
            if (!have) printf "127.0.1.1\t\t%s\n", new
        }' "$HOSTS_FILE" > "$tmp"; then
        rm -f "$tmp"
        err_report "Failed to update $HOSTS_FILE"
        exit 1
    fi

    if cmp -s "$tmp" "$HOSTS_FILE"; then
        rm -f "$tmp"
        debugger "($SCRIPT_NAME) $HOSTS_FILE already maps 127.0.1.1 to $new"
    elif ! { chmod --reference="$HOSTS_FILE" "$tmp" &&
             chown --reference="$HOSTS_FILE" "$tmp" &&
             mv -f "$tmp" "$HOSTS_FILE"; }; then
        rm -f "$tmp"
        err_report "Failed to replace $HOSTS_FILE"
        exit 1
    fi

    if ! hosts_maps "$new"; then
        err_report "($SCRIPT_NAME) New hostname $new has not been set correctly in hosts file $HOSTS_FILE (please edit manually)"
        exit 1
    fi
    debugger "($SCRIPT_NAME) $HOSTS_FILE maps 127.0.1.1 to $new"
}

# set new hostname
set_hostname() {

    debugger "($SCRIPT_NAME) Setting hostname..."

    new_hostname=$HOSTNAME
    debugger "($SCRIPT_NAME) New hostname: $new_hostname"

    # check we have correct hostname script filename
    check_file_exists $HOSTNAME_SCRIPT

    current_hostname=$($HOSTNAME_SCRIPT)
    debugger "($SCRIPT_NAME) Current hostname: $current_hostname"

    if [ -z "$new_hostname" ]; then
       err_report "No hostname passed to : set_hostname()"
       exit 1
    fi

    # One label: letters, digits and '-' (also keeps option-like names away from hostnamectl).
    if ! [[ $new_hostname =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$ ]]; then
        err_report "Cannot use: $new_hostname as it is not a valid hostname under RFC-952/RFC-1123 (letters, digits and '-' only, 1-63 chars, no leading or trailing '-')"
        exit 1
    fi

    # check we have correct hosts filename
    check_file_exists $HOSTS_FILE

    # check if current hostname is equal to new hostname
    if [ "$current_hostname" == "$new_hostname" ]; then
        debugger "($SCRIPT_NAME) Current and new hostnames are equal ($current_hostname) == ($new_hostname)"
        # A reboot between hostnamectl and the hosts update leaves the old
        # name in /etc/hosts; the next run repairs it here.
        sync_hosts "$current_hostname" "$new_hostname"
        exit 0
    fi

    # check we have correct hostnamectl script filename
    check_file_exists $HOSTNAMECTL_SCRIPT

    debugger "($SCRIPT_NAME) Setting hostname with hostname ctl cmd to: $new_hostname"

    # set hostname in /etc/hostname with hostnamectl commmand
    if ! err=$($HOSTNAMECTL_SCRIPT set-hostname "$new_hostname" 2>&1); then
        err_report "Hostname set command failed: $err"
        exit 1
    fi
    debugger "($SCRIPT_NAME) Set hostname with hostnamectl to : $new_hostname"

    sync_hosts "$current_hostname" "$new_hostname"

    # restart avahi-daemon so that the new hostname takes effect
    debugger "($SCRIPT_NAME) Restart avahi-daemon"
    if ! $SYSTEMCTL_SCRIPT restart avahi-daemon > /dev/null 2>&1; then
        err_report "Failed to restart avahi-daemon"
        exit 1
    fi
    debugger "($SCRIPT_NAME) avahi-daemon restarted"

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
        echo "Usage: wlanpi-hostname {-v | get | set | help}"
        echo ""
        echo "  wlanpi-hostname -v : show current script version"
        echo "  wlanpi-hostname get: show current hostname"
        echo "  wlanpi-hostname set [hostname_str]: set hostname"
        echo "  wlanpi-hostname : show usage info"
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
