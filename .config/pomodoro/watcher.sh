#!/usr/bin/env bash
# Polls pomodoro status; fires milestone announcement at configured minutes remaining.
# Usage: watcher.sh [minute-thresholds...]   (default: 5 1)
# Exits silently when the pomodoro ends.
set -euo pipefail

THRESHOLDS=("$@")
[[ ${#THRESHOLDS[@]} -eq 0 ]] && THRESHOLDS=(5 1)

SOUNDS_DIR="$HOME/.config/pomodoro/sounds"
FIRED_FILE="$(mktemp)"
trap 'rm -f "$FIRED_FILE"' EXIT

fire_milestone() {
    local mins="$1"
    paplay "$SOUNDS_DIR/milestone.wav" 2>/dev/null &
    sleep 0.2
    if [[ "$mins" == "1" ]]; then
        spd-say -w "One minute remaining." 2>/dev/null || true
    else
        spd-say -w "$mins minutes remaining." 2>/dev/null || true
    fi
}

while true; do
    # %R = remaining minutes (rounded). Empty if no active pomodoro.
    remaining=$(pomodoro status -f "%R" 2>/dev/null || echo "")
    # Exit when pomodoro is gone or has expired (❗ in any field).
    if [[ -z "$remaining" ]] || [[ "$remaining" == *"❗"* ]]; then
        exit 0
    fi

    # Extract integer minutes
    mins=${remaining//[^0-9]/}
    [[ -z "$mins" ]] && { sleep 20; continue; }

    for t in "${THRESHOLDS[@]}"; do
        if [[ "$mins" == "$t" ]] && ! grep -qx "$t" "$FIRED_FILE" 2>/dev/null; then
            fire_milestone "$t"
            echo "$t" >> "$FIRED_FILE"
        fi
    done

    sleep 20
done
