#!/bin/bash
# Shows public IPv4 address and related details 

#Get all data in JSON format 
DATAINJSON=$(timeout 3 curl -s --ipv4 'ifconfig.co/json')

if [ ! "$DATAINJSON" ]; then
    echo "No public IPv4 address detected"
    #Conciously exiting with 0 to prevent error message in Python code that calls this script 
    exit 0
fi

#Parse them
PUBLICIP=$(echo "$DATAINJSON" | jq -r '.ip')
PUBLICIPCOUNTRY=$(echo "$DATAINJSON" | jq -r '.country')
PUBLICIPASNORG=$(echo "$DATAINJSON" | jq -r '.asn_org')
PUBLICIPHOSTNAME=$(echo "$DATAINJSON" | jq -r '.hostname')
PUBLICIPASN=$(echo "$DATAINJSON" | jq -r '.asn')

#Display data
if [ "$PUBLICIP" ]; then
    echo "$PUBLICIP"
    echo "$PUBLICIPCOUNTRY"
    echo "$PUBLICIPASNORG"
    echo "$PUBLICIPHOSTNAME"
    echo "$PUBLICIPASN"
else
    echo "No public IPv4 address detected"
fi

exit 0

