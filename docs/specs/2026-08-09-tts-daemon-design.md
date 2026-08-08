# speechd-tts: a pluggable local TTS backend for speech-dispatcher

Date: 2026-08-09
Status: design approved, not yet implemented

## Context

speech-dispatcher can drive an arbitrary synthesiser through its `sd_generic`
module, but doing so well is awkward. A naive `sd_generic` wrapper spawns the
synthesiser once per utterance, which for a neural TTS model means reloading
several hundred megabytes of ONNX weights every time somebody speaks a sentence.

The usual workaround is a persistent daemon holding the model in memory, with
the `sd_generic` command acting as a thin client. That workaround is what this
project generalises: a resident daemon, a pluggable engine layer so the
synthesiser can be swapped (piper, espeak-ng, others), and predictable failure
behaviour so a broken backend degrades audibly rather than going silent.

This is project A of two. Project B, notification TTS, is a separate spec built
on top of this one.

## Prior art being replaced

The design starts from a working but ad-hoc implementation: an `sd_generic`
module invoking a bash runner, which talks to a persistent piper daemon over a
Unix socket and falls back to the piper CLI when the socket is absent. It works,
but its behaviour is unpredictable in practice: sometimes fast, sometimes slow,
and when it breaks it breaks silently.

## Measured behaviour (2026-08-09)

Diagnostics run against the live implementation, not assumptions:

| Observation | Measurement |
| --- | --- |
| Cold start (daemon exited, model reload) | 5.34 s |
| Warm start (model cached) | 0.69 s |
| Daemon idle timeout | 300 s, so sporadic use is nearly always cold |
| Long paragraph (392 chars) | spoken in full, 18.66 s, no truncation |
| Cancel (`spd-say -C`) mid-speech | clean; no orphaned `paplay` or synth processes |
| Concurrency | speech-dispatcher serialises; the daemon never sees parallel requests |

SSIP priority semantics, measured with a burst of three messages:

| Priority | Behaviour | Effect |
| --- | --- | --- |
| `text` | first two cancelled at 0.18 s | latest wins |
| `message` | queued: 0.98 / 1.73 / 2.70 s | all spoken, in order |
| `important` | queued, same as `message` | all spoken, never discarded |
| `notification` | first two dropped | latest wins, no backlog |

Two conclusions worth recording, because they contradict the first-pass audit:

- A serial accept loop in the daemon is **not** a real defect. speech-dispatcher
  serialises upstream, so concurrent requests do not arise.
- Cancellation is **not** a real defect. It already cleans up correctly.

The genuine defects are below.

## Problems being solved

1. **Cold-start latency dominates.** A 300 s idle timeout against sporadic use
   means most utterances pay 5.3 s instead of 0.7 s. This is the main source of
   the "sometimes it works, sometimes it doesn't" feeling.
2. **Update fragility.** The systemd unit hardcodes a python minor version in
   `LD_LIBRARY_PATH` to reach the CUDA libraries shipped in the `nvidia` wheels,
   and a cache file records the same paths. A distribution python bump silently
   removes the CUDA libraries from the search path.
3. **No CPU fallback.** The CLI fallback path also requests CUDA, so a CUDA
   failure takes out both the daemon and its fallback.
4. **Failures are silent.** Logs go to a file under `/tmp` (unbounded, lost on
   reboot) rather than the journal, and the runner exits 0 on its detached path
   regardless of outcome, hiding failures from speech-dispatcher.
5. **Duplicated pipeline.** The bash runner reimplements roughly 100 lines of
   the synthesis and playback pipeline that the socket client already
   implements. Two copies that drift.
6. **No plug point.** The engine is hardcoded. Other synthesisers cannot be
   selected.
7. **Hardcoded constants.** Length scale, playback volume and absolute
   `$HOME`-prefixed paths are embedded in code.
8. **No tests.**

## Approach

Three options were considered:

1. Patch the existing scripts in place. Smallest diff, but leaves the duplicated
   bash pipeline to drift.
2. **Collapse into a single python component set with an engine interface.**
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
  [ engine ]     Engine      piper | espeak | others
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
  every engine inherits the same volume behaviour.

The duplicated CLI pipeline is deleted. The fallback becomes engine selection
rather than a second copy of the pipeline.

## Layout

Installed layout, XDG-conformant:

```
$HOME/.local/libexec/speechd-tts/
    run              front-end, sd_generic entry point
    daemon.py        core: socket, model cache, idle lifetime
    client.py        core: socket client
    sink.py          playback, volume, pitch
    engines/
        base.py      Engine protocol
        piper.py     ONNX, CUDA -> CPU fallback
        espeak.py    subprocess
$HOME/.config/speechd-tts/config.toml
$HOME/.config/systemd/user/speechd-tts.{service,socket}
$HOME/.local/bin/speechd-tts     CLI: warm | status | say | test | engines
```

