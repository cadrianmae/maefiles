#!/usr/bin/env bash
# Record speaker SINK MONITOR (digital, what EE outputs) while playing baseline.
# Usage: ~/scripts/audio-tuning/record-baseline.sh <label>
set -euo pipefail

LABEL="${1:-no-effects}"
SINK_MONITOR="alsa_output.pci-0000_00_1f.3.analog-stereo.monitor"
INPUT="$HOME/Music/audio-tuning/laptop-speaker-baseline.wav"
OUTPUT="$HOME/Music/audio-tuning/recording-${LABEL}.wav"

if [ ! -f "$INPUT" ]; then
  echo "ERROR: $INPUT not found." >&2
  exit 1
fi

# Verify the monitor source exists
if ! pactl list sources short | awk '{print $2}' | grep -qx "$SINK_MONITOR"; then
  echo "ERROR: source '$SINK_MONITOR' not found. Available:" >&2
  pactl list sources short | awk '{print "  " $2}' >&2
  exit 1
fi

echo "==> Recording from sink monitor: $SINK_MONITOR"
echo "    Output: $OUTPUT"

# ffmpeg with pulse input is reliable about respecting -i source name
ffmpeg -hide_banner -loglevel warning -y \
  -f pulse -i "$SINK_MONITOR" \
  -ar 48000 -ac 2 -c:a pcm_s16le \
  "$OUTPUT" &
REC_PID=$!
sleep 0.4

echo "==> Playing baseline (4:55)"
paplay "$INPUT"

sleep 0.5
kill -INT "$REC_PID" 2>/dev/null || true
wait "$REC_PID" 2>/dev/null || true

echo "==> Done"
sox --i "$OUTPUT" 2>/dev/null | grep -E '(Duration|File Size)'
echo ""
echo "Listen back: mpv '$OUTPUT'"
