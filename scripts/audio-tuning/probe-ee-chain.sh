#!/usr/bin/env bash
# Probe each EasyEffects plugin output stage in parallel while playing baseline.
# Records 5 WAVs (one per stage) + analyses per-band RMS to show what each plugin does.
set -euo pipefail

INPUT="$HOME/Music/audio-tuning/laptop-speaker-baseline.wav"
OUTDIR="$HOME/Music/audio-tuning/ee-probe-$(date +%H%M%S)"
mkdir -p "$OUTDIR"
cd "$OUTDIR"

STAGES=(
  "01-input:easyeffects_sink.monitor"
  "02-after-filter:ee_soe_filter"
  "03-after-bass-enhancer:ee_soe_bass_enhancer"
  "04-after-multiband:ee_soe_multiband_compressor"
  "05-after-stereo:ee_soe_stereo_tools"
  "06-after-limiter:ee_soe_limiter"
)

echo "==> Probing EE chain — output dir: $OUTDIR"

# Start all recorders BEFORE playback
PIDS=()
for entry in "${STAGES[@]}"; do
  label="${entry%:*}"
  target="${entry#*:}"
  echo "  starting recorder: $label  <-  $target"
  pw-record --target "$target" "${label}.wav" &
  PIDS+=($!)
done

sleep 0.6  # let recorders settle

echo "==> Playing baseline (4:55)"
paplay "$INPUT"

sleep 0.5
echo "==> Stopping recorders"
for pid in "${PIDS[@]}"; do
  kill -INT "$pid" 2>/dev/null || true
done
wait 2>/dev/null || true

echo ""
echo "==> Per-stage analysis"
echo ""
printf "%-30s %8s %8s %8s %8s %8s %8s %8s\n" "Stage" "20-80" "80-250" "250-500" "500-2k" "2k-5k" "5k-10k" "10k-20k"
echo "--------------------------------------------------------------------------------------------"
for entry in "${STAGES[@]}"; do
  label="${entry%:*}"
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
echo "==> Loudness per stage"
for entry in "${STAGES[@]}"; do
  label="${entry%:*}"
  f="${label}.wav"
  [ -f "$f" ] || continue
  summary=$(ffmpeg -hide_banner -nostats -i "$f" -af ebur128=peak=true -f null - 2>&1 | tail -25)
  I=$(echo "$summary" | awk '/^    I:/ {print $2}')
  TP=$(echo "$summary" | awk '/^    Peak:/ {print $2}')
  printf "  %-30s I=%-8s LUFS  TP=%s dBFS\n" "$label" "$I" "$TP"
done

echo ""
echo "Files: $OUTDIR/"
