#!/bin/bash

# Aggressive Wake-on-LAN for Thanatos
# MAC: E8:9C:25:38:4C:63

MAC="E8:9C:25:38:4C:63"

echo "Sending aggressive Magic Packets to Thanatos (E8:9C:25:38:4C:63)..."
python3 ~/mac-forge/scripts/thboot.py

echo "Done. If it doesn't wake, check if the Ethernet lights are still blinking on the back of the PC."
