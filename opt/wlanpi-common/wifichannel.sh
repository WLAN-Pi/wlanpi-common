#!/bin/bash

# Author: Jiri Brejcha (jirka@jiribrejcha)
# Inspired by Adrian Granados from Intuibits and Keith Parsons from WLAN Pros

usage(){
echo "This tool converts channel number to frequency in MHz, and frequency in MHz to channel number. Simply pass a correct frequency or channel number as the first and only argument to the script."
exit 0
}

input="$1"

# Checks if argument is a number
case $input in
    ''|*[!0-9]*) usage ;;
esac

# Converts frequency in MHz to channel number
freq_to_channel(){
    if [ "$input" -eq 2484 ]; then
        echo "14"
    elif [ "$input" -ge 2412 ] && [ "$input" -lt 2484 ]; then
        echo "$(((($input - 2412) / 5) + 1))"
    elif [ "$input" -ge 5160 ] && [ "$input" -lt 5885 ]; then
        echo "$(((($input - 5180) / 5) + 36))"
    elif [ "$input" -ge 5955 ] && [ "$input" -lt 7115 ]; then
        echo "$(((($input - 5955) / 5) + 1))"
    else usage
    fi
}

# Converts channel number to frequency in MHz
channel_to_freq(){
    if [ "$input" -eq 14 ]; then
        echo "2484"
    elif [ "$input" -ge 1 ] && [ "$input" -le 13 ]; then
        echo "$((($input * 5) + 2407))"
    elif [ "$input" -ge 36 ] && [ "$input" -le 165 ]; then
        echo "$((($input * 5) + 5000))"
    fi
    if [ "$input" -ge 1 ] && [ "$input" -le 233 ]; then
        echo "$((($input * 5) + 5950))"
    fi
}

# Main
if [ "$input" -ge 2412 ]; then
    freq_to_channel
else
    channel_to_freq
fi
