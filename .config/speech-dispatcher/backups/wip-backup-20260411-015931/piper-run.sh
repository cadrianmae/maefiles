#!/bin/bash
# Piper synth runner for sd_generic
# Reads env vars set by sd_generic: VOICE, DATA, RATE, PITCH, VOLUME

LOG=/tmp/piper-debug.log
{
  echo "--- runner $(date +%H:%M:%S.%N) ---"
  echo "VOICE=[$VOICE]"
  echo "DATA=[$DATA]"
  echo "RATE=[$RATE] PITCH=[$PITCH] VOLUME=[$VOLUME]"
} >> "$LOG" 2>&1

# Parse voice:speaker syntax
MODEL="${VOICE%:*}"
SPK="${VOICE#*:}"
if [ "$MODEL" = "$SPK" ]; then
    SPKARG=""
else
    SPKARG="--speaker $SPK"
fi

MODEL_PATH="/home/cadrianmae/.local/share/piper-voices/$MODEL"
SR=$(jq -r '.audio.sample_rate' "$MODEL_PATH.json" 2>/dev/null || echo 22050)

echo "MODEL=$MODEL SPK=$SPK SR=$SR SPKARG=$SPKARG" >> "$LOG"
echo "MODEL_PATH=$MODEL_PATH" >> "$LOG"

# Check the model file exists
if [ ! -f "$MODEL_PATH" ]; then
    echo "ERROR: model file not found: $MODEL_PATH" >> "$LOG"
    exit 1
fi

echo "stage:before synth" >> "$LOG"

# Synthesize to tmp WAV file (NOT --output-raw which ignores -f and goes to stdout)
TMPWAV=$(mktemp /tmp/piper-out.XXXXX.wav)
echo "TMPWAV=$TMPWAV" >> "$LOG"

printf %s "$DATA" | /home/cadrianmae/.local/bin/piper \
      --length-scale 0.6 \
      --sentence-silence 0.1 \
      --model "$MODEL_PATH" \
      $SPKARG \
      -f "$TMPWAV" 2>>"$LOG"
PIPER_EXIT=$?
SIZE=$(stat -c%s "$TMPWAV" 2>/dev/null || echo 0)
echo "stage:after piper exit=$PIPER_EXIT size=$SIZE" >> "$LOG"

if [ ! -s "$TMPWAV" ]; then
    echo "ERROR: piper produced empty file" >> "$LOG"
    rm -f "$TMPWAV"
    exit 1
fi

# Detach playback with setsid so SD's process-group kill doesn't reach paplay.
# paplay auto-detects WAV format from header.
setsid bash -c "paplay --volume=40000 '$TMPWAV' 2>>'$LOG'; rm -f '$TMPWAV'" </dev/null >>"$LOG" 2>&1 &
disown 2>/dev/null

echo "stage:detached playback pid=$!" >> "$LOG"
echo "runner exit=0" >> "$LOG"
exit 0
