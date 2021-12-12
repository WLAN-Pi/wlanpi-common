#!/bin/bash
set -e
###########################################################
# Description:
#
#  Test suite for wlanpi-hostname.sh
#
###########################################################

##########################
# User configurable vars
##########################
MODULE=wlanpi-hostname.sh
VERSION=1.0.0
COMMENTS="wlanpi-hostname.sh test suite to test script operation"
SCRIPT_NAME="/opt/wlanpi-common/wlanpi-hostname.sh"

TEST_SCRIPT_NAME=$(basename $0)

###########################
# script global vars
###########################
# initialize tests passed counter
tests_passed=0
# initialize tests failed counter
tests_failed=0

# Tests log file
LOG_DIR="/var/log"
LOG_FILE="${LOG_DIR}/${TEST_SCRIPT_NAME}_results.log"

################
# root check
################
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi

##############################################
# Helper functions - see docs at end of file
##############################################

summary () {
  tests_completed=$((tests_passed + tests_failed))
  echo ""
  echo "-----------------------------------"
  echo " Total tests: $tests_completed"
  echo " Number tests passed: $tests_passed"
  echo " Number tests failed:  $tests_failed"
  echo "-----------------------------------"
  echo ""
  echo "(Results in : $LOG_FILE)"
  echo ""
}

inc_passed ()     { tests_passed=$((tests_passed + 1));  }
inc_failed ()     { tests_failed=$((tests_failed + 1));  }

info ()    { echo -n "(info) Test: $1" | tee -a $LOG_FILE;  }
info_n ()  { echo "(info) Test: $1" | tee -a $LOG_FILE;  }
comment () { echo $1 | tee -a $LOG_FILE; }

pass ()    { inc_passed; echo " $1  (pass)" | tee -a $LOG_FILE; }
fail ()    { inc_failed; echo " $1  (fail) <--- !!!!!!" | tee -a $LOG_FILE; }

check ()     { if [[ $1 ]];   then pass; else fail; fi; }
check_not () { if ! [[ $1 ]]; then pass; else fail; fi; }

file_exists ()    { info "Checking file exists: $1"; if [[ -e $1 ]]; then pass; else fail; fi; }
dir_exists ()     { info "Checking directory exists: $1"; if [[ -d $1 ]]; then pass; else fail; fi; }
symlink_exists () { info "Checking symlink exists: $1"; if [[ -L $1 ]]; then pass; else fail; fi; }
symlink_not () { info "Checking file is not symlink: $1"; if [[ ! -L $1 ]]; then pass; else fail; fi;  }
check_process ()  { info "Checking process running: $1"; if [[ `pgrep $1` ]]; then pass; else fail; fi; }
check_systemctl () { info "Checking systemctl running: $1"; if [[ `systemctl status $1 | grep 'active (running)'` ]]; then pass; else fail; fi; }

must_be_root () { info "Checking we must be root to run script"; check `/usr/bin/su -c "${SCRIPT_NAME}" wlanpi | grep root`; }

########################################
# Test rig overview
########################################
echo "\

=======================================================
Test rig description:

  1. Script installed on WLAN Pi Pro (default config 
     with hostname = wlanpi)
  2. CLI access to the WLAN Pi Pro (using wlanpi account)
  3. Run this script using sudo
=======================================================" | tee $LOG_FILE

########################################
# Test suite
########################################

run_tests () {

  comment ""
  comment "###########################################"
  comment "  Running $MODULE test suite"
  comment "###########################################"
  comment ""

  file_exists $SCRIPT_NAME

  must_be_root

  info "Checking hostname is wlanpi"
  check `$SCRIPT_NAME get | grep ^wlanpi$`

  info "Hostname set test - setting to : keith"
  check `$SCRIPT_NAME set keith; echo $?`

  info "Checking new hostname set to keith"
  check `$SCRIPT_NAME get | grep ^keith$`

  info "Changing hostname back to wlanpi"
  check `$SCRIPT_NAME set wlanpi; echo $?`

  info "Checking hostname back to wlanpi"
  check `$SCRIPT_NAME get | grep ^wlanpi$`

  info "Checking underscore not allowed in hostname"
  check `$SCRIPT_NAME set keith_is_great | grep RFC`

  # Print test run results summary
  summary

  comment ""
  comment "###########################################"
  comment "  End of $MODULE test suite"
  comment "###########################################"
  comment ""

  exit $tests_failed
}

########################################
# main
########################################

case "$1" in
  -v)
        echo ""
        echo "Test script version: $VERSION"
        echo $COMMENTS
        echo ""
        exit 0
        ;;
  -h)
        echo "Usage: $TEST_SCRIPT_NAME [ -h | -v ]"
        echo ""
        echo "  $TEST_SCRIPT_NAME -v : script version"
        echo "  $TEST_SCRIPT_NAME -h : script help"
        echo "  $TEST_SCRIPT_NAME    : run test suite"
        echo ""
        exit 0
        ;;
  *)
        run_tests
        ;;
esac

# should never reach here, but just in case....
exit 1

<< 'HOWTO'

#################################################################################################################

Test Utility Documentation
--------------------------

 This script uses a set of useful utilities to simplify running a series of 
 tests from this bash script. The syntax of the utilities is shown below:

 inc_passed: increment the test-passed counter (global var 'tests_passed')
 inc_failed: increment the test-failed counter (global var 'tests_failed')

 info: pre-prend the text in $1 with "info" and send to stdout & the log file (no CR)
 info_n: pre-prend the text in $1 with "info" and send to stdout & the log file (inc CR after msg)

 pass: write a "pass" msg to stdout & the log file, with optional additional msg in $1 (var passed to function)
 fail: write a "fail" msg to stdout & the log file, with optional additional msg in $1 (var passed to function)
 comment: output raw text supplied in $1 to std & log file

 check: call pass() if condition passed is true (can inc option msg via $1), otherwise fail()
 check_not: call pass() if condition passed is false (can inc option msg via $1), otherwise fail()

 file_exists: call pass() if file name passed via $1 exists, else call fail()
 dir_exists: call pass() if dir name passed via $1 exists, else call fail()
 symlink_exists: call pass() if file name passed via $1 is a symlink, else call fail()
 symlink_not: call pass() if file name passed via $1 is not symlink, else call fail()
 check_process: call pass() if process name passed via $1 is running, else call fail()
 check_systemctl: call pass() if service name passed via $1 is running, else call fail()

 must_be_root: call pass() if script called output msg to indicate must be root, else call fail()

#################################################################################################################
HOWTO