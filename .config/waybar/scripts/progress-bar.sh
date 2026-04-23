#!/bin/bash
# Progress bar with icon in middle
# Usage: progress-bar.sh <percentage> <icon> [color-class] [tooltip]

percent=${1:-0}
icon=${2:-}
class=${3:-}
tooltip=${4:-"$percent%"}

# Bar settings
total=5
filled=$((percent * total / 100))
empty=$((total - filled))

# Determine alert class based on percentage
if [ "$percent" -ge 90 ]; then
    alert="critical"
elif [ "$percent" -ge 75 ]; then
    alert="warning"
else
    alert=""
fi

# Build bar: filled | icon | empty
left=""
right=""

for ((i=0; i<filled; i++)); do
    left+="▰"
done

for ((i=0; i<empty; i++)); do
    right+="▱"
done

# Output with icon in middle
echo "{\"text\": \"$left $icon $right\", \"percentage\": $percent, \"tooltip\": \"$tooltip\", \"class\": \"$alert\"}"
