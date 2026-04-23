#!/bin/bash
# Monitor USB device add/remove events and play sounds

stdbuf -oL udevadm monitor --udev --subsystem-match=usb 2>/dev/null | while read -r line; do
    case "$line" in
        *"add"*"/usb"[0-9]*)
            # Skip hub events, only play for actual devices
            if echo "$line" | grep -qv "hub"; then
                canberra-gtk-play -i device-added 2>/dev/null &
            fi
            ;;
        *"remove"*"/usb"[0-9]*)
            if echo "$line" | grep -qv "hub"; then
                canberra-gtk-play -i device-removed 2>/dev/null &
            fi
            ;;
    esac
done
