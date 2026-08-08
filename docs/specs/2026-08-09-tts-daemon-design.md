# Pluggable TTS daemon for speech-dispatcher

Date: 2026-08-09
Status: design approved, not yet implemented
Supersedes: the ad-hoc `~/.config/speech-dispatcher/piper/` scripts

## Context

Local TTS runs through speech-dispatcher with a `sd_generic` module
(`piper-generic`) that shells out to `piper/run.sh`, which talks to a persistent
`piper/daemon.py` over a Unix socket, falling back to the `piper` CLI when the
socket is absent.

It works, but its behaviour is unpredictable in practice: sometimes fast,
sometimes slow, and when it breaks it breaks silently. This design fixes the
predictability, and factors the code so a second engine (espeak-ng today,
kokoro later) can be plugged in without touching the rest.

This is project A of two. Project B, notification TTS, is a separate spec built
on top of this one.

## Measured behaviour (2026-08-09)

Diagnostics run against the live system, not assumptions:

| Observation | Measurement |
| --- | --- |
| Cold start (daemon exited, model reload) | 5.34 s |
| Warm start (model cached) | 0.69 s |
| Daemon idle timeout | 300 s, so sporadic use is nearly always cold |
| Long paragraph (392 chars) | spoken in full, 18.66 s, no truncation |
| Cancel (`spd-say -C`) mid-speech | clean; no orphaned `paplay` or piper processes |
| Concurrency | speech-dispatcher serialises; the daemon never sees parallel requests |

SSIP priority semantics, measured with a burst of three messages:

| Priority | Behaviour | Effect |
| --- | --- | --- |
| `text` | first two cancelled at 0.18 s | latest wins |
| `message` | queued: 0.98 / 1.73 / 2.70 s | all spoken, in order |
| `important` | queued, same as `message` | all spoken, never discarded |
| `notification` | first two dropped | latest wins, no backlog |

Two conclusions worth recording, because they contradict the first-pass audit:

- The daemon's serial accept loop is **not** a real defect. speech-dispatcher
  serialises upstream, so concurrent requests do not arise.
- Cancellation is **not** a real defect. It already cleans up correctly.

The genuine defects are below.

## Problems being solved

1. **Cold-start latency dominates.** A 300 s idle timeout against sporadic use
   means most utterances pay 5.3 s instead of 0.7 s. This is the main source of
   the "sometimes it works, sometimes it doesn't" feeling.
2. **Update fragility.** `piper-daemon.service` hardcodes `python3.14` in
   `LD_LIBRARY_PATH`, and `~/.cache/piper-ld-path` caches the same paths. A
   Fedora python bump silently removes the CUDA libs from the search path.
3. **No CPU fallback.** `run.sh` passes `--cuda` on the fallback path too, so a
   CUDA failure takes out both the daemon and its fallback.
4. **Failures are silent.** Logs go to `/tmp/piper-daemon.log` (unbounded, lost
   on reboot) rather than the journal, and `run.sh` exits 0 in the noblock path
   regardless of outcome, hiding failures from speech-dispatcher.
5. **Duplicated pipeline.** `run.sh` reimplements roughly 100 lines of the
   synthesis/playback pipeline that `client.py` already implements. Two copies
   that drift.
6. **No plug point.** The engine is piper, hardcoded. espeak-ng and kokoro
   cannot be selected.
7. **Hardcoded constants.** `0.6` length scale, `40000` volume, and absolute
   `/home/cadrianmae/...` paths are embedded in code.
8. **No tests.**

## Approach

Three options were considered:

1. Patch the existing scripts in place. Smallest diff, but leaves the duplicated
   bash pipeline to drift.
2. **Collapse into a single Python component set with an engine interface.**
   Chosen.
3. Write a native speech-dispatcher output module speaking the module protocol
   instead of using `sd_generic`.

Option 3 is architecturally cleaner than it first appears: the module process
would hold the model and play audio itself, removing the socket, the client, the
daemon and both systemd units, and gaining PAUSE/RESUME and index marks that
`sd_generic` cannot support. It was rejected for now because its failure mode
works against the goal: a misbehaving module is killed by speechd, producing
silence with no error, which is exactly the symptom being eliminated. It also
loses the ability to call the daemon directly from non-speechd clients.

