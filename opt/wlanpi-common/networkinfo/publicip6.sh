#!/bin/bash
# Shows public IPv6 address and related details 

HOST="ifconfig.co"

#Fast DNS pre-check. Caps the wait at ~2s instead of the 20-30s stall a
#broken DNS otherwise causes (getaddrinfo retries the A and AAAA lookups
#across every configured nameserver before giving up). Two states:
#  124/137 - timeout had to stop getent: no nameserver answered in time
#  other   - getent returned non-zero on its own: resolution failed fast
#            (name not found, SERVFAIL, or no/refusing resolver)
#Resolution is transport-independent, so this correctly separates a DNS
#problem from the normal "no IPv6 connectivity" case handled below.
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
DATAINJSON=$(timeout 3 curl -s --ipv6 "$HOST/json")
#Capture the curl/timeout exit code to give the failure a cause
RC=$?

if [ ! "$DATAINJSON" ]; then
    #Map the exit code to a short message so the FPMS screen has context.
    #A failed IPv6 connection (RC 7) is the normal "no IPv6 here" case on
    #v4-only networks, so it falls through to the default message rather
    #than reporting an error.
    case "$RC" in
        6)      echo "DNS failure" ;;
        28|124) echo "Connection timed out" ;;
        *)      echo "No public IPv6 address detected" ;;
    esac
    #Conciously exiting with 0 to prevent error message in Python code that calls this script
    exit 0
fi

#Parse them
PUBLICIP=$(echo "$DATAINJSON" | jq -r '.ip')
PUBLICIPCOUNTRY=$(echo "$DATAINJSON" | jq -r '.country')
PUBLICIPASNORG=$(echo "$DATAINJSON" | jq -r '.asn_org')
PUBLICIPASN=$(echo "$DATAINJSON" | jq -r '.asn')

#Display data
if [ "$PUBLICIP" ]; then
    echo "$PUBLICIP"
    echo "$PUBLICIPCOUNTRY"
    echo "$PUBLICIPASNORG"
    echo "$PUBLICIPASN"
else
    echo "No public IPv6 address detected"
fi

exit 0

