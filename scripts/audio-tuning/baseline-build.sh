#!/usr/bin/env bash
# Build a 4:55 laptop speaker test file from 4 YouTube segments + 15s brown noise.
# All segments loudness-normalised to -16 LUFS (EBU R128) so they sound equally loud.
# Output: ~/Music/audio-tuning/laptop-speaker-baseline.wav
set -euo pipefail

OUT="$HOME/Music/audio-tuning/laptop-speaker-baseline.wav"
TMP="$HOME/Music/audio-tuning/.baseline-tmp"
TARGET_LUFS=-14    # Spotify/YouTube/Tidal Normal
TARGET_TP=-1.0     # true peak ceiling
TARGET_LRA=11      # loudness range
mkdir -p "$TMP"
cd "$TMP"

# segments: index|youtube_id|start_sec|duration_sec|label
SEGMENTS=(
  "1|GtOcxj3NDBI|30|70|norah-jones-dont-know-why"
  "2|5NV6Rdv1a3I|46|70|daft-punk-get-lucky"
  "3|HUHC9tYz8ik|60|70|billie-eilish-bury-a-friend"
  "4|oJ11Vq6N7rk|30|70|steely-dan-hey-nineteen"
)

normalize_lufs() {
  # 2-pass loudnorm for accurate target loudness.
  # $1=input wav  $2=output wav
  local in="$1" out="$2"
  echo "    pass 1/2: measuring loudness"
  local stats json
  stats=$(ffmpeg -hide_banner -nostats -i "$in" \
    -af "loudnorm=I=${TARGET_LUFS}:TP=${TARGET_TP}:LRA=${TARGET_LRA}:print_format=json" \
    -f null - 2>&1)
  # Extract just the JSON block (between first { and matching })
  json=$(echo "$stats" | sed -n '/^{$/,/^}$/p')
  local I TP LRA THRESH
  I=$(echo      "$json" | grep -oP '"input_i"\s*:\s*"\K[-0-9.]+')
  TP=$(echo     "$json" | grep -oP '"input_tp"\s*:\s*"\K[-0-9.]+')
  LRA=$(echo    "$json" | grep -oP '"input_lra"\s*:\s*"\K[-0-9.]+')
  THRESH=$(echo "$json" | grep -oP '"input_thresh"\s*:\s*"\K[-0-9.]+')
  if [ -z "$I" ] || [ -z "$TP" ] || [ -z "$LRA" ] || [ -z "$THRESH" ]; then
    echo "    ERROR: failed to parse loudnorm output" >&2
    echo "$stats" | tail -25 >&2
    return 1
  fi
  echo "    pass 2/2: applying (measured I=${I} TP=${TP} LRA=${LRA})"
  ffmpeg -hide_banner -loglevel error -y -i "$in" \
    -af "loudnorm=I=${TARGET_LUFS}:TP=${TARGET_TP}:LRA=${TARGET_LRA}:measured_I=${I}:measured_TP=${TP}:measured_LRA=${LRA}:measured_thresh=${THRESH}:linear=true:print_format=summary" \
    -ar 48000 -ac 2 -c:a pcm_s16le "$out"
}

echo "==> Generating 15s brown noise reference (then loudness-normalising)"
sox -n -r 48000 -b 16 -c 2 00-brownnoise-raw.wav synth 15 brownnoise gain -6
normalize_lufs 00-brownnoise-raw.wav 00-brownnoise.wav

for seg in "${SEGMENTS[@]}"; do
  IFS='|' read -r idx vid start dur label <<< "$seg"
  full="full-${idx}.wav"
  trimmed="trim-${idx}.wav"
  out="${idx}-${label}.wav"

  if [ ! -f "$full" ]; then
    echo "==> [$idx] downloading: $label"
    yt-dlp -q --no-warnings \
      -x --audio-format wav --audio-quality 0 \
      -o "full-${idx}.%(ext)s" \
      "https://youtube.com/watch?v=${vid}"
  else
    echo "==> [$idx] cached: $label"
  fi

  echo "    trimming ${start}s..$((start+dur))s"
  sox "$full" -r 48000 -b 16 -c 2 "$trimmed" \
    trim "$start" "$dur" \
    fade 0.5 "$dur" 0.5
  normalize_lufs "$trimmed" "$out"
done

echo "==> Concatenating final file"
sox 00-brownnoise.wav 1-*.wav 2-*.wav 3-*.wav 4-*.wav "$OUT"

echo ""
echo "Done: $OUT"
sox --i "$OUT"
echo ""
echo "==> Per-segment loudness check:"
for f in 00-brownnoise.wav 1-*.wav 2-*.wav 3-*.wav 4-*.wav; do
  rms=$(sox "$f" -n stats 2>&1 | awk '/RMS lev dB/ {print $4}')
  printf "  %-40s RMS %s dB\n" "$f" "$rms"
done
echo ""
echo "Listen with: paplay '$OUT'    or    mpv '$OUT'"
