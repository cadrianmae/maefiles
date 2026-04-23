#!/usr/bin/env bash
# Regenerates pomodoro stings. Idempotent — rerun to redesign.
# Aesthetic: lo-fi minimal with timer character + warm synth bass bed.
set -euo pipefail

SOUNDS_DIR="$(dirname "$0")/sounds"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$SOUNDS_DIR"

# ---- WORK START ----
# 2-bar swung triangle motif in C major (tonic pedal bass).
# Bar 1 climbs C-E-G-E; bar 2 returns G-E-C-E. Quick "ready to go" feel,
# shares tone family with break-start and all-done.
sox -n -r 44100 -c 2 "$TMP/work-top.wav" \
    synth 0.33 triangle 523 fade 0.02 0.33 0.25 \
    : synth 0.17 triangle 659 fade 0.02 0.17 0.12 \
    : synth 0.33 triangle 784 fade 0.02 0.33 0.25 \
    : synth 0.17 triangle 659 fade 0.02 0.17 0.12 \
    : synth 0.33 triangle 784 fade 0.02 0.33 0.25 \
    : synth 0.17 triangle 659 fade 0.02 0.17 0.12 \
    : synth 0.33 triangle 523 fade 0.02 0.33 0.25 \
    : synth 0.17 triangle 659 fade 0.02 0.17 0.12
# Bass: C4 (262Hz) tonic pedal for 2 bars
sox -n -r 44100 -c 2 "$TMP/work-bass.wav" \
    synth 2.0 sine 262 fade 0.05 2.0 0.2 vol 0.55
sox -m "$TMP/work-top.wav" "$TMP/work-bass.wav" "$SOUNDS_DIR/work-start.wav" \
    pad 0 1.5 reverb 50 60 85 norm -6

# ---- BREAK START ----
# 4-bar chord progression in E minor: i - VI - VII - i  (Em - C - D - Em).
# Triangle melody bars 1-3 (Idea 2 motif). Bar 4 = Em triad (E-G-B) played
# staggered (80ms offsets) with bell-like partials on each note.
sox -n -r 44100 -c 2 "$TMP/break-mel.wav" \
    synth 0.33 triangle 988 fade 0.02 0.33 0.25 \
    : synth 0.17 triangle 784 fade 0.02 0.17 0.12 \
    : synth 0.33 triangle 659 fade 0.02 0.33 0.25 \
    : synth 0.17 triangle 784 fade 0.02 0.17 0.12 \
    : synth 0.33 triangle 784 fade 0.02 0.33 0.25 \
    : synth 0.17 triangle 659 fade 0.02 0.17 0.12 \
    : synth 0.33 triangle 523 fade 0.02 0.33 0.25 \
    : synth 0.17 triangle 659 fade 0.02 0.17 0.12 \
    : synth 0.33 triangle 880 fade 0.02 0.33 0.25 \
    : synth 0.17 triangle 740 fade 0.02 0.17 0.12 \
    : synth 0.33 triangle 587 fade 0.02 0.33 0.25 \
    : synth 0.17 triangle 740 fade 0.02 0.17 0.12
# Staggered Em triad: E5 at 0ms, G5 at 80ms, B5 at 160ms. Sine bell tones with
# inharmonic partials. 4.0s each with logarithmic fade = physically accurate
# bell decay (even drop in dB over time, mimicking real resonant decay).
sox -n -r 44100 -c 2 "$TMP/break-e.wav" \
    synth 4.0 sine 659 sine 1977 sine 3295 fade l 0.02 4.0 3.9
sox -n -r 44100 -c 2 "$TMP/break-g.wav" \
    synth 4.0 sine 784 sine 2352 sine 3920 fade l 0.02 4.0 3.9 pad 0.08 0
sox -n -r 44100 -c 2 "$TMP/break-b.wav" \
    synth 4.0 sine 988 sine 2964 sine 4940 fade l 0.02 4.0 3.9 pad 0.16 0
sox -m "$TMP/break-e.wav" "$TMP/break-g.wav" "$TMP/break-b.wav" "$TMP/break-chord.wav" norm -1
# Concatenate melody + staggered chord
sox "$TMP/break-mel.wav" "$TMP/break-chord.wav" "$TMP/break-top.wav"
# Bass: chord root per bar. Bar 4 extended to 4.5s with log fade to ring out
# naturally under the bell chord.
sox -n -r 44100 -c 2 "$TMP/break-bass.wav" \
    synth 1.0 sine 165 fade 0.05 1.0 0.1 \
    : synth 1.0 sine 131 fade 0.02 1.0 0.1 \
    : synth 1.0 sine 147 fade 0.02 1.0 0.1 \
    : synth 4.5 sine 165 fade l 0.02 4.5 4.3 vol 0.6
sox -m "$TMP/break-top.wav" "$TMP/break-bass.wav" "$SOUNDS_DIR/break-start.wav" \
    pad 0 1.5 reverb 60 70 95 norm -6

