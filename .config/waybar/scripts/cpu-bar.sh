#!/bin/bash
# CPU usage with progress bar
percent=$(awk '/^cpu / {usage=100-($5*100/($2+$3+$4+$5+$6+$7+$8))} END {printf "%.0f", usage}' /proc/stat)
cores=$(nproc)
load=$(awk '{printf "%.2f, %.2f, %.2f", $1, $2, $3}' /proc/loadavg)
freq=$(awk '{printf "%.1f", $1/1000000}' /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null || echo "N/A")

tooltip="󰍛 CPU: ${percent}%\n${cores} cores @ ${freq} GHz\nLoad: ${load}"
~/.config/waybar/scripts/progress-bar.sh "$percent" "󰍛" "cpu" "$tooltip"
