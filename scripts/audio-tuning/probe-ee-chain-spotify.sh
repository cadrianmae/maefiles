#!/usr/bin/env bash
# Probe each EE plugin output by manually linking taps via pw-link.
# Usage: ~/Music/.probe-ee-chain-spotify.sh [duration_seconds] [label]
set -euo pipefail

DURATION="${1:-60}"
LABEL="${2:-spotify}"
OUTDIR="$HOME/Music/ee-probe-${LABEL}-$(date +%H%M%S)"
mkdir -p "$OUTDIR"
cd "$OUTDIR"

# label : ee-node-name : port-prefix
STAGES=(
  "01-input:easyeffects_sink:monitor"
  "02-after-filter:ee_soe_filter:output"
  "03-after-bass-enhancer:ee_soe_bass_enhancer:output"
  "04-after-multiband:ee_soe_multiband_compressor:output"
  "05-after-stereo:ee_soe_stereo_tools:output"
  "06-after-limiter:ee_soe_limiter:output"
)

echo "==> Probing EE chain (manual pw-link taps) — output: $OUTDIR"
echo "==> Get Spotify ready, press ENTER to start recording for ${DURATION}s"
read -r

# Spawn one pw-cat recorder per stage, named so we can find them
PIDS=()
TAP_NAMES=()
for entry in "${STAGES[@]}"; do
  IFS=: read -r label src port <<< "$entry"
  tap_name="ee-tap-${label}"
  TAP_NAMES+=("$tap_name")

  pw-cat --record --target 0 \
    -P "node.name=${tap_name}" \
    -P "node.description=EE Tap ${label}" \
    --rate 48000 --channels 2 --format s16 \
    "${label}.wav" &
  PIDS+=($!)
done

sleep 0.8  # let all recorder nodes register

# Now manually link each plugin output to its tap node's inputs
for entry in "${STAGES[@]}"; do
  IFS=: read -r label src port <<< "$entry"
  tap_name="ee-tap-${label}"
  echo "  linking ${src}:${port}_FL -> ${tap_name}:input_FL"
  pw-link "${src}:${port}_FL" "${tap_name}:input_FL" 2>/dev/null || echo "    WARN: link FL failed"
  pw-link "${src}:${port}_FR" "${tap_name}:input_FR" 2>/dev/null || echo "    WARN: link FR failed"
done

sleep 0.4
echo ""
echo "==> Recording for ${DURATION}s — START PLAYBACK NOW"
sleep "$DURATION"

echo "==> Stopping"
for pid in "${PIDS[@]}"; do
  kill -INT "$pid" 2>/dev/null || true
done
wait 2>/dev/null || true

echo ""
echo "==> Per-stage analysis (RMS dB per frequency band)"
echo ""
printf "%-30s %8s %8s %8s %8s %8s %8s %8s\n" "Stage" "20-80" "80-250" "250-500" "500-2k" "2k-5k" "5k-10k" "10k-20k"
echo "--------------------------------------------------------------------------------------------"
for entry in "${STAGES[@]}"; do
  IFS=: read -r label _ _ <<< "$entry"
  f="${label}.wav"
  [ -f "$f" ] || continue
  vals=""
  for band in "20:80" "80:250" "250:500" "500:2000" "2000:5000" "5000:10000" "10000:20000"; do
    low="${band%:*}"; high="${band#*:}"
    rms=$(sox "$f" -n sinc "${low}-${high}" stats 2>&1 | awk '/RMS lev dB/ {print $4}')
    vals+=$(printf " %8s" "$rms")
  done
  printf "%-30s%s\n" "$label" "$vals"
done

echo ""
echo "==> Loudness + peak per stage"
for entry in "${STAGES[@]}"; do
  IFS=: read -r label _ _ <<< "$entry"
  f="${label}.wav"
  [ -f "$f" ] || continue
  summary=$(ffmpeg -hide_banner -nostats -i "$f" -af ebur128=peak=true -f null - 2>&1 | tail -25)
  I=$(echo "$summary" | awk '/^    I:/ {print $2}')
  TP=$(echo "$summary" | awk '/^    Peak:/ {print $2}')
  printf "  %-30s I=%-8s LUFS  TP=%s dBFS\n" "$label" "$I" "$TP"
done

echo ""
echo "==> Transient peak hunter (samples > -1 dBFS per stage)"
for entry in "${STAGES[@]}"; do
  IFS=: read -r label _ _ <<< "$entry"
  f="${label}.wav"
  [ -f "$f" ] || continue
  count=$(sox "$f" -n stats 2>&1 | awk '/Pk lev dB/ {print $4}')
  printf "  %-30s peak: %s dB\n" "$label" "$count"
done

echo ""
echo "Files: $OUTDIR/"
