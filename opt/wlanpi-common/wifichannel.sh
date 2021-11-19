#!/bin/bash

# Author: Jiri Brejcha, jirka@jiribrejcha.net, @jiribrejcha
# Inspired by Adrian Granados from Intuibits, Keith Parsons from WLAN Pros, idea sparked by Nick Turner

usage(){
echo "This tool converts channel number to center frequency in MHz, and center frequency in MHz to channel number. Please pass a correct frequency or channel number as the first and only argument to it."
}

input="$1"
band=""

# Checks if it is a valid 2.4, 5 or 6 GHz channel or frequency
unknown_band(){
if [ -z "$band" ]; then
    echo "Error: Have you entered a valid frequency or channel number?"
    echo
    usage
    exit 1
fi
}

# Checks if argument is a number
case $input in
    ''|*[!0-9]*) unknown_band ;;
esac

# Valid 5 GHz channels
valid_5_channels=(36 38 40 42 44 46 48 50 52 54 56 58 60 62 64 100 104 106 108 110 112 114 116 118 120 122 124 126 128 132 134 136 138 140 142 144 149 151 153 155 157 159 161 165)

# Converts frequency in MHz to channel number
freq_to_channel(){
    # 2.4 GHz
    if [ "$input" -eq 2484 ]; then
        band="2.4"
        echo "Band:   $band GHz   Channel: 14   Recommended: No"
    elif [ "$input" -ge 2412 ] && [ "$input" -lt 2484 ] && [ $(($input%2412%5)) -eq 0 ]; then
        band="2.4"
        channel_2_4="$(((($input - 2412) / 5) + 1))"
        if [ "$channel_2_4" -eq 1 ] || [ "$channel_2_4" -eq 6 ] || [ "$channel_2_4" -eq 11 ]; then
            echo "Band:   $band GHz   Channel: $channel_2_4   Recommended: Yes"
        else
            echo "Band:   $band GHz   Channel: $channel_2_4   Recommended: No"
        fi

    # 5 GHz
    elif [ "$input" -ge 5160 ] && [ "$input" -lt 5885 ] && [ $(($input%10)) -eq 0 ]; then
        channel_5="$(((($input - 5180) / 5) + 36))"
        if [[ " ${valid_5_channels[*]} " =~ " ${channel_5} " ]]; then
            band="5"
            echo "Band:   $band GHz   Channel: $channel_5"
        fi

    # 6 GHz
    elif [ "$input" -ge 5955 ] && [ "$input" -lt 7115 ]; then
        channel_6="$(((($input - 5955) / 5) + 1))"
        # Valid 6 GHz PSC channel
        if [ $(($channel_6%4)) -eq 1 ] && [ $(($channel_6%16)) -eq 5 ]; then
            band="6"
            echo "Band:   $band GHz   Channel: $channel_6   PSC: Yes"
        # Valid 6 GHz channel
        elif [ $(($channel_6%4)) -eq 1 ]; then
            band="6"
            echo "Band:   $band GHz   Channel: $channel_6"
        fi
    fi
    unknown_band
}

# Converts channel number to frequency in MHz
channel_to_freq(){
    # 2.4 GHz
    if [ "$input" -eq 14 ]; then
        band="2.4"
        echo "Band: $band GHz   Center frequency: 2484 MHz   Recommended: No"

    elif [ "$input" -ge 1 ] && [ "$input" -le 13 ]; then
        band="2.4"
        if [ "$input" -eq 1 ] || [ "$input" -eq 6 ] || [ "$input" -eq 11 ]; then
            echo "Band: $band GHz   Center frequency: $((($input * 5) + 2407)) MHz   Recommended: Yes"
        else
            echo "Band: $band GHz   Center frequency: $((($input * 5) + 2407)) MHz   Recommended: No"
        fi

    # 5 GHz
    elif [[ " ${valid_5_channels[*]} " =~ " ${input} " ]]; then
        band="5"
        echo "Band:   $band GHz   Center frequency: $((($input * 5) + 5000)) MHz"
    fi


    # 6 GHz
    if [ "$input" -ge 1 ] && [ "$input" -le 233 ] && [ $(($input%4)) -eq 1 ]; then
        band="6"
        echo "Band:   $band GHz   Center frequency: $((($input * 5) + 5950)) MHz"
    fi
    unknown_band
}

# Main
if [ "$input" -ge 2412 ]; then
    freq_to_channel
else
    channel_to_freq
fi
