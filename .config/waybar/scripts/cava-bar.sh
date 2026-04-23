#!/bin/bash
# Cava visualizer for waybar

bar_chars="▁▂▃▄▅▆▇█"

# Kill any existing cava for waybar
pkill -f "cava -p.*waybar.conf" 2>/dev/null

cava -p ~/.config/cava/waybar.conf 2>/dev/null | while IFS=';' read -ra vals; do
    output=""
    for val in "${vals[@]}"; do
        [ -n "$val" ] && output+="${bar_chars:$val:1}"
    done
    [ -n "$output" ] && echo "$output"
done
