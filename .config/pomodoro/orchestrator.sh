#!/usr/bin/env bash
# Orchestrates pomodoro state transitions: sting + voice + Obsidian log.
# Invoked by ~/.pomodoro/hooks/{start,break,stop} with the state as $1.
set -euo pipefail

STATE="${1:?state required: start|break|stop}"
SOUNDS_DIR="$HOME/.config/pomodoro/sounds"
VAULT_DAILY_DIR="$HOME/Documents/Computer Science TU856/Year 4/logs"
TODAY="$(date +%Y-%m-%d)"
NOTE_FILE="$VAULT_DAILY_DIR/$TODAY.md"
TIME_NOW="$(date +%H:%M)"
# Cache dir — preserves task desc/tags across state transitions, since
# break/stop hooks fire after the original pomodoro's state is gone.
CACHE_DIR="$HOME/.pomodoro/_cache"
mkdir -p "$CACHE_DIR"

# Pull current pomodoro context via format string. Fields:
#   %c = completed count today, %g = daily goal (from settings)
#   %d = description, %t = tags (comma-joined)
COUNT=$(pomodoro status -f "%c" 2>/dev/null || echo "0")
GOAL=$(pomodoro status -f "%g" 2>/dev/null || echo "0")
DESC=$(pomodoro status -f "%d" 2>/dev/null || echo "")
TAGS=$(pomodoro status -f "%t" 2>/dev/null || echo "")
[[ -z "$COUNT" ]] && COUNT="0"
[[ -z "$GOAL" ]] && GOAL="0"

# On start: cache the task info. On break/stop: restore from cache if current is empty.
if [[ "$STATE" == "start" ]]; then
    printf '%s' "$DESC" > "$CACHE_DIR/last_desc"
    printf '%s' "$TAGS" > "$CACHE_DIR/last_tags"
else
    [[ -z "$DESC" && -f "$CACHE_DIR/last_desc" ]] && DESC=$(cat "$CACHE_DIR/last_desc")
    [[ -z "$TAGS" && -f "$CACHE_DIR/last_tags" ]] && TAGS=$(cat "$CACHE_DIR/last_tags")
fi

# Approximate position in 4-tomato cycle (openpomodoro-cli doesn't track this).
CYCLE_POS=$(( (COUNT % 4) + 1 ))

play_sting() {
    paplay "$1" 2>/dev/null &
}

speak() {
    # -w waits for completion so stings/voice don't overlap.
    # Default piper voice (cori / en_GB-cori-high) is used automatically.
    spd-say -w "$1" 2>/dev/null || true
}

log_obsidian() {
    local line="$1"
    mkdir -p "$VAULT_DAILY_DIR"
    if [[ ! -f "$NOTE_FILE" ]]; then
        printf '# %s\n\n' "$(date '+%a %d %B %Y')" > "$NOTE_FILE"
    fi
    if ! grep -q '^## Pomodoros' "$NOTE_FILE"; then
        printf '\n## Pomodoros\n' >> "$NOTE_FILE"
    fi
    printf -- '- %s %s\n' "$TIME_NOW" "$line" >> "$NOTE_FILE"
}

case "$STATE" in
    start)
        play_sting "$SOUNDS_DIR/work-start.wav"
        sleep 0.4
        msg="Focus session started. Tomato $CYCLE_POS of 4."
        [[ -n "$DESC" ]] && msg="$msg Task: $DESC."
        msg="$msg $COUNT of $GOAL done today."
        speak "$msg"
        log_obsidian "started — ${DESC:-untitled}${TAGS:+ [$TAGS]}"
        ;;
    break)
        play_sting "$SOUNDS_DIR/break-start.wav"
        sleep 0.4
        msg="Tomato complete. Take a break."
        [[ -n "$DESC" ]] && msg="$msg Finished: $DESC."
        msg="$msg $COUNT of $GOAL done today."
        speak "$msg"
        log_obsidian "complete — ${DESC:-untitled} (${COUNT}/${GOAL})"
        ;;
    stop)
        play_sting "$SOUNDS_DIR/all-done.wav"
        sleep 0.5
        speak "Session ended. $COUNT of $GOAL done today."
        log_obsidian "session ended (${COUNT}/${GOAL})"
        ;;
    *)
        echo "unknown state: $STATE" >&2
        exit 2
        ;;
esac
