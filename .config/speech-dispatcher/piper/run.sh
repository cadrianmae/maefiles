#!/bin/bash
# Piper synth runner for sd_generic
# Reads env vars set by sd_generic: VOICE, DATA, RATE, PITCH, VOLUME

# ---- NVIDIA CUDA library path (cached) ----------------------------------
# speech-dispatcher does not source the user's shell env, so onnxruntime-gpu
# CUDA libs (cublas, cudnn, etc.) won't be on LD_LIBRARY_PATH automatically.
# Compute once, cache to ~/.cache/piper-ld-path for subsequent calls.
_LD_CACHE="$HOME/.cache/piper-ld-path"
if [ -f "$_LD_CACHE" ]; then
    export LD_LIBRARY_PATH="$(cat "$_LD_CACHE")${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
else
    _nv_root="${HOME}/.local/lib/python$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null)/site-packages/nvidia"
    if [ -d "$_nv_root" ]; then
        _nv_paths=""
        for _nv_dir in "$_nv_root"/*/lib; do
            [ -d "$_nv_dir" ] && _nv_paths="${_nv_paths:+$_nv_paths:}$_nv_dir"
        done
        if [ -n "$_nv_paths" ]; then
            mkdir -p "$(dirname "$_LD_CACHE")"
            printf '%s' "$_nv_paths" > "$_LD_CACHE"
            export LD_LIBRARY_PATH="${_nv_paths}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
        fi
        unset _nv_paths _nv_dir
    fi
    unset _nv_root
fi
unset _LD_CACHE

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

# ---- Sample rate (cached per model) --------------------------------------
_SR_CACHE="$HOME/.cache/piper-sr-$(echo "$MODEL" | tr '/' '_')"
if [ -f "$_SR_CACHE" ]; then
    SR=$(cat "$_SR_CACHE")
else
    SR=$(jq -r '.audio.sample_rate' "$MODEL_PATH.json" 2>/dev/null || echo 22050)
    mkdir -p "$(dirname "$_SR_CACHE")"
    printf '%s' "$SR" > "$_SR_CACHE"
fi
unset _SR_CACHE

echo "MODEL=$MODEL SPK=$SPK SR=$SR SPKARG=$SPKARG" >> "$LOG"
echo "MODEL_PATH=$MODEL_PATH" >> "$LOG"

# Check the model file exists
if [ ! -f "$MODEL_PATH" ]; then
    echo "ERROR: model file not found: $MODEL_PATH" >> "$LOG"
    exit 1
fi

echo "stage:before synth" >> "$LOG"

# ---- Map speechd RATE/PITCH/VOLUME (-1.0..+1.0) to piper/paplay/sox ----------
# Baseline length_scale is 0.6 (historical personal default); RATE scales from
# there exponentially. VOLUME maps to paplay's 0..65536 range with 40000 base.
# PITCH maps to ±600 cents (±6 semitones) via sox; skipped if near zero.
RATE="${RATE:-0}"
PITCH="${PITCH:-0}"
VOLUME="${VOLUME:-0}"

LENGTH_SCALE=$(awk -v r="$RATE" 'BEGIN{ printf "%.3f", 0.6 * (2.0 ^ -r) }')
PAPLAY_VOLUME=$(awk -v v="$VOLUME" 'BEGIN{
    x = 40000 * (2.0 ^ v)
    if (x > 65536) x = 65536
    if (x < 0) x = 0
    printf "%d", x
}')
PITCH_CENTS=$(awk -v p="$PITCH" 'BEGIN{ printf "%d", p * 600 }')
export LENGTH_SCALE PAPLAY_VOLUME PITCH_CENTS

echo "mapped: LENGTH_SCALE=$LENGTH_SCALE PAPLAY_VOLUME=$PAPLAY_VOLUME PITCH_CENTS=$PITCH_CENTS" >> "$LOG"

# ---- Try daemon first, fall back to CLI if unavailable ----------------------
SOCK="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/piper-daemon.sock"

if [ -S "$SOCK" ]; then
    # Build speaker_id arg for JSON (only if multi-speaker voice)
    if [ -n "$SPK" ] && [ "$SPK" != "$MODEL" ]; then
        SPKJSON=",\"speaker_id\":$SPK"
    else
        SPKJSON=""
    fi

    # Default: client blocks until playback finishes (correct for sd_generic queueing).
    # PIPER_NOBLOCK=1 (env): client forks and parent returns immediately.
    if /home/cadrianmae/.config/speech-dispatcher/piper/client.py \
            "$SOCK" "$DATA" "$MODEL" "$SPKJSON" >>"$LOG" 2>&1; then
        echo "stage:daemon handling" >> "$LOG"
        echo "runner exit=0" >> "$LOG"
        exit 0
    fi
    echo "stage:daemon unavailable, falling back to CLI" >> "$LOG"
fi

echo "stage:using piper CLI" >> "$LOG"

# Default: block until playback finishes so sd_generic queues messages correctly.
# PIPER_NOBLOCK=1: detach for fire-and-forget callers.
if [ "$PIPER_NOBLOCK" = "1" ]; then
    setsid bash -c "
        printf '%s' \"\$1\" | /home/cadrianmae/.local/bin/piper \
            --cuda --length-scale 0.6 --sentence-silence 0.1 \
            --model \"\$2\" \$3 --output-raw 2>>\"$LOG\" \
        | paplay --raw --format=s16le --rate=\$4 --channels=1 --volume=40000 2>>\"$LOG\"
    " _ "$DATA" "$MODEL_PATH" "$SPKARG" "$SR" </dev/null >>"$LOG" 2>&1 &
    disown 2>/dev/null
    echo "stage:CLI detached pid=$!" >> "$LOG"
    echo "runner exit=0 (noblock)" >> "$LOG"
    exit 0
fi

# Build the pipeline: piper → [sox pitch] → paplay. sox is skipped when
# |PITCH_CENTS| < 10 to avoid the process spawn for near-zero values.
if [ "${PITCH_CENTS#-}" -ge 10 ] 2>/dev/null && command -v sox >/dev/null 2>&1; then
    printf '%s' "$DATA" | /home/cadrianmae/.local/bin/piper \
        --cuda --length-scale "$LENGTH_SCALE" --sentence-silence 0.1 \
        --model "$MODEL_PATH" $SPKARG \
        --output-raw 2>>"$LOG" \
    | sox -t raw -r "$SR" -e signed -b 16 -c 1 - \
          -t raw -r "$SR" -e signed -b 16 -c 1 - \
          pitch "$PITCH_CENTS" 2>>"$LOG" \
    | paplay --raw --format=s16le --rate="$SR" --channels=1 --volume="$PAPLAY_VOLUME" 2>>"$LOG"
else
    printf '%s' "$DATA" | /home/cadrianmae/.local/bin/piper \
        --cuda --length-scale "$LENGTH_SCALE" --sentence-silence 0.1 \
        --model "$MODEL_PATH" $SPKARG \
        --output-raw 2>>"$LOG" \
    | paplay --raw --format=s16le --rate="$SR" --channels=1 --volume="$PAPLAY_VOLUME" 2>>"$LOG"
fi
RC=$?
echo "stage:CLI sync done rc=$RC" >> "$LOG"
exit $RC
