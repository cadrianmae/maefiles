#!/bin/bash
# Memory usage with progress bar
read -r total used available <<< $(free -h | awk '/Mem:/ {print $2, $3, $7}')
percent=$(free | awk '/Mem:/ {printf "%.0f", $3/$2*100}')
swap=$(free -h | awk '/Swap:/ {printf "%s / %s", $3, $2}')

tooltip="󰘚 RAM: ${used} / ${total} (${percent}%)\nAvailable: ${available}\nSwap: ${swap}"
~/.config/waybar/scripts/progress-bar.sh "$percent" "󰘚" "memory" "$tooltip"
