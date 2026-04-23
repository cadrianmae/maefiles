#!/bin/bash
# Minimal trace wrapper — always logs to /tmp/piper-trace.log
LOG=/tmp/piper-trace.log
{
  echo "===== INVOKED $(date) ====="
  echo "PID=$$ PPID=$PPID"
  echo "VOICE=$VOICE"
  echo "DATA=$DATA"
  echo "RATE=$RATE PITCH=$PITCH VOLUME=$VOLUME"
  echo "PLAY_COMMAND=$PLAY_COMMAND"
  env | grep -iE "^(XDG|PULSE|WAYLAND|DISPLAY|DBUS|PATH)=" | head
} >> "$LOG" 2>&1

# If DATA is empty, read it from stdin (SD may pipe text in)
if [ -z "$DATA" ]; then
    DATA=$(cat)
    echo "STDIN_DATA=$DATA" >> "$LOG"
    export DATA
fi

/home/cadrianmae/.config/speech-dispatcher/piper-wrapper.sh 2>>"$LOG"
EXIT=$?
echo "EXIT=$EXIT" >> "$LOG"
exit $EXIT
