#!/bin/bash
LOG_FILE="/home/cadrianmae/power-events.log"
echo "$(date '+%Y-%m-%d %H:%M:%S'): Power event detected" >> "$LOG_FILE"
journalctl -b | grep -iE "suspend|hibernate|resume" | tail -5 >> "$LOG_FILE"

# Check for ACTUAL errors (failed, timeout, black screen keywords)
ERROR_CHECK=$(journalctl -b -p err | grep -iE "nvidia|suspend|hibernate" | grep -iE "fail|timeout|black|freeze|hung" | tail -3)
if [ -n "$ERROR_CHECK" ]; then
    echo "⚠️ REAL ERRORS DETECTED:" >> "$LOG_FILE"
    echo "$ERROR_CHECK" >> "$LOG_FILE"
fi
echo "---" >> "$LOG_FILE"
