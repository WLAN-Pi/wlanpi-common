#!/bin/bash
###########################################################
# Description:
#
#  Test suite for wlanpi-update.sh image version comparison
#  (semver and calver parsing, prerelease ordering)
#
###########################################################

MODULE=wlanpi-update.sh
VERSION=1.0.0
COMMENTS="wlanpi-update.sh test suite to validate image version comparison"
SCRIPT_NAME="$(dirname "$0")/../wlanpi-update.sh"

# shellcheck source=../wlanpi-update.sh
. "$SCRIPT_NAME"

# initialize tests passed/failed counters
tests_passed=0
tests_failed=0

summary () {
  tests_completed=$((tests_passed + tests_failed))
  echo ""
  echo "-----------------------------------"
  echo " Total tests: $tests_completed"
  echo " Number tests passed: $tests_passed"
  echo " Number tests failed:  $tests_failed"
  echo "-----------------------------------"
  echo ""
}

inc_passed ()     { tests_passed=$((tests_passed + 1));  }
inc_failed ()     { tests_failed=$((tests_failed + 1));  }

info ()    { echo -n "(info) Test: $1";  }

pass ()    { inc_passed; echo "  (pass)"; }
fail ()    { inc_failed; echo "  (fail) <--- !!!!!!"; }

check_eq () {
  if [ "$1" = "$2" ]; then
    pass
  else
    fail
    echo "       Expected: $2"
    echo "       Actual:   $1"
  fi
}

########################################
# Test suite
########################################

run_tests () {

  echo ""
  echo "###########################################"
  echo "  Running $MODULE test suite"
  echo "###########################################"
  echo ""

  # ---- normalize_version ----
  info "normalize semver tag"
  check_eq "$(normalize_version 'v3.4.4')" "3.4.4"
  info "normalize calver tag"
  check_eq "$(normalize_version '26.02-Cortado')" "26.02"
  info "normalize calver rc tag"
  check_eq "$(normalize_version '26.02-rc.1-theanine')" "26.02~rc.1"
  info "normalize calver dev tag"
  check_eq "$(normalize_version '26.08-dev.5-Cortado')" "26.08~dev.5"
  info "normalize calver point release"
  check_eq "$(normalize_version '26.02.1')" "26.02.1"
  info "reject malformed version"
  check_eq "$(normalize_version 'garbage')" ""

  # ---- image_upgrade_status (both args pre-normalized) ----
  info "semver upgrade available"
  check_eq "$(image_upgrade_status '3.4.4' '3.3.0')" "New software image is available for download"
  info "semver up to date"
  check_eq "$(image_upgrade_status '3.4.4' '3.4.4')" "You are running the latest stable release"
  info "calver device vs old semver latest (regression)"
  check_eq "$(image_upgrade_status '3.4.4' '26.02')" "You are running a bleeding edge release"
  info "calver upgrade available"
  check_eq "$(image_upgrade_status '26.08' '26.02')" "New software image is available for download"
  info "calver point upgrade available"
  check_eq "$(image_upgrade_status '26.02.1' '26.02')" "New software image is available for download"
  info "rc to final upgrade available"
  check_eq "$(image_upgrade_status '26.02' '26.02~rc.1')" "New software image is available for download"
  info "dev to final upgrade available"
  check_eq "$(image_upgrade_status '26.02' '26.02~dev.1')" "New software image is available for download"
  info "equal calver is up to date"
  check_eq "$(image_upgrade_status '26.02' '26.02')" "You are running the latest stable release"
}

run_tests
summary
exit $tests_failed