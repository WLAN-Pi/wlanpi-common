#!/bin/bash
###########################################################
# Description:
#
#  Test suite for wifichannel.sh - channel width feature
#
###########################################################

##########################
# User configurable vars
##########################
MODULE=wifichannel.sh
VERSION=1.0.0
COMMENTS="wifichannel.sh test suite to validate channel width reporting"
SCRIPT_NAME="$(dirname "$0")/../wifichannel.sh"

TEST_SCRIPT_NAME=$(basename $0)

###########################
# script global vars
###########################
# initialize tests passed counter
tests_passed=0
# initialize tests failed counter
tests_failed=0

##############################################
# Helper functions
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
}

inc_passed ()     { tests_passed=$((tests_passed + 1));  }
inc_failed ()     { tests_failed=$((tests_failed + 1));  }

info ()    { echo -n "(info) Test: $1";  }

pass ()    { inc_passed; echo " $1  (pass)"; }
fail ()    { inc_failed; echo " $1  (fail) <--- !!!!!!"; }

# Check that output of a command contains an expected string
check_output () {
    local description="$1"
    local input="$2"
    local expected="$3"
    local output

    info "$description"
    output=$($SCRIPT_NAME $input 2>&1)
    if echo "$output" | grep -qF "$expected"; then
        pass
    else
        fail
        echo "       Expected to find: $expected"
        echo "       Actual output:    $output"
    fi
}

# Check that every non-empty line of output contains a string
check_all_lines () {
    local description="$1"
    local input="$2"
    local expected="$3"
    local output
    local line_count
    local match_count

    info "$description"
    output=$($SCRIPT_NAME $input 2>&1)
    line_count=$(echo "$output" | grep -c '.')
    match_count=$(echo "$output" | grep -cF "$expected")
    if [ "$line_count" -eq "$match_count" ] && [ "$line_count" -gt 0 ]; then
        pass
    else
        fail
        echo "       Expected '$expected' on all $line_count lines, found on $match_count"
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

  # ---- 2.4 GHz channel width tests ----
  check_output "2.4 GHz ch 1 width" "1" "Widths: 20/40"
  check_output "2.4 GHz ch 6 width" "6" "Widths: 20/40"
  check_output "2.4 GHz ch 14 width" "14" "Widths: 20"

  # ---- 5 GHz channel width tests ----
  check_output "5 GHz ch 36 width (160 MHz capable)" "36" "Widths: 20/40/80/160"
  check_output "5 GHz ch 100 width (160 MHz capable)" "100" "Widths: 20/40/80/160"
  check_output "5 GHz ch 132 width (80 MHz max)" "132" "Widths: 20/40/80"
  check_output "5 GHz ch 144 width (80 MHz max)" "144" "Widths: 20/40/80"
  check_output "5 GHz ch 149 width (160 MHz capable)" "149" "Widths: 20/40/80/160"
  check_output "5 GHz ch 165 width (160 MHz capable)" "165" "Widths: 20/40/80/160"
  check_output "5 GHz ch 181 width (20 MHz only)" "181" "Widths: 20"

  # ---- 5 GHz frequency lookup width tests ----
  check_output "5 GHz freq 5180 (ch 36) width" "5180" "Widths: 20/40/80/160"
  check_output "5 GHz freq 5660 (ch 132) width" "5660" "Widths: 20/40/80"

  # ---- 6 GHz channel width tests ----
  check_output "6 GHz ch 5 width (320 MHz capable)" "5" "Widths: 20/40/80/160/320"
  check_output "6 GHz ch 37 width (320 MHz capable)" "37" "Widths: 20/40/80/160/320"
  check_output "6 GHz ch 197 width (160 MHz max)" "197" "Widths: 20/40/80/160"
  check_output "6 GHz ch 225 width (40 MHz max)" "225" "Widths: 20/40"
  check_output "6 GHz ch 233 width (20 MHz only)" "233" "Widths: 20"

  # ---- 6 GHz frequency lookup width tests ----
  check_output "6 GHz freq 5975 (ch 5) width" "5975" "Widths: 20/40/80/160/320"

  # ---- Band listing tests (every line should have Widths:) ----
  check_all_lines "All 2.4 GHz lines have Widths" "-2" "Widths:"
  check_all_lines "All 5 GHz lines have Widths" "-5" "Widths:"
  check_all_lines "All 6 GHz lines have Widths" "-6" "Widths:"

  # ---- Existing behavior preservation tests ----
  check_output "Ch 36 still shows frequency" "36" "5180 MHz"
  check_output "Ch 6 still shows recommended" "6" "Recommended: Yes"
  check_output "Ch 36 still shows U-NII band" "36" "U-NII-1"
  check_output "Ch 132 still shows U-NII band" "132" "U-NII-2C"

  # ---- Error handling preserved ----
  info "Invalid input still shows error"
  output=$($SCRIPT_NAME "abc" 2>&1)
  if echo "$output" | grep -qF "Error: Invalid"; then
      pass
  else
      fail
      echo "       Expected error message, got: $output"
  fi

  # Print test run results summary
  summary

  echo ""
  echo "###########################################"
  echo "  End of $MODULE test suite"
  echo "###########################################"
  echo ""

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