Option 2 is therefore built with the front-end held strictly separate from the
engine layer, so that adopting option 3 later is a front-end swap that reuses
every engine unchanged.

## Architecture

```
speech-dispatcher            queueing, priority, cancel (upstream, works)
        |  sd_generic: env VOICE / DATA / RATE / PITCH / VOLUME
        v
  [ front-end ]  run         parse env, map params; exit code means "done"
        |
        v
  [ core ]       daemon      model cache, idle lifetime, socket
        |
        v
  [ engine ]     Engine      piper | espeak | (kokoro later)
        |
        v
  [ sink ]       sink        playback, volume, pitch
```

Four boundaries, each independently testable:

- **front-end** owns only speechd's env-var contract and parameter mapping. It
  knows nothing about ONNX and is swappable for a native module later.
- **core** owns model caching, the socket and idle lifetime. It knows nothing
  about which engine is in use.
- **engine** exposes `synthesize()` returning a sample rate and an iterator of
  s16le PCM chunks. One class per backend.
- **sink** owns playback and the volume/pitch mapping, shared by all engines, so
  espeak inherits the existing volume mapping unchanged.

`run.sh`'s duplicated CLI pipeline is deleted. The fallback becomes engine
selection rather than a second copy of the pipeline.

## Layout

```
~/.local/libexec/tts/
    run              front-end, sd_generic entry point (replaces run.sh)
    daemon.py        core: socket, model cache, idle lifetime
    client.py        core: socket client (kept, trimmed)
    sink.py          playback, volume, pitch
    engines/
        base.py      Engine protocol
        piper.py     ONNX, CUDA -> CPU fallback
        espeak.py    subprocess
~/.config/tts/config.toml
~/.config/systemd/user/tts-daemon.{service,socket}
~/bin/tts            CLI: warm | status | say | test | engines
~/scripts/tts/       pytest suite
```

Layout follows existing conventions: `~/.local/libexec/` for internal service
helpers, `~/bin/` for user-facing scripts, and tests under `~/scripts/<topic>/`
as `memory-notify` does.

Every component is python, including `run` and the `tts` CLI. The current split
between bash (`run.sh`) and python (`client.py`, `daemon.py`) is what allowed
the pipeline to be implemented twice; a single language removes that, and lets
one pytest suite cover the whole stack. No name conflicts exist for `tts` or
`~/.config/tts/`.

## Engine interface

```python
class Engine(Protocol):
    name: str
    def available(self) -> bool: ...              # deps present, model dir exists
    def resolve(self, voice: str) -> Voice: ...   # "x.onnx:2" -> model + speaker
    def synthesize(self, text: str, voice: Voice, p: Params) -> Synthesis: ...
    # Synthesis = (sample_rate: int, chunks: Iterator[bytes])   # s16le mono
```

Everything downstream consumes `Synthesis`, keeping `sink.py` engine-agnostic.
Adding kokoro later means one new file implementing four methods.

## Configuration

`tomllib` is used, which is stdlib on python 3.14, so no new dependency.

```toml
[core]
idle_timeout  = 600        # 10 minutes
model_evict   = 900

[engine]
default  = "piper"
fallback = ["espeak"]      # tried in order when the default fails

[piper]
voice_dir     = "~/.local/share/piper-voices"
default_voice = "en_GB-cori-high.onnx"
length_scale  = 0.6
device        = "auto"     # auto | cuda | cpu

[sink]
base_volume = 40000
```

`AddVoice` lines stay in the speech-dispatcher module config. That is speechd's
own voice registry and is not duplicated here.

The module is renamed `piper-generic` -> `mae-tts`, since it is no longer
piper-specific. Only `speechd.conf` names the module; nvim and other callers use
the default module, so this is a one-line change.

## Failure handling

The governing principle: **never fail silently, always degrade to some speech.**

1. **Re-exec instead of a version pin.** The hardcoded `python3.14`
   `Environment=` lines are removed from the unit and `~/.cache/piper-ld-path`
   is deleted, since a stale cache is itself a failure mode. The daemon derives
   the nvidia lib paths at startup by globbing `site-packages/nvidia/*/lib`, and
   if they are absent from its own environment it `execve`s itself once with a
   corrected environment. This survives any python version bump.
