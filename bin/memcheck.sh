#!/bin/bash

# Check memory usage and send notification if over 90%
MEM_USAGE=$(free | grep Mem | awk '{print ($3/$2) * 100.0}')
TOP_PROCS=$(ps aux --sort=-%mem | awk 'NR<=4 {if(NR>1) print $11": "$4"%"}' | tr '\n' ', ' | sed 's/,$//')
THRESHOLD=85

if (( $(echo "$MEM_USAGE > $THRESHOLD" | bc -l) )); then
    notify-send -i dialog-warning -u critical "High Memory Usage! " "Memory at ${MEM_USAGE}%\n\nTop culprits:\n${TOP_PROCS}" && paplay ./.local/share/sounds/modern-minimal-ui-sounds-v1.1/stereo/dialog-error-critical.oga
fi
