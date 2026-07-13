#!/bin/bash
# Shows public IPv4 address and related details 

HOST="ifconfig.co"

#Fast DNS pre-check. Caps the wait at ~2s instead of the 20-30s stall a
#broken DNS otherwise causes (getaddrinfo retries the A and AAAA lookups
#across every configured nameserver before giving up). Two states:
#  124/137 - timeout had to stop getent: no nameserver answered in time
#  other   - getent returned non-zero on its own: resolution failed fast
#            (name not found, SERVFAIL, or no/refusing resolver)
timeout -k 1 2 getent hosts "$HOST" >/dev/null 2>&1
DNSRC=$?
if [ "$DNSRC" -ne 0 ]; then
    case "$DNSRC" in
        124|137) echo "DNS unreachable" ;;
        *)       echo "DNS failed" ;;
    esac
    #Conciously exiting with 0 to prevent error message in Python code that calls this script
    exit 0
fi

#Get all data in JSON format
DATAINJSON=$(timeout 3 curl -s --ipv4 "$HOST/json")
#Capture the curl/timeout exit code to give the failure a cause
RC=$?

if [ ! "$DATAINJSON" ]; then
    #Map the exit code to a short message so the FPMS screen has context
    #for why it failed instead of a generic "no address" line
    case "$RC" in
        6)      echo "DNS failure" ;;
        7)      echo "Network unreachable" ;;
        28|124) echo "Connection timed out" ;;
        *)      echo "No public IPv4 address detected" ;;
    esac
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
    if [ "$PUBLICIPHOSTNAME" == "null" ]; then
        : 
    else
        echo "$PUBLICIPHOSTNAME"
    fi
    echo "$PUBLICIPASN"
else
    echo "No public IPv4 address detected"
fi

exit 0

