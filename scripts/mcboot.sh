#!/bin/bash

# Wake-on-Wireless-LAN (WoWLAN) for MasterChief
# This works only if MasterChief is in SLEEP mode (mcsleep)
# MAC (Wi-Fi): C4:03:A8:37:38:81
# IP (Wi-Fi): 192.168.68.115

MAC="C4:03:A8:37:38:81"

echo "Attempting to wake MasterChief from Sleep ($MAC)..."
wakeonlan -i 192.168.68.255 "$MAC"