# ---- ALL DONE ----
# 4-bar chord progression in C major: I - IV - V - I  (C - F - G - C).
# Triangle melody bars 1-3 (Idea 2 motif). Bar 4 = C-major triad (C-E-G) played
# staggered (80ms offsets) with bell-like partials on each note.
sox -n -r 44100 -c 2 "$TMP/all-mel.wav" \
    synth 0.33 triangle 784 fade 0.02 0.33 0.25 \
    : synth 0.17 triangle 659 fade 0.02 0.17 0.12 \
    : synth 0.33 triangle 523 fade 0.02 0.33 0.25 \
    : synth 0.17 triangle 659 fade 0.02 0.17 0.12 \
    : synth 0.33 triangle 880 fade 0.02 0.33 0.25 \
    : synth 0.17 triangle 698 fade 0.02 0.17 0.12 \
    : synth 0.33 triangle 523 fade 0.02 0.33 0.25 \
    : synth 0.17 triangle 698 fade 0.02 0.17 0.12 \
    : synth 0.33 triangle 988 fade 0.02 0.33 0.25 \
    : synth 0.17 triangle 784 fade 0.02 0.17 0.12 \
    : synth 0.33 triangle 1175 fade 0.02 0.33 0.25 \
    : synth 0.17 triangle 784 fade 0.02 0.17 0.12
# Staggered C-major triad: C5 at 0ms, E5 at 80ms, G5 at 160ms. Sine bell tones with
# inharmonic partials. 4.0s each with logarithmic fade = physically accurate
# bell decay (even drop in dB over time, mimicking real resonant decay).
sox -n -r 44100 -c 2 "$TMP/all-c.wav" \
    synth 4.0 sine 523 sine 1569 sine 2615 fade l 0.02 4.0 3.9
sox -n -r 44100 -c 2 "$TMP/all-e.wav" \
    synth 4.0 sine 659 sine 1977 sine 3295 fade l 0.02 4.0 3.9 pad 0.08 0
sox -n -r 44100 -c 2 "$TMP/all-g.wav" \
    synth 4.0 sine 784 sine 2352 sine 3920 fade l 0.02 4.0 3.9 pad 0.16 0
sox -m "$TMP/all-c.wav" "$TMP/all-e.wav" "$TMP/all-g.wav" "$TMP/all-chord.wav" norm -1
# Concatenate melody + staggered chord
sox "$TMP/all-mel.wav" "$TMP/all-chord.wav" "$TMP/all-top.wav"
# Bass: chord root per bar. Bar 4 extended to 4.5s with log fade to ring out
# naturally under the bell chord.
sox -n -r 44100 -c 2 "$TMP/all-bass.wav" \
    synth 1.0 sine 262 fade 0.05 1.0 0.1 \
    : synth 1.0 sine 349 fade 0.02 1.0 0.1 \
    : synth 1.0 sine 392 fade 0.02 1.0 0.1 \
    : synth 4.5 sine 262 fade l 0.02 4.5 4.3 vol 0.55
sox -m "$TMP/all-top.wav" "$TMP/all-bass.wav" "$SOUNDS_DIR/all-done.wav" \
    pad 0 1.5 reverb 60 70 95 norm -6

# ---- MILESTONE ----
# 1.5-bar ticking swung motif — 6 sharp triangle ticks alternating pitches
# (1800Hz long, 1500Hz short) with swing timing, like a clock pendulum.
sox -n -r 44100 -c 2 "$TMP/mile-t1.wav" \
    synth 0.04 triangle 1800 fade 0 0.04 0.035 lowpass 3500 pad 0 0.29
sox -n -r 44100 -c 2 "$TMP/mile-t2.wav" \
    synth 0.04 triangle 1500 fade 0 0.04 0.035 lowpass 3500 pad 0 0.13
sox -n -r 44100 -c 2 "$TMP/mile-t3.wav" \
    synth 0.04 triangle 1800 fade 0 0.04 0.035 lowpass 3500 pad 0 0.29
sox -n -r 44100 -c 2 "$TMP/mile-t4.wav" \
    synth 0.04 triangle 1500 fade 0 0.04 0.035 lowpass 3500 pad 0 0.13
sox -n -r 44100 -c 2 "$TMP/mile-t5.wav" \
    synth 0.04 triangle 1800 fade 0 0.04 0.035 lowpass 3500 pad 0 0.29
sox -n -r 44100 -c 2 "$TMP/mile-t6.wav" \
    synth 0.04 triangle 1500 fade 0 0.04 0.035 lowpass 3500 pad 0 0.13
sox "$TMP/mile-t1.wav" "$TMP/mile-t2.wav" "$TMP/mile-t3.wav" \
    "$TMP/mile-t4.wav" "$TMP/mile-t5.wav" "$TMP/mile-t6.wav" "$TMP/mile-top.wav"
# Subtle bass thump accent on each long-position tick (3 beats)
sox -n -r 44100 -c 2 "$TMP/mile-b1.wav" \
    synth 0.08 sine 220 fade 0 0.08 0.07 vol 0.4 pad 0 0.42
sox -n -r 44100 -c 2 "$TMP/mile-b2.wav" \
    synth 0.08 sine 220 fade 0 0.08 0.07 vol 0.4 pad 0 0.42
sox -n -r 44100 -c 2 "$TMP/mile-b3.wav" \
    synth 0.08 sine 220 fade 0 0.08 0.07 vol 0.4 pad 0 0.42
sox "$TMP/mile-b1.wav" "$TMP/mile-b2.wav" "$TMP/mile-b3.wav" "$TMP/mile-bass.wav"
sox -m "$TMP/mile-top.wav" "$TMP/mile-bass.wav" "$SOUNDS_DIR/milestone.wav" \
    pad 0 1.5 reverb 30 50 60 norm -8

echo "Generated 4 stings in $SOUNDS_DIR"
