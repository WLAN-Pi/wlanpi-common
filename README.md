# Common WLAN Pi scripts and files

These are support scripts and files used by other WLAN Pi packages on the RPi4/CM4 platforms.

Previously, some of these files were part of the `fpms` package. This has now changed and `wlanpi-fpms` depends on this new standalone `wlanpi-common` package.

## Components

networkinfo scripts deliver features like CDP/LLDP neighbour detection, allow you to display public IP address, check reachability of internet services or blink eth0 LEDs and allow you to trace an unknown Ethernet cable and a switch port it connects to. 

## MOTD tips
After you SSH to WLAN Pi you will notive Tips in the MOTD. More of them can be added in a one-per-line fashion here: /opt/wlanpi-common/motd-tips.txt

## Installation instructions

Assuming you are using one of the newer images running WLAN Pi OS, you can install or upgrade `wlanpi-common` by executing `sudo apt update && sudo apt install wlanpi-common`.
