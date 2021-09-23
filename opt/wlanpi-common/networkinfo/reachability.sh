#!/bin/bash
# Checks reachability of default gateway, internet connectivity, DNS resolution, arpings default gateway

# --- Clean up ---
function cleanup () {
  rm -r "$TMPDIR" &>/dev/null
}
#Clean up now
cleanup

# --- Variables ---
TMPDIR="/tmp/reachability"
DEFAULTGATEWAY=$(ip route | grep "default" | grep -E -o "([0-9]{1,3}[\.]){3}[0-9]{1,3}" | head -n1)
DGINTERFACE=$(ip route | grep "default" | head -n1 | cut -d ' ' -f5)
DNSSERVERCOUNT=$(cat /etc/resolv.conf | grep "nameserver" | cut -d ' ' -f2 | wc -l)

if [ "$DNSSERVERCOUNT" -eq 1 ]; then
  DNSSERVER1=$(cat /etc/resolv.conf | grep "nameserver" -m1 | cut -d ' ' -f2)
fi

if [ "$DNSSERVERCOUNT" -eq 2 ]; then
  DNSSERVER1=$(cat /etc/resolv.conf | grep "nameserver" -m1 | cut -d ' ' -f2)
  DNSSERVER2=$(cat /etc/resolv.conf | grep "nameserver" | head -2 | tail -1 | cut -d ' ' -f2)
fi

if [ "$DNSSERVERCOUNT" -gt 2 ]; then
  DNSSERVER1=$(cat /etc/resolv.conf | grep "nameserver" -m1 | cut -d ' ' -f2)
  DNSSERVER2=$(cat /etc/resolv.conf | grep "nameserver" | head -2 | tail -1 | cut -d ' ' -f2)
  DNSSERVER3=$(cat /etc/resolv.conf | grep "nameserver" | head -3 | tail -1 | cut -d ' ' -f2)
fi

# --- Checks ---
#Prevent multiple instances of the script to run at the same time
for pid in $(pidof -x $0); do
  if [ $pid != $$ ]; then
    echo "Another instance of the script is already running. Wait for it to finish first."
    exit 1
  fi
done

if [ ! "$DEFAULTGATEWAY" ]; then
  echo "No default gateway"
  exit 0
fi

# --- Start tests ---
mkdir "$TMPDIR" &>/dev/null

{ timeout 2 ping -c1 -W2 -q google.com; } &> "$TMPDIR/pinggoogle.txt" &
{ timeout 2 curl -s -L www.google.com | grep "google.com" &>/dev/null; echo $?; } &> "$TMPDIR/browsegoogle.txt" &
{ ping -c1 -W2 -q "$DEFAULTGATEWAY"; } &> "$TMPDIR/pinggateway.txt" &

if [ "$DNSSERVER1" ]; then
{ dig +short +time=2 +tries=1 @"$DNSSERVER1" NS google.com &>/dev/null; echo $?; } &> "$TMPDIR/dns1.txt" &
fi

if [ "$DNSSERVER2" ]; then
{ dig +short +time=2 +tries=1 @"$DNSSERVER2" NS google.com &>/dev/null; echo $?; } &> "$TMPDIR/dns2.txt" &
fi

if [ "$DNSSERVER3" ]; then
{ dig +short +time=2 +tries=1 @"$DNSSERVER3" NS google.com &>/dev/null; echo $?; } &> "$TMPDIR/dns3.txt" &
fi

{ timeout 2 arping -c1 -w2 -I "$DGINTERFACE" "$DEFAULTGATEWAY" 2>/dev/null; }  &> "$TMPDIR/arpinggateway.txt" &

#Wait for all tests to finish
wait


# --- Print output ---

#Ping Google
PINGGOOGLERTT=$(grep "rtt" "$TMPDIR/pinggoogle.txt" | cut -d "." -f2 | cut -d "/" -f2)
  if [ "$PINGGOOGLERTT" ]; then
    PINGGOOGLERTT="${PINGGOOGLERTT}ms"
    PINGGOOGLESTR1="Ping Google:"
    PINGGOOGLESPACES=$((20-${#PINGGOOGLERTT}-${#PINGGOOGLESTR1}))
    PINGGOOGLESTR2=$(echo "$PINGGOOGLERTT" | sed ':lbl; /^ \{'$PINGGOOGLESPACES'\}/! {s/^/ /;b lbl}')
    echo "${PINGGOOGLESTR1}${PINGGOOGLESTR2}"
  else
    echo "Ping Google:    FAIL"
  fi

#Browse Google.com page
BROWSEGOOGLERET=$(<"$TMPDIR/browsegoogle.txt")
[ "$BROWSEGOOGLERET" == "0" ] && echo "Browse Google:    OK" || echo "Browse Google:  FAIL"

#Ping default gateway
PINGDGRTT=$(grep "rtt" "$TMPDIR/pinggateway.txt" | cut -d "." -f2 | cut -d "/" -f2)
  if [ "$PINGDGRTT" ]; then
    PINGDGRTT="${PINGDGRTT}ms"
    PINGDGSTR1="Ping Gateway:"
    PINGDGSPACES=$((20-${#PINGDGRTT}-${#PINGDGSTR1}))
    PINGDGSTR2=$(echo "$PINGDGRTT" | sed ':lbl; /^ \{'$PINGDGSPACES'\}/! {s/^/ /;b lbl}')
    echo "${PINGDGSTR1}${PINGDGSTR2}"
  else
    echo "Ping Gateway:   FAIL"
  fi

#Check if primary and secondary DNS servers can translate google.com
if [ "$DNSSERVER1" ]; then
  DNS1RET=$(<"$TMPDIR/dns1.txt")
  [ "$DNS1RET" == "0" ] && echo "Pri DNS Resol:    OK" || echo "Pri DNS Resol:  FAIL"
fi

if [ "$DNSSERVER2" ]; then
  DNS2RET=$(<"$TMPDIR/dns2.txt")
  [ "$DNS2RET" == "0" ] && echo "Sec DNS Resol:    OK" || echo "Sec DNS Resol:  FAIL"
fi

if [ "$DNSSERVER3" ]; then
  DNS3RET=$(<"$TMPDIR/dns3.txt")
  [ "$DNS3RET" == "0" ] && echo "Ter DNS Resol:    OK" || echo "Ter DNS Resol:  FAIL"
fi

#ARPing default gateway - useful if gateway is configured not to respond to pings
ARPINGRTT=$(grep "ms" "$TMPDIR/arpinggateway.txt" | cut -d " " -f7 | cut -d "." -f1)
  if [ "$ARPINGRTT" ]; then
    ARPINGRTT="${ARPINGRTT}ms"
    ARPINGSTR1="Arping Gateway:"
    ARPINGSPACES=$((20-${#ARPINGRTT}-${#ARPINGSTR1}))
    ARPINGSTR2=$(echo "$ARPINGRTT" | sed ':lbl; /^ \{'$ARPINGSPACES'\}/! {s/^/ /;b lbl}')
    echo "${ARPINGSTR1}${ARPINGSTR2}"
  else
    echo "Arping Gateway: FAIL"
  fi

#Clean up now
cleanup

exit 0
