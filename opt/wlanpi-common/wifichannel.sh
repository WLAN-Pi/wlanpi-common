#!/bin/bash

# This script converts channel number to center frequency in MHz, and vice versa. 

# Author: Jiri Brejcha, jirka@jiribrejcha.net, @jiribrejcha
# Idea sparked by Nick Turner @nickjvturner, thanks to Adrian Granados @adriangranados and Keith Parsons @KeithRParsons

INPUT="$1"
BAND=""
VERSION="1.0.11"
SCRIPT_NAME="$(basename "$0")"

# Returns available channel widths for a given band and channel
get_channel_widths(){
    local band=$1
    local channel=$2

    case $band in
        "2.4")
            if [ "$channel" -eq 14 ]; then
                echo "20"
            else
                echo "20/40"
            fi
            ;;
        "5")
            # 160 MHz: U-NII-1 + U-NII-2A (36-64), U-NII-2C first half (100-128), U-NII-3 + U-NII-4 (149-177)
            local ch160="36 40 44 48 52 56 60 64 100 104 108 112 116 120 124 128 149 153 157 161 165 169 173 177"
            # 80 MHz only: U-NII-2C second half (132-144)
            local ch80="132 136 140 144"

            if [[ " $ch160 " =~ " $channel " ]]; then
                echo "20/40/80/160"
            elif [[ " $ch80 " =~ " $channel " ]]; then
                echo "20/40/80"
            else
                echo "20"
            fi
            ;;
        "6")
            # 6 GHz channel widths determined by hierarchical grouping
            # 40 MHz pairs span 8 channel numbers, 80 MHz groups span 16, etc.
            local widths="20"
            local group_end_40=$(( ((channel - 1) / 8) * 8 + 1 + 4 ))
            local group_end_80=$(( ((channel - 1) / 16) * 16 + 1 + 12 ))
            local group_end_160=$(( ((channel - 1) / 32) * 32 + 1 + 28 ))
            local group_end_320=$(( ((channel - 1) / 64) * 64 + 1 + 60 ))

            if [ $group_end_40 -le 233 ]; then
                widths="$widths/40"
            fi
            if [ $group_end_80 -le 233 ]; then
                widths="$widths/80"
            fi
            if [ $group_end_160 -le 233 ]; then
                widths="$widths/160"
            fi
            if [ $group_end_320 -le 233 ]; then
                widths="$widths/320"
            fi
            echo "$widths"
            ;;
    esac
}

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
            WIDTHS=$(get_channel_widths "2.4" "$INPUT")
            echo "Band: $BAND GHz   Channel: $INPUT   Center freq: 2484 MHz   Recommended: No    Widths: $WIDTHS"

        elif [ "$INPUT" -ge 1 ] && [ "$INPUT" -le 13 ]; then
            BAND="2.4"
            WIDTHS=$(get_channel_widths "2.4" "$INPUT")
            PAD=""
            if [ "$INPUT" -ge 1 ] && [ "$INPUT" -le 9 ]; then
                PAD=" "
            fi
            if [ "$INPUT" -eq 1 ] || [ "$INPUT" -eq 6 ] || [ "$INPUT" -eq 11 ]; then
                echo "Band: $BAND GHz   Channel:$PAD $INPUT   Center freq: $((($INPUT * 5) + 2407)) MHz   Recommended: Yes   Widths: $WIDTHS"
            else
                echo "Band: $BAND GHz   Channel:$PAD $INPUT   Center freq: $((($INPUT * 5) + 2407)) MHz   Recommended: No    Widths: $WIDTHS"
            fi
        fi
    done
    exit 0
}

# List all 5 GHz channels
show_all_5(){
    BAND="5"
    for INPUT in "${UNBONDED_5_CHANNELS[@]}"; do
        WIDTHS=$(get_channel_widths "5" "$INPUT")
        if [[ " ${UNII_1_CHANNELS[*]} " =~ " ${INPUT} " ]]; then
            echo "Band: $BAND GHz   Channel:  $INPUT   Center freq: $((($INPUT * 5) + 5000)) MHz   U-NII-1    Widths: $WIDTHS"
        elif [[ " ${UNII_2A_CHANNELS[*]} " =~ " ${INPUT} " ]]; then
            echo "Band: $BAND GHz   Channel:  $INPUT   Center freq: $((($INPUT * 5) + 5000)) MHz   U-NII-2A   Widths: $WIDTHS"
        elif [[ " ${UNII_2C_CHANNELS[*]} " =~ " ${INPUT} " ]]; then
            echo "Band: $BAND GHz   Channel: $INPUT   Center freq: $((($INPUT * 5) + 5000)) MHz   U-NII-2C   Widths: $WIDTHS"
        elif [[ " ${UNII_3_CHANNELS[*]} " =~ " ${INPUT} " ]]; then
            echo "Band: $BAND GHz   Channel: $INPUT   Center freq: $((($INPUT * 5) + 5000)) MHz   U-NII-3    Widths: $WIDTHS"
        elif [[ " ${UNII_4_CHANNELS[*]} " =~ " ${INPUT} " ]]; then
            echo "Band: $BAND GHz   Channel: $INPUT   Center freq: $((($INPUT * 5) + 5000)) MHz   U-NII-4    Widths: $WIDTHS"
        fi
    done
    exit 0
}

