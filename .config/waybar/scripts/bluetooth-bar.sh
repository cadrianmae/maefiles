#!/bin/bash
# Custom bluetooth module with device icons and battery

# Check if bluetooth is powered
powered=$(bluetoothctl show 2>/dev/null | grep "Powered:" | awk '{print $2}')

if [ "$powered" != "yes" ]; then
    echo '{"text": "󰂲", "tooltip": "Bluetooth off", "class": "off"}'
    exit 0
fi

# Get connected devices
devices=$(bluetoothctl devices Connected 2>/dev/null | cut -d' ' -f2-)

if [ -z "$devices" ]; then
    echo '{"text": "󰂯", "tooltip": "Bluetooth on - No devices", "class": ""}'
    exit 0
fi

# Device type icons
get_device_icon() {
    local info="$1"
    case "$info" in
        *[Hh]eadphone*|*[Hh]eadset*|*[Bb]uds*|*[Aa]irpod*|*WH-*|*WF-*)
            echo "󰋋" ;;
        *[Mm]ouse*|*MX*|*[Tt]rackpad*)
            echo "󰍽" ;;
        *[Kk]eyboard*)
            echo "󰌌" ;;
        *[Cc]ontroller*|*[Gg]amepad*|*Xbox*|*PlayStation*|*DualSense*)
            echo "󰊗" ;;
        *[Ss]peaker*|*[Ss]oundbar*)
            echo "󰓃" ;;
        *[Pp]hone*|*iPhone*|*Galaxy*|*Pixel*)
            echo "󰏲" ;;
        *[Ww]atch*)
            echo "󰖉" ;;
        *)
            echo "󰂱" ;;
    esac
}

# Battery icon based on level
get_battery_icon() {
    local level=$1
    if [ -z "$level" ] || [ "$level" = "" ]; then
        echo ""
        return
    fi
    if [ "$level" -ge 90 ]; then
        echo "󰁹"
    elif [ "$level" -ge 70 ]; then
        echo "󰂁"
    elif [ "$level" -ge 50 ]; then
        echo "󰁿"
    elif [ "$level" -ge 30 ]; then
        echo "󰁽"
    elif [ "$level" -ge 10 ]; then
        echo "󰁻"
    else
        echo "󰂃"
    fi
}

text=""
tooltip="󰂯 Bluetooth\n"
alert=""
low_battery=false

while IFS= read -r line; do
    mac=$(echo "$line" | awk '{print $1}')
    name=$(echo "$line" | cut -d' ' -f2-)

    # Get device info for icon detection
    info=$(bluetoothctl info "$mac" 2>/dev/null)
    device_icon=$(get_device_icon "$name $info")

    # Get battery percentage
    battery=$(echo "$info" | grep "Battery Percentage" | grep -oP '\(\K\d+' | head -1)

    if [ -n "$battery" ]; then
        battery_icon=$(get_battery_icon "$battery")
        text+="${device_icon} ${battery_icon}  "
        tooltip+="${device_icon} ${name}: ${battery}%\n"

        # Check for low battery
        if [ "$battery" -le 20 ]; then
            low_battery=true
        fi
    else
        text+="${device_icon}  "
        tooltip+="${device_icon} ${name}\n"
    fi
done <<< "$devices"

# Remove trailing space
text="${text% }"

# Set alert class for low battery
if $low_battery; then
    alert="warning"
fi

echo "{\"text\": \"$text\", \"tooltip\": \"$tooltip\", \"class\": \"$alert\"}"