`$HOME/.local/libexec/` holds the internal service helpers, which are not
intended to be invoked directly; only the CLI goes on `PATH`.

Every component is python, including `run` and the CLI. The prior bash/python
split is what allowed the pipeline to be implemented twice; a single language
removes that, and lets one pytest suite cover the whole stack.

## Engine interface

```python
class Engine(Protocol):
    name: str
    def available(self) -> bool: ...              # deps present, model dir exists
    def resolve(self, voice: str) -> Voice: ...   # "x.onnx:2" -> model + speaker
    def synthesize(self, text: str, voice: Voice, p: Params) -> Synthesis: ...
    # Synthesis = (sample_rate: int, chunks: Iterator[bytes])   # s16le mono
```

Everything downstream consumes `Synthesis`, keeping the sink engine-agnostic.
Adding an engine means one new file implementing four methods.

## Configuration

`tomllib` is used, which is stdlib from python 3.11, so no new dependency.

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

The speech-dispatcher module is named `speechd-tts`.

## Failure handling

The governing principle: **never fail silently, always degrade to some speech.**

1. **Re-exec instead of a version pin.** No python version is hardcoded and no
   path cache is kept, since a stale cache is itself a failure mode. The daemon
   derives the nvidia library paths at startup by globbing
   `site-packages/nvidia/*/lib`, and if they are absent from its own environment
   it `execve`s itself once with a corrected environment. This survives any
   python version bump.
2. **Device fallback.** `device = "auto"` tries CUDA and falls back to
   `CPUExecutionProvider` on session-creation failure, logging a warning and
   remembering the choice for the session.
3. **Engine fallback chain.** When the default engine fails, the engines in
   `engine.fallback` are tried in order.
4. **Degradation is announced once per session.** Falling back to CPU or to
   another engine fires a desktop notification, e.g. "TTS degraded: piper ->
   espeak (model load failed)". This is the direct fix for not knowing when the
   system has broken.
5. **`status` and `test` subcommands.** `status` reports engine, device, cached
   models, daemon uptime and last error. `test` runs every engine against every
   device and prints an OK/FAIL table.
6. **Journal logging.** stderr to `journalctl --user -u speechd-tts`, replacing
   the `/tmp` log files.
7. **Fail loud.** The front-end exits non-zero when nothing was spoken.
8. **Synth watchdog.** If no PCM arrives within a timeout, the attempt is
   aborted and the fallback chain continues, converting a hang into a fallback.

This makes the fallback engine load-bearing, so its own health matters; `test`
covers it.

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
| end-to-end | `test` subcommand, real audio, run by hand | yes |

The contract suite is the payoff of the plug design: a future engine is proven
by running the existing suite against it, with no new test code.

Regression tests for the defects measured on 2026-08-09:

- the front-end exits non-zero when nothing was spoken
- stale or missing CUDA paths produce CPU fallback, not silence
- the daemon idle timeout is read from config, not a literal

Deliberately not covered: speech-dispatcher's own queueing and priority
behaviour. That is upstream's, and the measurements above confirm it works.

## Distribution

The project is intended for release, so the source lives in a git repository and
the layout above is an *install target*, not the working tree. Installation
symlinks or copies into the XDG paths and installs the speech-dispatcher module
config; uninstallation reverses it. Nothing is written outside `$HOME`.

Consequences for the design: no absolute paths to a particular user's home may
appear in code or config defaults, the config file must be optional with working
defaults, and the systemd units must be templated at install time rather than
shipped with paths baked in.

## Migration and rollback

For an existing ad-hoc setup, the new stack installs alongside the old one
rather than replacing it in place, so the cutover is a single config line and
the rollback is the same line reversed.

1. Install `speechd-tts` while the existing module remains the default. Nothing
   changes for daily use.
2. Add the `speechd-tts` module config and its systemd units. Verify with
   `spd-say -o speechd-tts` and the `test` subcommand while the old module still
   works.
3. Cut over by pointing `DefaultModule` in `speechd.conf` at `speechd-tts`.
4. Soak. Rollback at any point is reverting `DefaultModule`, which is left
   untouched throughout.
5. Only after the soak: remove the old scripts, units, module config and cache
   files.

The old and new sockets use different paths, so both can be installed at once
without conflict.

## Out of scope

- Notification TTS. Separate spec (project B), built on this.
- Engines beyond piper and espeak-ng. The interface admits them; none are
  implemented here.
- A native speech-dispatcher output module (option 3), deferred as above.
