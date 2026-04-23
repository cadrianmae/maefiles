#!/bin/bash
# Wrapper script for Piper TTS with Speech Dispatcher parameter conversion

# Convert Speech Dispatcher RATE (-100 to 100) to Piper length_scale (0.1 to 1.0)
# Rate -100 = slowest (1.0), Rate 0 = normal (0.55), Rate 100 = fastest (0.1)
PIPER_SPEED=$(awk "BEGIN {print 0.55 - ($RATE * 0.0045)}")

# Clamp to valid range
if (( $(awk "BEGIN {print ($PIPER_SPEED < 0.1)}") )); then
    PIPER_SPEED=0.1
fi
if (( $(awk "BEGIN {print ($PIPER_SPEED > 1.0)}") )); then
    PIPER_SPEED=1.0
fi

# Run Piper with calculated speed, then process with sox for pitch and volume
printf %s "$DATA" | \
    /home/cadrianmae/.local/bin/piper \
        --model /home/cadrianmae/.local/share/piper-voices/$VOICE \
        --length_scale $PIPER_SPEED \
        --output-raw \
        -f - | \
    sox -v $VOLUME -r 22050 -c 1 -b 16 -e signed-integer -t raw - -t wav - \
        pitch $PITCH norm 2>/dev/null | \
    mpv --no-terminal --keep-open=no - 2>/dev/null
