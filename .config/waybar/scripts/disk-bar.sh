#!/bin/bash
# Disk usage with progress bar
read -r size used avail percent_raw <<< $(df -h / | awk 'NR==2 {print $2, $3, $4, $5}')
percent=${percent_raw%\%}
mount=$(df / | awk 'NR==2 {print $1}')

tooltip="󰋊 Disk (/): ${used} / ${size} (${percent}%)\nAvailable: ${avail}\nMount: ${mount}"
~/.config/waybar/scripts/progress-bar.sh "$percent" "󰋊" "disk" "$tooltip"
