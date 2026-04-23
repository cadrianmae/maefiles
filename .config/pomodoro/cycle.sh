#!/usr/bin/env bash
# Runs a full 4-tomato cycle with breaks. Blocks until complete.
# Usage: cycle.sh <description> [-t tag] ...
#
# Env overrides:
#   POMO_DURATION=25  (minutes per tomato)
#   BREAK_DURATION=5  (minutes per short break)
#   LONG_BREAK=15     (minutes for long break at end)
#   TOMATOES=4        (tomatoes before long break)
set -euo pipefail

TOMATOES="${TOMATOES:-4}"
POMO_DURATION="${POMO_DURATION:-25}"
BREAK_DURATION="${BREAK_DURATION:-5}"
LONG_BREAK="${LONG_BREAK:-15}"

WATCHER_PID=""

cleanup() {
    [[ -n "$WATCHER_PID" ]] && kill "$WATCHER_PID" 2>/dev/null || true
    pomodoro cancel >/dev/null 2>&1 || true
    pomodoro clear  >/dev/null 2>&1 || true
    echo
    echo "Cycle interrupted. Pomodoro state cleared."
}
trap cleanup INT TERM

for i in $(seq 1 "$TOMATOES"); do
    echo "=== Tomato $i of $TOMATOES ($POMO_DURATION min) ==="
    # Spawn watcher in background for milestone announcements
    "$HOME/.config/pomodoro/watcher.sh" 5 1 &
    WATCHER_PID=$!

    pomodoro start --wait --duration "$POMO_DURATION" "$@"
    pomodoro finish >/dev/null 2>&1 || true

    kill "$WATCHER_PID" 2>/dev/null || true
    WATCHER_PID=""

    if [[ $i -lt $TOMATOES ]]; then
        echo "=== Break $i ($BREAK_DURATION min) ==="
        pomodoro break --wait "$BREAK_DURATION"
        pomodoro clear >/dev/null 2>&1 || true
    fi
done

echo "=== Long break ($LONG_BREAK min) ==="
pomodoro break --wait "$LONG_BREAK"
pomodoro clear >/dev/null 2>&1 || true

# Fire the stop hook for the "all-done" announcement
"$HOME/.pomodoro/hooks/stop"
