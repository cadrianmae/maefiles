#!/usr/bin/env python3
"""Client for piper-daemon.

Default (blocking): connect, synth, play, exit when paplay finishes. This is
required for sd_generic to queue messages correctly — runner exit signals
"message done" to speech-dispatcher.

PIPER_NOBLOCK=1: fork-and-detach. Parent exits 0 immediately on connect; child
handles synthesis + playback in background. Use only for fire-and-forget cases
where queue ordering does not matter.
"""

import json
import os
import socket
import struct
import subprocess
import sys

NOBLOCK = os.environ.get("PIPER_NOBLOCK") == "1"

# Params exported by run.sh after mapping speechd RATE/PITCH/VOLUME.
# Defaults mirror run.sh when env is unset (e.g. spd-say one-shots).
LENGTH_SCALE = os.environ.get("LENGTH_SCALE", "0.6")
PAPLAY_VOLUME = os.environ.get("PAPLAY_VOLUME", "40000")
try:
    PITCH_CENTS = int(os.environ.get("PITCH_CENTS", "0"))
except ValueError:
    PITCH_CENTS = 0

sock_path = sys.argv[1]
text = sys.argv[2]
model = sys.argv[3]
spk_json = sys.argv[4] if len(sys.argv) > 4 else ""

req = ('{"text":' + json.dumps(text)
       + ',"model":' + json.dumps(model)
       + ',"length_scale":' + LENGTH_SCALE
       + spk_json + '}\n')

# Connect in parent — fast fail if daemon is unavailable.
sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.settimeout(2)
try:
    sock.connect(sock_path)
except OSError:
    sys.exit(1)

if NOBLOCK:
    # Fork — parent exits 0 immediately, child handles playback detached.
    pid = os.fork()
    if pid > 0:
        sock.close()
        sys.exit(0)
    os.setsid()

sock.settimeout(None)

try:
    sock.sendall(req.encode())

    hdr = b""
    while len(hdr) < 8:
        chunk = sock.recv(8 - len(hdr))
        if not chunk:
            sys.exit(1)
        hdr += chunk

    sr = struct.unpack("<I", hdr[4:8])[0]

    paplay_cmd = ["paplay", "--raw", "--format=s16le", f"--rate={sr}",
                  "--channels=1", f"--volume={PAPLAY_VOLUME}"]

    # Pipeline: socket → [sox pitch] → paplay. sox is only inserted when
    # |PITCH_CENTS| >= 10, to avoid the subprocess spawn for near-zero shifts.
    sox_proc = None
    if abs(PITCH_CENTS) >= 10:
        sox_cmd = [
            "sox",
            "-t", "raw", "-r", str(sr), "-e", "signed", "-b", "16", "-c", "1", "-",
            "-t", "raw", "-r", str(sr), "-e", "signed", "-b", "16", "-c", "1", "-",
            "pitch", str(PITCH_CENTS),
        ]
        sox_proc = subprocess.Popen(sox_cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE)
        assert sox_proc.stdout is not None
        paplay_proc = subprocess.Popen(paplay_cmd, stdin=sox_proc.stdout)
        sox_proc.stdout.close()  # allow sox to receive SIGPIPE if paplay dies
        sink = sox_proc
    else:
        paplay_proc = subprocess.Popen(paplay_cmd, stdin=subprocess.PIPE)
        sink = paplay_proc

    assert sink.stdin is not None
    while True:
        data = sock.recv(65536)
        if not data:
            break
        sink.stdin.write(data)
    sink.stdin.close()
    if sox_proc is not None:
        sox_proc.wait()
    paplay_proc.wait()
finally:
    sock.close()
