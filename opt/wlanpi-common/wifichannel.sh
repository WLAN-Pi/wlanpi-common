#!/bin/bash

# Author: Jiri Brejcha, jirka@jiribrejcha.net, @jiribrejcha
# Idea sparked by Nick Turner, inspired by Adrian Granados @ Intuibits and Keith Parsons @ WLAN Pros

usage(){
echo "Usage: wifichannel channel_number | center_frequency"
echo
echo "This tool converts channel number to center frequency in MHz, and center frequency in MHz to channel number. Please pass a correct frequency or channel number as the first and only argument to it."
}

INPUT="$1"
BAND=""

# Checks if it is a valid 2.4, 5 or 6 GHz channel or frequency
unknown_band(){
if [ -z "$BAND" ]; then
    usage
    exit 1
fi
}

# Checks if argument is a number
case $INPUT in
    ''|*[!0-9]*) unknown_band ;;
esac

# Valid 5 GHz channels
VALID_5_CHANNELS=(36 38 40 42 44 46 48 50 52 54 56 58 60 62 64 100 102 104 106 108 110 112 114 116 118 120 122 124 126 128 132 134 136 138 140 142 144 149 151 153 155 157 159 161 165)
# 5 GHz bands
UNII_1_CHANNELS=(36 38 40 42 44 46 48)
UNII_2_CHANNELS=(52 54 56 58 60 62 64)
UNII_2E_CHANNELS=(100 102 104 106 108 110 112 114 116 118 120 122 124 126 128 132 134 136 138 140 142 144)
UNII_3_CHANNELS=(149 151 153 155 157 159 161 165)


# Converts frequency in MHz to channel number
freq_to_channel(){
    # 2.4 GHz
    if [ "$INPUT" -eq 2484 ]; then
        BAND="2.4"
        echo "Band:   $BAND GHz   Channel: 14   Recommended: No"
    elif [ "$INPUT" -ge 2412 ] && [ "$INPUT" -lt 2484 ] && [ $(($INPUT%2412%5)) -eq 0 ]; then
        BAND="2.4"
        CHANNEL_2_4="$(((($INPUT - 2412) / 5) + 1))"
        if [ "$CHANNEL_2_4" -eq 1 ] || [ "$CHANNEL_2_4" -eq 6 ] || [ "$CHANNEL_2_4" -eq 11 ]; then
            echo "Band:   $BAND GHz   Channel: $CHANNEL_2_4   Recommended: Yes"
        else
            echo "Band:   $BAND GHz   Channel: $CHANNEL_2_4   Recommended: No"
        fi

    # 5 GHz
    elif [ "$INPUT" -ge 5160 ] && [ "$INPUT" -lt 5885 ] && [ $(($INPUT%10)) -eq 0 ]; then
        CHANNEL_5="$(((($INPUT - 5180) / 5) + 36))"
        if [[ " ${VALID_5_CHANNELS[*]} " =~ " ${CHANNEL_5} " ]]; then
            BAND="5"
            echo "Band:   $BAND GHz   Channel: $CHANNEL_5"
        fi

    # 6 GHz
    elif [ "$INPUT" -ge 5955 ] && [ "$INPUT" -lt 7115 ]; then
        channel_6="$(((($INPUT - 5955) / 5) + 1))"
        # Valid 6 GHz PSC channel
        if [ $(($channel_6%4)) -eq 1 ] && [ $(($channel_6%16)) -eq 5 ]; then
            BAND="6"
            echo "Band:   $BAND GHz   Channel: $channel_6   PSC: Yes"
        # Valid 6 GHz channel
        elif [ $(($channel_6%4)) -eq 1 ]; then
            BAND="6"
            echo "Band:   $BAND GHz   Channel: $channel_6"
        fi
    fi

    unknown_band
}

# Converts channel number to frequency in MHz
channel_to_freq(){
    # 2.4 GHz
    if [ "$INPUT" -eq 14 ]; then
        BAND="2.4"
        echo "Band: $BAND GHz   Center frequency: 2484 MHz   Recommended: No"

    elif [ "$INPUT" -ge 1 ] && [ "$INPUT" -le 13 ]; then
        BAND="2.4"
        if [ "$INPUT" -eq 1 ] || [ "$INPUT" -eq 6 ] || [ "$INPUT" -eq 11 ]; then
            echo "Band: $BAND GHz   Center frequency: $((($INPUT * 5) + 2407)) MHz   Recommended: Yes"
        else
            echo "Band: $BAND GHz   Center frequency: $((($INPUT * 5) + 2407)) MHz   Recommended: No"
        fi
    fi

    # 5 GHz
    if [[ " ${VALID_5_CHANNELS[*]} " =~ " ${INPUT} " ]]; then
        BAND="5"
        CTF_5_OUTPUT="Band:   $BAND GHz   Center frequency: $((($INPUT * 5) + 5000)) MHz"
        if [[ " ${UNII_1_CHANNELS[*]} " =~ " ${INPUT} " ]]; then
            CTF_5_OUTPUT="$CTF_5_OUTPUT   UNII-1"
        elif [[ " ${UNII_2_CHANNELS[*]} " =~ " ${INPUT} " ]]; then
            CTF_5_OUTPUT="$CTF_5_OUTPUT   UNII-2"
        elif [[ " ${UNII_2E_CHANNELS[*]} " =~ " ${INPUT} " ]]; then
            CTF_5_OUTPUT="$CTF_5_OUTPUT   UNII-2E"
        elif [[ " ${UNII_3_CHANNELS[*]} " =~ " ${INPUT} " ]]; then
            CTF_5_OUTPUT="$CTF_5_OUTPUT   UNII-3"
        fi
        echo "$CTF_5_OUTPUT"
    fi

    # 6 GHz
    # Valid 6 GHz PSC channel
    if [ "$INPUT" -ge 1 ] && [ "$INPUT" -le 233 ] && [ $(($INPUT%4)) -eq 1 ] && [ $(($INPUT%16)) -eq 5 ]; then
        BAND="6"
        echo "Band:   $BAND GHz   Center frequency: $((($INPUT * 5) + 5950)) MHz   PSC: Yes"
    fi
    if [ "$INPUT" -ge 1 ] && [ "$INPUT" -le 233 ] && [ $(($INPUT%16)) -eq 1 ]; then
        BAND="6"
        echo "Band:   $BAND GHz   Center frequency: $((($INPUT * 5) + 5950)) MHz"
    fi
    
    unknown_band
}

# Main
if [ "$INPUT" -ge 2412 ]; then
    freq_to_channel
else
    channel_to_freq
fi
