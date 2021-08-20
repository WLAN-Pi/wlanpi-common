# Common WLAN Pi scripts and files

These are support scripts and files used by other WLAN Pi packages on the RPi4/CM4 platforms.

Previously, some of these files were part of the FPMS package.

## Components

networkinfo scripts deliver features like CDP/LLDP neighbour detection, allow you to display public IP address, check reachability of internet services or blink eth0 LEDs and allow you to trace an unknown Ethernet cable and a switch port it connects to. 

## Installation instructions

The goal is to make `wlan-pi-fpms` package depend on `wlanpi-common`.

Assuming you are using one of the newer images running WLAN Pi OS, you can install `wlanpi-common` by executing `apt install wlanpi-common`.
