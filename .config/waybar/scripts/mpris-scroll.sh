#!/bin/bash
# Scrolling MPRIS for waybar using zscroll

WIDTH=32

get_text() {
    text=$(playerctl metadata --format '{{ title }} - {{ artist }}' 2>/dev/null)
    printf "%-${WIDTH}s" "$text"
}

export -f get_text
export WIDTH

~/.local/bin/zscroll -l $WIDTH \
    -d 0.3 \
    -p "     " \
    -M "playerctl status" \
    -m "Paused" "--scroll false --before-text ' '" \
    -m "Playing" "--scroll true --before-text ' '" \
    -u true \
    "bash -c get_text"
