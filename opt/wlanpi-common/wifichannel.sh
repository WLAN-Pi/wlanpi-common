#!/bin/bash

# Author: Jiri Brejcha, jirka@jiribrejcha.net, @jiribrejcha
# Idea sparked by Nick Turner @nickjvturner, thanks to Adrian Granados @adriangranados and Keith Parsons @KeithRParsons
#
# This script converts channel number to center frequency in MHz, and vice versa.
# 

INPUT="$1"
BAND=""
VERSION="1.0.7"
SCRIPT_NAME="$(basename "$0")"

usage(){
    echo "Converts channel number to center frequency in MHz, and vice versa."
    echo
    echo "Usage:"
    echo "  $SCRIPT_NAME <channel-number>"
    echo "  $SCRIPT_NAME <center-frequency>"
    echo "  $SCRIPT_NAME [options]"
    echo
    echo "Options:"
    echo "  -v, --version  Show version"
    echo "  -h, --help     Show this screen"
    echo "  -2.4, -2       List all 2.4 GHz channels"
    echo "  -5             List all 5 GHz channels"
    echo "  -6             List all 6 GHz channels"
    echo
    exit 0
}

version(){
    echo "$VERSION"
    exit 0
}

# Checks if it is a valid 2.4, 5 or 6 GHz channel or frequency
invalid_input(){
if [ -z "$BAND" ]; then
    echo "Error: Invalid channel number or frequency. Use \"-h\" for help."
    exit 1
fi
}

# Only accept a single argument
if [ "$#" -ne 1 ]; then
    invalid_input
fi

# 5 GHz channels
ALL_5_CHANNELS=(36 38 40 42 44 46 48 50 52 54 56 58 60 62 64 100 102 104 106 108 110 112 114 116 118 120 122 124 126 128 132 134 136 138 140 142 144 149 151 153 155 157 159 161 165 169 173 177 181)
UNBONDED_5_CHANNELS=(36 40 44 48 52 56 60 64 100 104 108 112 116 120 124 128 132 136 140 144 149 153 157 161 165 169 173 177 181)
UNII_1_CHANNELS=(36 38 40 42 44 46 48)
UNII_2A_CHANNELS=(52 54 56 58 60 62 64)
UNII_2C_CHANNELS=(100 102 104 106 108 110 112 114 116 118 120 122 124 126 128 132 134 136 138 140 142 144)
UNII_3_CHANNELS=(149 151 153 155 157 159 161 165)
UNII_4_CHANNELS=(169 173 177 181)

# List all 2.4 GHz channels
show_all_2_4(){
    for i in {1..14}; do
        INPUT="$i"
        if [ "$INPUT" -eq 14 ]; then
            BAND="2.4"
            echo "Band: $BAND GHz   Channel: $INPUT   Center freq: 2484 MHz   Recommended: No"

        elif [ "$INPUT" -ge 1 ] && [ "$INPUT" -le 13 ]; then
            BAND="2.4"
            PAD=""
            if [ "$INPUT" -ge 1 ] && [ "$INPUT" -le 9 ]; then
                PAD=" "
            fi
            if [ "$INPUT" -eq 1 ] || [ "$INPUT" -eq 6 ] || [ "$INPUT" -eq 11 ]; then
                echo "Band: $BAND GHz   Channel:$PAD $INPUT   Center freq: $((($INPUT * 5) + 2407)) MHz   Recommended: Yes"
            else
                echo "Band: $BAND GHz   Channel:$PAD $INPUT   Center freq: $((($INPUT * 5) + 2407)) MHz   Recommended: No"
            fi
        fi
    done
    exit 0
}

# List all 5 GHz channels
show_all_5(){
    BAND="5"
    for INPUT in "${UNBONDED_5_CHANNELS[@]}"; do
        if [[ " ${UNII_1_CHANNELS[*]} " =~ " ${INPUT} " ]]; then
            ALL_5_OUTPUT="Band: $BAND GHz   Channel:  $INPUT   Center freq: $((($INPUT * 5) + 5000)) MHz   U-NII-1"
        elif [[ " ${UNII_2A_CHANNELS[*]} " =~ " ${INPUT} " ]]; then
            ALL_5_OUTPUT="Band: $BAND GHz   Channel:  $INPUT   Center freq: $((($INPUT * 5) + 5000)) MHz   U-NII-2A"
        elif [[ " ${UNII_2C_CHANNELS[*]} " =~ " ${INPUT} " ]]; then
            ALL_5_OUTPUT="Band: $BAND GHz   Channel: $INPUT   Center freq: $((($INPUT * 5) + 5000)) MHz   U-NII-2C"
        elif [[ " ${UNII_3_CHANNELS[*]} " =~ " ${INPUT} " ]]; then
            ALL_5_OUTPUT="Band: $BAND GHz   Channel: $INPUT   Center freq: $((($INPUT * 5) + 5000)) MHz   U-NII-3"
        fi
        echo "$ALL_5_OUTPUT"
    done
    exit 0
}