# List all 6 GHz channels
show_all_6(){
    BAND="6"
    for INPUT in {1..233}; do
        # Workout padding
        PAD=""
        if [ ${#INPUT} -eq 1 ]; then
            PAD="  "
        elif [ ${#INPUT} -eq 2 ]; then
            PAD=" "
        fi
        # Indicate lower or upper 6 GHz to illustrate difference between countries using 500 MHz and 1200 MHz
        if [ $INPUT -le 93 ]; then
            LOWER_UPPER="Lower 6 GHz"
        else
            LOWER_UPPER="Upper 6 GHz"
        fi

        # Determine U-NII band for 6 GHz
        if [ $INPUT -le 93 ]; then
            UNII_BAND="U-NII-5"
        elif [ $INPUT -le 113 ]; then
            UNII_BAND="U-NII-6"
        elif [ $INPUT -le 181 ]; then
            UNII_BAND="U-NII-7"
        else
            UNII_BAND="U-NII-8"
        fi

        if [ $(($INPUT%4)) -eq 1 ]; then
            WIDTHS=$(get_channel_widths "6" "$INPUT")
            if [ $(($INPUT%16)) -eq 5 ]; then
                echo "Band: $BAND GHz   Channel:$PAD $INPUT   Center freq: $((($INPUT * 5) + 5950)) MHz   PSC: Yes   $LOWER_UPPER   $UNII_BAND   Widths: $WIDTHS"
            else
                echo "Band: $BAND GHz   Channel:$PAD $INPUT   Center freq: $((($INPUT * 5) + 5950)) MHz   PSC: No    $LOWER_UPPER   $UNII_BAND   Widths: $WIDTHS"
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
        WIDTHS=$(get_channel_widths "2.4" 14)
        echo "Band:   $BAND GHz   Channel: 14   Recommended: No    Widths: $WIDTHS"
    elif [ "$INPUT" -ge 2412 ] && [ "$INPUT" -lt 2484 ] && [ $(($INPUT%2412%5)) -eq 0 ]; then
        BAND="2.4"
        CHANNEL_2_4="$(((($INPUT - 2412) / 5) + 1))"
        WIDTHS=$(get_channel_widths "2.4" "$CHANNEL_2_4")
        if [ "$CHANNEL_2_4" -eq 1 ] || [ "$CHANNEL_2_4" -eq 6 ] || [ "$CHANNEL_2_4" -eq 11 ]; then
            echo "Band:   $BAND GHz   Channel: $CHANNEL_2_4   Recommended: Yes   Widths: $WIDTHS"
        else
            echo "Band:   $BAND GHz   Channel: $CHANNEL_2_4   Recommended: No    Widths: $WIDTHS"
        fi

    # 5 GHz
    elif [ "$INPUT" -ge 5160 ] && [ "$INPUT" -le 5905 ] && [ $(($INPUT%5)) -eq 0 ]; then
        CHANNEL_5="$(((($INPUT - 5180) / 5) + 36))"
        if [[ " ${ALL_5_CHANNELS[*]} " =~ " ${CHANNEL_5} " ]]; then
            BAND="5"
            WIDTHS=$(get_channel_widths "5" "$CHANNEL_5")
            if [[ " ${UNII_1_CHANNELS[*]} " =~ " ${CHANNEL_5} " ]]; then
                echo "Band:   $BAND GHz   Channel: $CHANNEL_5   Center freq: $INPUT MHz   U-NII-1   Widths: $WIDTHS"
            elif [[ " ${UNII_2A_CHANNELS[*]} " =~ " ${CHANNEL_5} " ]]; then
                echo "Band:   $BAND GHz   Channel: $CHANNEL_5   Center freq: $INPUT MHz   U-NII-2A   Widths: $WIDTHS"
            elif [[ " ${UNII_2C_CHANNELS[*]} " =~ " ${CHANNEL_5} " ]]; then
                echo "Band:   $BAND GHz   Channel: $CHANNEL_5   Center freq: $INPUT MHz   U-NII-2C   Widths: $WIDTHS"
            elif [[ " ${UNII_3_CHANNELS[*]} " =~ " ${CHANNEL_5} " ]]; then
                echo "Band:   $BAND GHz   Channel: $CHANNEL_5   Center freq: $INPUT MHz   U-NII-3   Widths: $WIDTHS"
            elif [[ " ${UNII_4_CHANNELS[*]} " =~ " ${CHANNEL_5} " ]]; then
                echo "Band:   $BAND GHz   Channel: $CHANNEL_5   Center freq: $INPUT MHz   U-NII-4   Widths: $WIDTHS"
            fi
        fi

    # 6 GHz
    elif [ "$INPUT" -ge 5955 ] && [ "$INPUT" -le 7115 ]; then
        CHANNEL_6="$(((($INPUT - 5955) / 5) + 1))"

        # Indicate lower or upper 6 GHz to illustrate difference between countries using 500 MHz and 1200 MHz
        if [ $CHANNEL_6 -le 93 ]; then
            LOWER_UPPER="Lower 6 GHz"
        else
            LOWER_UPPER="Upper 6 GHz"
        fi

        # Valid 6 GHz PSC channel
        if [ $(($CHANNEL_6%4)) -eq 1 ] && [ $(($CHANNEL_6%16)) -eq 5 ]; then
            BAND="6"
            WIDTHS=$(get_channel_widths "6" "$CHANNEL_6")
            echo "Band:   $BAND GHz   Channel: $CHANNEL_6   PSC: Yes   $LOWER_UPPER   Widths: $WIDTHS"
        # Valid 6 GHz non-PSC channel
        elif [ $(($CHANNEL_6%4)) -eq 1 ]; then
            BAND="6"
            WIDTHS=$(get_channel_widths "6" "$CHANNEL_6")
            echo "Band:   $BAND GHz   Channel: $CHANNEL_6   PSC: No    $LOWER_UPPER   Widths: $WIDTHS"
        fi
    fi

    invalid_input
}

# Convert channel number to frequency in MHz
channel_to_freq(){
    # 2.4 GHz
    if [ "$INPUT" -eq 14 ]; then
        BAND="2.4"
        WIDTHS=$(get_channel_widths "2.4" "$INPUT")
        echo "Band: $BAND GHz   Channel: $INPUT   Center freq: 2484 MHz   Recommended: No    Widths: $WIDTHS"

    elif [ "$INPUT" -ge 1 ] && [ "$INPUT" -le 13 ]; then
        BAND="2.4"
        WIDTHS=$(get_channel_widths "2.4" "$INPUT")
        if [ "$INPUT" -eq 1 ] || [ "$INPUT" -eq 6 ] || [ "$INPUT" -eq 11 ]; then
            echo "Band: $BAND GHz   Channel: $INPUT   Center freq: $((($INPUT * 5) + 2407)) MHz   Recommended: Yes   Widths: $WIDTHS"
        else
            echo "Band: $BAND GHz   Channel: $INPUT   Center freq: $((($INPUT * 5) + 2407)) MHz   Recommended: No    Widths: $WIDTHS"
        fi
    fi

    # 5 GHz
    if [[ " ${ALL_5_CHANNELS[*]} " =~ " ${INPUT} " ]]; then
        BAND="5"
        WIDTHS=$(get_channel_widths "5" "$INPUT")
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
        CTF_5_OUTPUT="$CTF_5_OUTPUT   Widths: $WIDTHS"
        echo "$CTF_5_OUTPUT"
    fi

    # 6 GHz

    # Indicate lower or upper 6 GHz to illustrate difference between countries using 500 MHz and 1200 MHz
    if [ "$INPUT" -le 93 ]; then
        LOWER_UPPER="Lower 6 GHz"
    else
        LOWER_UPPER="Upper 6 GHz"
    fi

    # 6 GHz PSC channel
    if [ "$INPUT" -ge 1 ] && [ "$INPUT" -le 233 ] && [ $(($INPUT%4)) -eq 1 ] && [ $(($INPUT%16)) -eq 5 ]; then
        BAND="6"
        WIDTHS=$(get_channel_widths "6" "$INPUT")
        echo "Band:   $BAND GHz   Channel: $INPUT   Center freq: $((($INPUT * 5) + 5950)) MHz   PSC: Yes   $LOWER_UPPER   Widths: $WIDTHS"

    # 6 GHz non-PSC channel
    elif [ "$INPUT" -ge 1 ] && [ "$INPUT" -le 233 ] && [ $(($INPUT%4)) -eq 1 ]; then
        BAND="6"
        WIDTHS=$(get_channel_widths "6" "$INPUT")
        echo "Band:   $BAND GHz   Channel: $INPUT   Center freq: $((($INPUT * 5) + 5950)) MHz   PSC: No    $LOWER_UPPER   Widths: $WIDTHS"
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
