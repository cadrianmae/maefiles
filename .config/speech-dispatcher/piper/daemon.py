#!/usr/bin/env python3
"""Persistent Piper TTS daemon -- loads ONNX model once, serves via Unix socket.

Protocol:
  Client sends: JSON line {"text": "...", "model": "X.onnx", "speaker_id": N, "length_scale": 0.6}
  Server sends: 8-byte header (b"PIPR" + uint32 sample_rate LE) then raw s16le PCM until close.
"""

import json
import logging
import os
import select
import socket
import struct
import time
from pathlib import Path

from piper.config import SynthesisConfig
from piper.voice import PiperVoice

VOICE_DIR = Path.home() / ".local/share/piper-voices"
IDLE_TIMEOUT = 300       # 5 minutes idle -> exit (systemd restarts on next connection)
MODEL_EVICT_SECS = 600   # evict models unused for 10 minutes
HEADER_MAGIC = b"PIPR"
LOG_PATH = "/tmp/piper-daemon.log"

logging.basicConfig(
    filename=LOG_PATH, level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
)
log = logging.getLogger("piper-daemon")

_models: dict[str, PiperVoice] = {}
_model_last_used: dict[str, float] = {}


def get_voice(model_name: str) -> PiperVoice:
    now = time.monotonic()
    if model_name not in _models:
        model_path = VOICE_DIR / model_name
        log.info("Loading model: %s (use_cuda=True)", model_path)
        t0 = time.monotonic()
        _models[model_name] = PiperVoice.load(str(model_path), use_cuda=True)
        log.info("Model loaded in %.2fs: %s", time.monotonic() - t0, model_name)
    _model_last_used[model_name] = now
    return _models[model_name]


def evict_stale_models():
    now = time.monotonic()
    stale = [k for k, t in _model_last_used.items() if now - t > MODEL_EVICT_SECS]
    for k in stale:
        log.info("Evicting stale model: %s", k)
        del _models[k]
        del _model_last_used[k]


def handle_client(client: socket.socket):
    try:
        data = b""
        while b"\n" not in data:
            chunk = client.recv(4096)
            if not chunk:
                break
            data += chunk

        if not data.strip():
            return

        req = json.loads(data.strip())
        text = req["text"]
        model_name = req["model"]
        speaker_id = req.get("speaker_id")
        length_scale = req.get("length_scale", 1.0)

        log.info("Synth: model=%s speaker=%s len=%d", model_name, speaker_id, len(text))

        voice = get_voice(model_name)
        config = SynthesisConfig(speaker_id=speaker_id, length_scale=length_scale)

        sr = voice.config.sample_rate
        client.sendall(HEADER_MAGIC + struct.pack("<I", sr))

        for audio_chunk in voice.synthesize(text, config):
            client.sendall(audio_chunk.audio_int16_bytes)

    except Exception:
        log.exception("Error handling client")
    finally:
        client.close()


def get_server_socket() -> socket.socket:
    """Prefer systemd socket activation, fall back to creating our own."""
    try:
        from systemd.daemon import listen_fds
        fds = listen_fds()
        if fds:
            log.info("Using systemd socket activation (fd=%d)", fds[0])
            sock = socket.fromfd(fds[0], socket.AF_UNIX, socket.SOCK_STREAM)
            sock.setblocking(False)
            return sock
    except ImportError:
        pass

    sock_path = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}") + "/piper-daemon.sock"
    log.info("Creating socket at %s", sock_path)
    try:
        os.unlink(sock_path)
    except FileNotFoundError:
        pass
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.setblocking(False)
    sock.bind(sock_path)
    sock.listen(4)
    return sock


def setup_cuda_ld_path():
    ld_cache = Path.home() / ".cache/piper-ld-path"
    if ld_cache.exists():
        extra = ld_cache.read_text().strip()
        current = os.environ.get("LD_LIBRARY_PATH", "")
        os.environ["LD_LIBRARY_PATH"] = f"{extra}:{current}" if current else extra
        log.info("LD_LIBRARY_PATH loaded from cache")


def main():
    setup_cuda_ld_path()
    log.info("Piper daemon starting (pid=%d, idle_timeout=%ds)", os.getpid(), IDLE_TIMEOUT)
    server = get_server_socket()

    try:
        while True:
            readable, _, _ = select.select([server], [], [], IDLE_TIMEOUT)
            if not readable:
                log.info("Idle timeout (%ds), exiting", IDLE_TIMEOUT)
                break
            client, _ = server.accept()
            client.setblocking(True)
            handle_client(client)
            evict_stale_models()
    except KeyboardInterrupt:
        log.info("Interrupted, exiting")
    finally:
        server.close()
        log.info("Daemon stopped")


if __name__ == "__main__":
    main()