# List all 6 GHz channels
show_all_6(){
    BAND="6"
    for INPUT in {1..233}; do
        # 6 GHz PSC channels
        PAD=""
        if [ ${#INPUT} -eq 1 ]; then
            PAD="  "
        elif [ ${#INPUT} -eq 2 ]; then
            PAD=" "
        fi

        if [ $(($INPUT%4)) -eq 1 ]; then
            if [ $(($INPUT%16)) -eq 5 ]; then
                echo "Band: $BAND GHz   Channel:$PAD $INPUT   Center freq: $((($INPUT * 5) + 5950)) MHz   PSC: Yes"
            else
                echo "Band: $BAND GHz   Channel:$PAD $INPUT   Center freq: $((($INPUT * 5) + 5950)) MHz   PSC: No"
            fi
        fi
    done
    exit 0
}

# Convert frequency in MHz to channel number
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
        if [[ " ${ALL_5_CHANNELS[*]} " =~ " ${CHANNEL_5} " ]]; then
            BAND="5"
            echo "Band:   $BAND GHz   Channel: $CHANNEL_5"
        fi

    # 6 GHz
    elif [ "$INPUT" -ge 5955 ] && [ "$INPUT" -le 7115 ]; then
        channel_6="$(((($INPUT - 5955) / 5) + 1))"
        # Valid 6 GHz PSC channel
        if [ $(($channel_6%4)) -eq 1 ] && [ $(($channel_6%16)) -eq 5 ]; then
            BAND="6"
            echo "Band:   $BAND GHz   Channel: $channel_6   PSC: Yes"
        # Valid 6 GHz channel
        elif [ $(($channel_6%4)) -eq 1 ]; then
            BAND="6"
            echo "Band:   $BAND GHz   Channel: $channel_6   PSC: No"
        fi
    fi

    invalid_input
}

# Convert channel number to frequency in MHz
channel_to_freq(){
    # 2.4 GHz
    if [ "$INPUT" -eq 14 ]; then
        BAND="2.4"
        echo "Band: $BAND GHz   Channel: $INPUT   Center freq: 2484 MHz   Recommended: No"

    elif [ "$INPUT" -ge 1 ] && [ "$INPUT" -le 13 ]; then
        BAND="2.4"
        if [ "$INPUT" -eq 1 ] || [ "$INPUT" -eq 6 ] || [ "$INPUT" -eq 11 ]; then
            echo "Band: $BAND GHz   Channel: $INPUT   Center freq: $((($INPUT * 5) + 2407)) MHz   Recommended: Yes"
        else
            echo "Band: $BAND GHz   Channel: $INPUT   Center freq: $((($INPUT * 5) + 2407)) MHz   Recommended: No"
        fi
    fi

    # 5 GHz
    if [[ " ${ALL_5_CHANNELS[*]} " =~ " ${INPUT} " ]]; then
        BAND="5"
        CTF_5_OUTPUT="Band:   $BAND GHz   Channel: $INPUT   Center freq: $((($INPUT * 5) + 5000)) MHz"
        if [[ " ${UNII_1_CHANNELS[*]} " =~ " ${INPUT} " ]]; then
            CTF_5_OUTPUT="$CTF_5_OUTPUT   U-NII-1"
        elif [[ " ${UNII_2A_CHANNELS[*]} " =~ " ${INPUT} " ]]; then
            CTF_5_OUTPUT="$CTF_5_OUTPUT   U-NII-2A"
        elif [[ " ${UNII_2C_CHANNELS[*]} " =~ " ${INPUT} " ]]; then
            CTF_5_OUTPUT="$CTF_5_OUTPUT   U-NII-2C"
        elif [[ " ${UNII_3_CHANNELS[*]} " =~ " ${INPUT} " ]]; then
            CTF_5_OUTPUT="$CTF_5_OUTPUT   U-NII-3"
        fi
        echo "$CTF_5_OUTPUT"
    fi

    # 6 GHz PSC channel
    if [ "$INPUT" -ge 1 ] && [ "$INPUT" -le 233 ] && [ $(($INPUT%4)) -eq 1 ] && [ $(($INPUT%16)) -eq 5 ]; then
        BAND="6"
        echo "Band:   $BAND GHz   Channel: $INPUT   Center freq: $((($INPUT * 5) + 5950)) MHz   PSC: Yes"
    # 6 GHz non-PSC channel
    elif [ "$INPUT" -ge 1 ] && [ "$INPUT" -le 233 ] && [ $(($INPUT%4)) -eq 1 ]; then
        BAND="6"
        echo "Band:   $BAND GHz   Channel: $INPUT   Center freq: $((($INPUT * 5) + 5950)) MHz   PSC: No"
    fi
    
    invalid_input
}

#-------------
# Main logic
#-------------

# Process options and filter invalid input out
case $INPUT in
    -h | --help) usage ;;
    -v | --version) version ;;
    -2.4 | -2) show_all_2_4 ;;
    -5) show_all_5 ;;
    -6) show_all_6 ;;
    ''|*[!0-9]*) invalid_input ;;
esac

# Convert channel to frequency or vice versa
if [ "$INPUT" -ge 2412 ]; then
    freq_to_channel
else
    channel_to_freq
fi
