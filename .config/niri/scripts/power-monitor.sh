#!/bin/bash
# Monitor power/charging state changes and play sounds

POWER_SUPPLY="/sys/class/power_supply/AC"
[ ! -d "$POWER_SUPPLY" ] && POWER_SUPPLY="/sys/class/power_supply/ACAD"
[ ! -d "$POWER_SUPPLY" ] && exit 1

LAST_STATE=""

while true; do
    if [ -f "$POWER_SUPPLY/online" ]; then
        CURRENT=$(cat "$POWER_SUPPLY/online")
        if [ -n "$LAST_STATE" ] && [ "$CURRENT" != "$LAST_STATE" ]; then
            if [ "$CURRENT" = "1" ]; then
                canberra-gtk-play -i power-plug 2>/dev/null
            else
                canberra-gtk-play -i power-unplug 2>/dev/null
            fi
        fi
        LAST_STATE="$CURRENT"
    fi
    sleep 2
done