2. **Device fallback.** `device = "auto"` tries CUDA and falls back to
   `CPUExecutionProvider` on session-creation failure, logging a warning and
   remembering the choice for the session.
3. **Engine fallback chain.** When the default engine fails, the engines in
   `engine.fallback` are tried in order.
4. **Degradation is announced once per session.** Falling back to CPU or to
   espeak fires a desktop notification, e.g. "TTS degraded: piper -> espeak
   (model load failed)". This is the direct fix for not knowing when the system
   has broken.
5. **`tts status` and `tts test`.** `status` reports engine, device, cached
   models, daemon uptime and last error. `test` runs every engine against every
   device and prints an OK/FAIL table.
6. **Journal logging.** stderr to `journalctl --user -u tts-daemon`, replacing
   `/tmp/piper-daemon.log` and `/tmp/piper-debug.log`.
7. **Fail loud.** The front-end exits non-zero when nothing was spoken.
8. **Synth watchdog.** If no PCM arrives within a timeout, the attempt is
   aborted and the fallback chain continues, converting a hang into a fallback.

This makes espeak-ng load-bearing, so its own health matters; `tts test` covers
it.

## Testing

Real TTS needs a GPU, a model and speakers, so those are isolated behind two
seams: a `FakeEngine` (no model, no GPU) and a file-writing sink (no audio
device). Everything above the engine boundary is then ordinary fast unit
testing.

| Layer | Test | Hardware |
| --- | --- | --- |
| param mapping | table-driven, including clamping at +/-1.0 | no |
| voice parsing | `"...onnx:2"` -> model + speaker, and the no-speaker case | no |
| config | defaults, `~` expansion, missing file, malformed TOML | no |
| CUDA path derivation | fake `site-packages/nvidia/*/lib` tree in `tmp_path`; asserts a python bump still resolves | no |
| engine fallback | `FakeEngine(fails=True)` falls through; degradation notification fires exactly once | no |
| daemon socket | `FakeEngine` emitting known PCM; asserts header magic, sample rate, byte-exact payload | no |
| sink | file sink; asserts bytes, and that sox is only invoked above the pitch threshold | no |
| engine contract suite | shared parametrised suite every engine must pass | espeak no, piper `@pytest.mark.gpu` |
| end-to-end | `tts test`, real audio, run by hand | yes |

The contract suite is the payoff of the plug design: a future kokoro engine is
proven by running the existing suite against it, with no new test code.

Regression tests for the defects found on 2026-08-09:

- the front-end exits non-zero when nothing was spoken
- stale or missing CUDA paths produce CPU fallback, not silence
- the daemon idle timeout is read from config, not a literal

Deliberately not covered: speech-dispatcher's own queueing and priority
behaviour. That is upstream's, and the measurements above confirm it works.

## Migration and rollback

The new stack is installed alongside the old one rather than replacing it in
place, so the cutover is a single config line and the rollback is the same line
reversed.

1. Build `~/.local/libexec/tts/` and `~/.config/tts/config.toml` while
   `piper-generic` remains the default module. Nothing changes for daily use.
2. Add the `mae-tts` module config and its systemd units. Verify with
   `spd-say -o mae-tts` and `tts test` while `piper-generic` still works.
3. Cut over by pointing `DefaultModule` in `speechd.conf` at `mae-tts`.
4. Soak. Rollback at any point is reverting `DefaultModule` to `piper-generic`,
   which is left untouched throughout.
5. Only after the soak: remove `~/.config/speech-dispatcher/piper/`, the
   `piper-daemon` units, the `piper-generic` module config, and the stale
   `~/.cache/piper-ld-path` and `~/.cache/piper-sr-*` caches.

The old `piper-daemon.socket` and the new `tts-daemon.socket` use different
socket paths, so both can be installed at once without conflict.

## Out of scope

- Notification TTS. Separate spec (project B), built on this.
- A kokoro engine. The interface admits one; it is not implemented here. Kokoro
  currently exists only inside the speaches container in `open-notebook-stack`.
- A native speech-dispatcher output module (option 3), deferred as above.
