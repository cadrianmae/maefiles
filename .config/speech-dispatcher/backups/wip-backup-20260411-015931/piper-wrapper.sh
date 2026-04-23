#!/bin/bash
# Wrapper script for Piper TTS with Speech Dispatcher
# Handles: voice selection, multi-speaker voices, streaming output
#
# Env vars provided by sd_generic:
#   VOICE   - voice model filename, optionally suffixed with :N for speaker id
#             (e.g. "en_GB-semaine-medium.onnx:1" for speaker 1)
#   DATA    - text to speak
#   RATE    - speech rate (-100 to 100, pass-through)
#   PITCH   - pitch (-100 to 100, pass-through)
#   VOLUME  - volume (-100 to 100, pass-through)

PIPER_BIN="/home/cadrianmae/.local/bin/piper"
VOICES_DIR="/home/cadrianmae/.local/share/piper-voices"

# ---- Parse VOICE string into filename and optional speaker id ----
VOICE_FILE="${VOICE%:*}"
SPEAKER="${VOICE#*:}"
if [ "$VOICE_FILE" = "$SPEAKER" ]; then
    SPEAKER_ARG=""
else
    SPEAKER_ARG="--speaker $SPEAKER"
fi

# ---- Read native sample rate from voice JSON ----
SAMPLE_RATE=$(jq -r '.audio.sample_rate' "$VOICES_DIR/$VOICE_FILE.json" 2>/dev/null || echo 22050)

# ---- Convert SD parameters to Piper/mpv/sox values ----
# SD VOLUME is -100..100. Map to mpv 0..100 with a mild default (65% at SD 0).
# Clamp defensively.
MPV_VOL=$(( (VOLUME + 100) * 65 / 100 ))
[ "$MPV_VOL" -gt 100 ] && MPV_VOL=100
[ "$MPV_VOL" -lt 0 ] && MPV_VOL=0

# SD RATE is -100..100. Map to Piper --length-scale (0.1 fast .. 1.5 slow).
# SD 0 (default) -> 0.6 (slightly faster than natural, matches previous setup)
PIPER_LENGTH=$(awk "BEGIN {v=0.6 - ($RATE * 0.004); if(v<0.1)v=0.1; if(v>1.5)v=1.5; print v}")

# SD PITCH is -100..100. Map to sox pitch cents (-500 .. 500). SD 0 -> 0 (neutral).
SOX_PITCH=$(( PITCH * 5 ))

# ---- Run the Piper pipeline ----
# Piper streams raw PCM as sentences are synthesised.
# sox applies pitch only (no volume, no norm, no tempo — streaming friendly).
# mpv handles final volume on its 0..100 scale and plays with minimal buffering.
printf %s "$DATA" \
  | "$PIPER_BIN" \
      --length-scale "$PIPER_LENGTH" \
      --sentence-silence 0.1 \
      --model "$VOICES_DIR/$VOICE_FILE" \
      $SPEAKER_ARG \
      --output-raw \
      -f - 2>/dev/null \
  | sox \
      -r "$SAMPLE_RATE" \
      -c 1 \
      -b 16 \
      -e signed-integer \
      -t raw - \
      -t wav - \
      pitch "$SOX_PITCH" 2>/dev/null \
  | mpv --no-terminal --keep-open=no --cache=no --demuxer-max-bytes=32KiB \
        --volume="$MPV_VOL" - 2>/dev/null
