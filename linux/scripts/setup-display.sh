#!/bin/bash
# Setup DP-4 as primary (125% scale) and DP-2 as extended secondary (right, 100% scale)
xrandr --output DP-4 --primary --auto --scale 0.8x0.8 --output DP-2 --auto --scale 1x1 --right-of DP-4
