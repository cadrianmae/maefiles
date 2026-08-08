# speechd-neural Implementation Plan (stage 1)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A resident speech-dispatcher backend that speaks through neural TTS engines reliably, degrading audibly instead of going silent.

**Architecture:** Four layers with hard boundaries: a `sd_generic` front-end that owns only speechd's env-var contract, a socket daemon that owns lifetime and caching, an `Engine` protocol with piper and espeak-ng implementations, and a sink that owns playback. Synthesis happens daemon-side; playback happens client-side, so the client blocking until audio finishes is what tells speech-dispatcher the message is done.

**Tech Stack:** python 3.11+ (stdlib `tomllib`), pytest, piper-tts + onnxruntime, espeak-ng, speech-dispatcher `sd_generic`, systemd socket activation, `paplay`, optional `sox`.

**Design doc:** `~/docs/specs/2026-08-09-speechd-neural-design.md` (moved into the repo in Task 1).

## Global Constraints

- Python 3.11 or later. `tomllib` is stdlib from 3.11; no TOML dependency may be added.
- **No python version may be hardcoded anywhere** — not in code, not in config, not in systemd units. This is defect 2 from the spec and the single most important constraint.
- **No absolute path to a particular user's home** in code or config defaults. Use `Path.home()`, `$HOME`, or XDG lookups.
- The config file is optional. Every setting has a working default.
- systemd units are templated at install time, never shipped with paths baked in.
- Nothing is written outside `$HOME`.
- Never fail silently. Every failure path either degrades to another engine/device or exits non-zero.
- Logs go to stderr for the journal. No log files under `/tmp`.
- Prose in British English. No emoji or non-keyboard characters in code, comments, or docs — use `[OK]`, `[WARN]`, `[ERROR]` tags.
- Repo: `~/git/github.com/cadrianmae/speechd-neural`. Package: `src/speechd_neural/`.

## Deviations from the spec (deliberate, flagged)

1. **Tests live in the repo** (`tests/`), not `~/scripts/<topic>/`. The spec was written before the repo decision.
2. **Model cache lives in the engine, lifetime policy lives in the core.** The spec says the core owns model caching. Caching a `PiperVoice` object is inherently engine-specific (espeak has nothing to cache), so the engine owns the dict and exposes `evict(older_than)`, which the daemon calls on its own schedule. The boundary the spec cares about — core knowing nothing about ONNX — is preserved.
3. **Playback is client-side, not daemon-side.** The spec diagram shows the sink below the engine. Keeping playback in the client is what makes the front-end block for exactly as long as audio plays, which is how `sd_generic` knows a message is finished.

## File Structure

```
~/git/github.com/cadrianmae/speechd-neural/
    README.md                     stub: what it is, status
    .gitignore                    python
    pyproject.toml                pytest config + package metadata only
    install.sh                    templated install into XDG paths
    docs/design.md                the spec, moved here
    conf/speechd-neural.conf      speech-dispatcher module config
    conf/speechd-neural.service   systemd unit template
    conf/speechd-neural.socket    systemd socket template
    src/speechd_neural/
        __init__.py
        config.py                 TOML load, defaults, expansion
        params.py                 voice parsing, speechd param mapping
        cuda.py                   nvidia lib discovery, re-exec
        sink.py                   playback: paplay, sox, file sink
        chain.py                  engine fallback + degradation notice
        protocol.py               wire format, shared by daemon and client
        daemon.py                 socket server, lifetime, evict policy
        client.py                 socket client, drives the sink
        run.py                    sd_generic front-end
        cli.py                    warm | status | say | test | engines
        engines/
            __init__.py
            base.py               Engine protocol, Voice, Params, EngineError
            espeak.py             subprocess engine
            piper.py              ONNX engine, CUDA -> CPU fallback
    tests/
        conftest.py               FakeEngine, fixtures
        contract.py               shared Engine contract suite
        test_config.py
        test_params.py
        test_cuda.py
        test_sink.py
        test_chain.py
        test_protocol.py
        test_daemon.py
        test_espeak.py
        test_piper.py             @pytest.mark.gpu
        test_run.py
```

---

### Task 1: Repo scaffold

**Files:**
- Create: `README.md`, `.gitignore`, `pyproject.toml`, `src/speechd_neural/__init__.py`, `src/speechd_neural/engines/__init__.py`, `tests/test_smoke.py`
- Move: `~/docs/specs/2026-08-09-speechd-neural-design.md` -> `docs/design.md`

**Interfaces:**
- Consumes: nothing.
- Produces: an importable `speechd_neural` package and a working `pytest` invocation. Every later task assumes `pytest` is run from the repo root and that `src/` is on the import path.

- [ ] **Step 1: Create the repo and directory skeleton**

```bash
mkdir -p ~/git/github.com/cadrianmae/speechd-neural
cd ~/git/github.com/cadrianmae/speechd-neural
git init
mkdir -p src/speechd_neural/engines tests docs conf
touch src/speechd_neural/__init__.py src/speechd_neural/engines/__init__.py
```

- [ ] **Step 2: Write `pyproject.toml`**

`pythonpath = ["src"]` is what makes `import speechd_neural` work in tests without an install step.

```toml
[project]
name = "speechd-neural"
version = "0.1.0"
description = "Local neural TTS engines for speech-dispatcher"
requires-python = ">=3.11"

[tool.pytest.ini_options]
pythonpath = ["src"]
testpaths = ["tests"]
markers = [
    "gpu: requires a GPU, a piper model, or an audio device",
]
```

- [ ] **Step 3: Write `.gitignore`**

```
__pycache__/
*.py[cod]
.pytest_cache/
*.egg-info/
.venv/
```

- [ ] **Step 4: Write `README.md`**

```markdown
# speechd-neural

Local neural TTS engines for speech-dispatcher.

speech-dispatcher can drive any synthesiser through `sd_generic`, but a naive
wrapper reloads the model on every utterance. speechd-neural keeps the model
resident in a small daemon, exposes a pluggable engine interface, and degrades
audibly rather than silently when a backend breaks.

Status: in development. Not yet installable from a package.

See `docs/design.md` for the design and the measurements behind it.
```

- [ ] **Step 5: Move the design doc into the repo**

```bash
cd ~
yadm rm --cached docs/specs/2026-08-09-speechd-neural-design.md
mv docs/specs/2026-08-09-speechd-neural-design.md \
   ~/git/github.com/cadrianmae/speechd-neural/docs/design.md
printf '%s\n' \
  '# speechd-neural design' '' \
  'Moved into the project repository:' \
  '`~/git/github.com/cadrianmae/speechd-neural/docs/design.md`' \
  > docs/specs/2026-08-09-speechd-neural-design.md
yadm add docs/specs/2026-08-09-speechd-neural-design.md
yadm commit -m "docs(specs): move speechd-neural design into its repo"
```

- [ ] **Step 6: Write the smoke test**

```python
# tests/test_smoke.py
def test_package_imports():
    import speechd_neural
    assert speechd_neural is not None
```

- [ ] **Step 7: Run it**

Run: `cd ~/git/github.com/cadrianmae/speechd-neural && pytest -q`
Expected: 1 passed.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "chore: scaffold repository"
```

---

### Task 2: Configuration

**Files:**
- Create: `src/speechd_neural/config.py`
- Test: `tests/test_config.py`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `load_config(path: Path | None = None) -> Config`
  - `Config` with attributes `core: CoreConfig`, `engine: EngineConfig`, `piper: PiperConfig`, `sink: SinkConfig`
  - `CoreConfig(idle_timeout: int = 600, model_evict: int = 900)`
  - `EngineConfig(default: str = "piper", fallback: tuple[str, ...] = ("espeak",))`
  - `PiperConfig(voice_dir: Path, default_voice: str, length_scale: float, device: str)`
  - `SinkConfig(base_volume: int = 40000)`
  - `DEFAULT_CONFIG_PATH: Path`
  - `ConfigError(Exception)`

- [ ] **Step 1: Write the failing tests**

```python
# tests/test_config.py
import pytest
from pathlib import Path
from speechd_neural.config import load_config, ConfigError


def test_defaults_apply_when_file_missing(tmp_path):
    cfg = load_config(tmp_path / "nope.toml")
    assert cfg.core.idle_timeout == 600
    assert cfg.engine.default == "piper"
    assert cfg.engine.fallback == ("espeak",)
    assert cfg.sink.base_volume == 40000
    assert cfg.piper.device == "auto"


def test_file_overrides_defaults(tmp_path):
    p = tmp_path / "config.toml"
    p.write_text('[core]\nidle_timeout = 60\n\n[sink]\nbase_volume = 12345\n')
    cfg = load_config(p)
    assert cfg.core.idle_timeout == 60
    assert cfg.sink.base_volume == 12345
    assert cfg.core.model_evict == 900  # untouched key keeps its default


def test_tilde_is_expanded(tmp_path):
    p = tmp_path / "config.toml"
    p.write_text('[piper]\nvoice_dir = "~/somewhere/voices"\n')
    cfg = load_config(p)
    assert cfg.piper.voice_dir.is_absolute()
    assert "~" not in str(cfg.piper.voice_dir)
    assert cfg.piper.voice_dir == Path.home() / "somewhere/voices"


def test_default_voice_dir_contains_no_hardcoded_home(tmp_path):
    cfg = load_config(tmp_path / "nope.toml")
    assert cfg.piper.voice_dir == Path.home() / ".local/share/piper-voices"


def test_malformed_toml_raises_config_error(tmp_path):
    p = tmp_path / "config.toml"
    p.write_text("this is not = = toml")
    with pytest.raises(ConfigError):
        load_config(p)


def test_unknown_key_raises_config_error(tmp_path):
    p = tmp_path / "config.toml"
    p.write_text('[core]\nidle_timeuot = 60\n')
    with pytest.raises(ConfigError) as e:
        load_config(p)
    assert "idle_timeuot" in str(e.value)
```

The unknown-key test matters: a silently ignored typo in a config key is exactly the "why isn't my setting working" failure this project exists to eliminate.

- [ ] **Step 2: Run to verify they fail**

Run: `pytest tests/test_config.py -q`
Expected: FAIL, `ModuleNotFoundError: No module named 'speechd_neural.config'`

- [ ] **Step 3: Implement**

```python
# src/speechd_neural/config.py
"""Configuration loading. The file is optional; every value has a default."""

from __future__ import annotations

import os
import tomllib
from dataclasses import dataclass, fields, replace
from pathlib import Path


class ConfigError(Exception):
    """Raised for malformed TOML or unrecognised keys."""


def _xdg_config_home() -> Path:
    return Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config")


DEFAULT_CONFIG_PATH = _xdg_config_home() / "speechd-neural" / "config.toml"


@dataclass(frozen=True)
class CoreConfig:
    idle_timeout: int = 600
    model_evict: int = 900


@dataclass(frozen=True)
class EngineConfig:
    default: str = "piper"
    fallback: tuple[str, ...] = ("espeak",)


@dataclass(frozen=True)
class PiperConfig:
    voice_dir: Path = Path()          # replaced in load_config; see _default_piper
    default_voice: str = "en_GB-cori-high.onnx"
    length_scale: float = 0.6
    device: str = "auto"              # auto | cuda | cpu


@dataclass(frozen=True)
class SinkConfig:
    base_volume: int = 40000


@dataclass(frozen=True)
class Config:
    core: CoreConfig
    engine: EngineConfig
    piper: PiperConfig
    sink: SinkConfig


def _default_piper() -> PiperConfig:
    # Computed rather than a class default so no home path is baked in at import.
    return PiperConfig(voice_dir=Path.home() / ".local/share/piper-voices")


def _expand(value):
    if isinstance(value, str) and value.startswith("~"):
        return Path(value).expanduser()
    return value


def _apply(section_name: str, base, raw: dict):
    known = {f.name for f in fields(base)}
    unknown = set(raw) - known
    if unknown:
        raise ConfigError(
            f"unknown key(s) in [{section_name}]: {', '.join(sorted(unknown))}"
        )
    updates = {}
    for key, value in raw.items():
        current = getattr(base, key)
        value = _expand(value)
        if isinstance(current, Path):
            value = Path(value).expanduser()
        elif isinstance(current, tuple):
            value = tuple(value)
        updates[key] = value
    return replace(base, **updates)


def load_config(path: Path | None = None) -> Config:
    path = Path(path) if path is not None else DEFAULT_CONFIG_PATH

    raw: dict = {}
    if path.exists():
        try:
            raw = tomllib.loads(path.read_text())
        except tomllib.TOMLDecodeError as exc:
            raise ConfigError(f"{path}: {exc}") from exc

    unknown_sections = set(raw) - {"core", "engine", "piper", "sink"}
    if unknown_sections:
        raise ConfigError(
            f"unknown section(s): {', '.join(sorted(unknown_sections))}"
        )

    return Config(
        core=_apply("core", CoreConfig(), raw.get("core", {})),
        engine=_apply("engine", EngineConfig(), raw.get("engine", {})),
        piper=_apply("piper", _default_piper(), raw.get("piper", {})),
        sink=_apply("sink", SinkConfig(), raw.get("sink", {})),
    )
```

- [ ] **Step 4: Run to verify they pass**

Run: `pytest tests/test_config.py -q`
Expected: 6 passed.

- [ ] **Step 5: Commit**

```bash
git add src/speechd_neural/config.py tests/test_config.py
git commit -m "feat(config): optional TOML config with defaults and key validation"
```

---

### Task 3: Voice parsing and speechd parameter mapping

**Files:**
- Create: `src/speechd_neural/params.py`
- Test: `tests/test_params.py`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `Voice(model: str, speaker_id: int | None)` — frozen dataclass
  - `Params(length_scale: float, volume: int, pitch_cents: int)` — frozen dataclass
  - `parse_voice(spec: str) -> Voice`
  - `map_params(rate: float, pitch: float, volume: float, *, base_length_scale: float, base_volume: int) -> Params`
  - `PITCH_THRESHOLD_CENTS: int = 10`

The formulas are lifted verbatim from the existing `run.sh`, so voices sound identical after the migration:
`length_scale = base_length_scale * 2 ** -rate`, `volume = clamp(base_volume * 2 ** volume, 0, 65536)`, `pitch_cents = int(pitch * 600)`.

- [ ] **Step 1: Write the failing tests**

```python
# tests/test_params.py
import pytest
from speechd_neural.params import Voice, parse_voice, map_params


def test_parse_voice_without_speaker():
    assert parse_voice("en_GB-cori-high.onnx") == Voice("en_GB-cori-high.onnx", None)


def test_parse_voice_with_speaker():
    assert parse_voice("en_GB-semaine-medium.onnx:2") == Voice(
        "en_GB-semaine-medium.onnx", 2
    )


def test_parse_voice_speaker_zero_is_not_none():
    # 0 is a real speaker id; a falsy-check bug would turn it into None.
    assert parse_voice("multi.onnx:0").speaker_id == 0


def test_parse_voice_rejects_non_numeric_speaker():
    with pytest.raises(ValueError):
        parse_voice("multi.onnx:alice")


def test_map_params_neutral_matches_base():
    p = map_params(0.0, 0.0, 0.0, base_length_scale=0.6, base_volume=40000)
    assert p.length_scale == pytest.approx(0.6)
    assert p.volume == 40000
    assert p.pitch_cents == 0


def test_map_params_positive_rate_speeds_up():
    # Higher rate means a SHORTER length scale.
    p = map_params(1.0, 0.0, 0.0, base_length_scale=0.6, base_volume=40000)
    assert p.length_scale == pytest.approx(0.3)


def test_map_params_negative_rate_slows_down():
    p = map_params(-1.0, 0.0, 0.0, base_length_scale=0.6, base_volume=40000)
    assert p.length_scale == pytest.approx(1.2)


def test_map_params_volume_is_clamped_to_paplay_maximum():
    p = map_params(0.0, 0.0, 1.0, base_length_scale=0.6, base_volume=40000)
    assert p.volume == 65536


def test_map_params_pitch_maps_to_cents():
    p = map_params(0.0, 0.5, 0.0, base_length_scale=0.6, base_volume=40000)
    assert p.pitch_cents == 300


def test_map_params_clamps_out_of_range_input():
    p = map_params(9.0, 9.0, 9.0, base_length_scale=0.6, base_volume=40000)
    assert p.length_scale == pytest.approx(0.3)
    assert p.pitch_cents == 600
    assert p.volume == 65536
```

- [ ] **Step 2: Run to verify they fail**

Run: `pytest tests/test_params.py -q`
Expected: FAIL, `ModuleNotFoundError: No module named 'speechd_neural.params'`

- [ ] **Step 3: Implement**

```python
# src/speechd_neural/params.py
"""Voice specifiers and the speech-dispatcher parameter mapping.

speech-dispatcher hands the generic module RATE, PITCH and VOLUME in the
range -1.0 to +1.0. The formulas below are carried over unchanged from the
previous bash implementation so voices sound identical after migration.
"""

from __future__ import annotations

from dataclasses import dataclass

PAPLAY_MAX_VOLUME = 65536
PITCH_RANGE_CENTS = 600          # +/- six semitones at full deflection
PITCH_THRESHOLD_CENTS = 10       # below this, skip the sox process entirely


@dataclass(frozen=True)
class Voice:
    model: str
    speaker_id: int | None = None


@dataclass(frozen=True)
class Params:
    length_scale: float
    volume: int
    pitch_cents: int


def parse_voice(spec: str) -> Voice:
    """Parse "model.onnx" or "model.onnx:SPEAKER_ID"."""
    model, sep, speaker = spec.partition(":")
    if not sep:
        return Voice(model, None)
    if not speaker.isdigit():
        raise ValueError(f"speaker id must be numeric, got {speaker!r}")
    return Voice(model, int(speaker))


def _clamp(value: float, low: float, high: float) -> float:
    return max(low, min(high, value))


def map_params(
    rate: float,
    pitch: float,
    volume: float,
    *,
    base_length_scale: float,
    base_volume: int,
) -> Params:
    rate = _clamp(rate, -1.0, 1.0)
    pitch = _clamp(pitch, -1.0, 1.0)
    volume = _clamp(volume, -1.0, 1.0)

    length_scale = base_length_scale * (2.0 ** -rate)
    scaled_volume = int(_clamp(base_volume * (2.0 ** volume), 0, PAPLAY_MAX_VOLUME))
    pitch_cents = int(pitch * PITCH_RANGE_CENTS)

    return Params(
        length_scale=length_scale,
        volume=scaled_volume,
        pitch_cents=pitch_cents,
    )
```

- [ ] **Step 4: Run to verify they pass**

Run: `pytest tests/test_params.py -q`
Expected: 10 passed.

- [ ] **Step 5: Commit**

```bash
git add src/speechd_neural/params.py tests/test_params.py
git commit -m "feat(params): voice parsing and speechd parameter mapping"
```

---

### Task 4: Engine protocol, FakeEngine, and the contract suite

**Files:**
- Create: `src/speechd_neural/engines/base.py`, `tests/conftest.py`, `tests/contract.py`
- Test: `tests/test_contract_fake.py`

**Interfaces:**
- Consumes: `Voice`, `Params` from Task 3.
- Produces:
  - `Synthesis = tuple[int, Iterator[bytes]]` — sample rate and s16le mono PCM chunks
  - `EngineError(Exception)`
  - `Engine` Protocol: `name: str`, `available() -> bool`, `resolve(spec: str | None) -> Voice`, `synthesize(text: str, voice: Voice, p: Params) -> Synthesis`
  - `FakeEngine(name="fake", fails=False, sample_rate=22050)` in `tests/conftest.py`
  - `EngineContract` base class in `tests/contract.py`, subclassed by each engine's test module

- [ ] **Step 1: Write the contract suite and FakeEngine**

```python
# tests/contract.py
"""Shared contract every Engine implementation must satisfy.

Subclass this in an engine's test module and set `engine`. A new engine is
proven correct by running this suite against it, with no new test code.
"""
import pytest
from speechd_neural.params import Params


class EngineContract:
    engine = None          # set by the subclass
    voice_spec = None      # a specifier this engine can resolve

    def params(self):
        return Params(length_scale=0.6, volume=40000, pitch_cents=0)

    def test_has_a_name(self):
        assert isinstance(self.engine.name, str) and self.engine.name

    def test_reports_availability(self):
        assert isinstance(self.engine.available(), bool)

    def test_resolve_returns_a_voice(self):
        voice = self.engine.resolve(self.voice_spec)
        assert voice.model

    def test_resolve_none_returns_a_default_voice(self):
        assert self.engine.resolve(None).model

    def test_synthesize_yields_pcm(self):
        voice = self.engine.resolve(self.voice_spec)
        sample_rate, chunks = self.engine.synthesize("hello", voice, self.params())
        assert sample_rate > 0
        audio = b"".join(chunks)
        assert len(audio) > 0
        assert len(audio) % 2 == 0, "s16le samples are two bytes wide"
```

```python
# tests/conftest.py
import pytest
from speechd_neural.engines.base import EngineError
from speechd_neural.params import Voice


class FakeEngine:
    """An engine that needs no model, no GPU and no audio device."""

    def __init__(self, name="fake", fails=False, sample_rate=22050, pcm=b"\x01\x00" * 64):
        self.name = name
        self.fails = fails
        self._sample_rate = sample_rate
        self._pcm = pcm
        self.calls = []

    def available(self):
        return not self.fails

    def resolve(self, spec):
        return Voice(spec or "fake-voice", None)

    def synthesize(self, text, voice, p):
        self.calls.append((text, voice, p))
        if self.fails:
            raise EngineError(f"{self.name} is configured to fail")
        return self._sample_rate, iter([self._pcm])


@pytest.fixture
def fake_engine():
    return FakeEngine()
```

```python
# tests/test_contract_fake.py
from contract import EngineContract
from conftest import FakeEngine


class TestFakeEngineContract(EngineContract):
    engine = FakeEngine()
    voice_spec = "fake-voice"
```

Add `tests` to the import path so `contract` and `conftest` import cleanly:

```toml
# append inside [tool.pytest.ini_options] in pyproject.toml
pythonpath = ["src", "tests"]
```

- [ ] **Step 2: Run to verify it fails**

Run: `pytest tests/test_contract_fake.py -q`
Expected: FAIL, `ModuleNotFoundError: No module named 'speechd_neural.engines.base'`

- [ ] **Step 3: Implement the protocol**

```python
# src/speechd_neural/engines/base.py
"""The plug point. An engine turns text into PCM and knows nothing else."""

from __future__ import annotations

from typing import Iterator, Protocol, runtime_checkable

from speechd_neural.params import Params, Voice

# Sample rate in hertz, and an iterator of signed 16-bit little-endian mono PCM.
Synthesis = tuple[int, Iterator[bytes]]


class EngineError(Exception):
    """Raised when an engine cannot synthesise. Triggers the fallback chain."""


@runtime_checkable
class Engine(Protocol):
    name: str

    def available(self) -> bool:
        """True when this engine's dependencies and models are present."""

    def resolve(self, spec: str | None) -> Voice:
        """Turn a voice specifier into a Voice. None means this engine's default."""

    def synthesize(self, text: str, voice: Voice, p: Params) -> Synthesis:
        """Synthesise text. Raises EngineError on any failure."""
```

- [ ] **Step 4: Run to verify it passes**

Run: `pytest tests/test_contract_fake.py -q`
Expected: 5 passed.

- [ ] **Step 5: Commit**

```bash
git add src/speechd_neural/engines/base.py tests/contract.py tests/conftest.py tests/test_contract_fake.py pyproject.toml
git commit -m "feat(engines): Engine protocol with a shared contract suite"
```

---

### Task 5: espeak-ng engine

**Files:**
- Create: `src/speechd_neural/engines/espeak.py`
- Test: `tests/test_espeak.py`

**Interfaces:**
- Consumes: `Engine`, `EngineError`, `Synthesis` (Task 4); `Voice`, `Params` (Task 3).
- Produces: `EspeakEngine(voice: str = "en-gb", binary: str = "espeak-ng")`, plus `WAV_HEADER_BYTES = 44` and `wpm_from_length_scale(length_scale, base_length_scale=0.6) -> int`.

This engine is the load-bearing fallback, so it is built before piper and tested without hardware. `espeak-ng --stdout` emits a 44-byte RIFF/WAVE header followed by s16le PCM; the sample rate is read from the header at offset 24 rather than assumed.

- [ ] **Step 1: Write the failing tests**

```python
# tests/test_espeak.py
import shutil
import pytest
from contract import EngineContract
from speechd_neural.engines.espeak import EspeakEngine, wpm_from_length_scale
from speechd_neural.engines.base import EngineError
from speechd_neural.params import Params, Voice

espeak_missing = shutil.which("espeak-ng") is None


def test_wpm_is_inverse_to_length_scale():
    assert wpm_from_length_scale(0.6) == 175          # neutral
    assert wpm_from_length_scale(0.3) > 175           # shorter scale, faster
    assert wpm_from_length_scale(1.2) < 175


def test_wpm_is_clamped_to_espeak_limits():
    assert wpm_from_length_scale(0.0001) == 450
    assert wpm_from_length_scale(1000.0) == 80


def test_missing_binary_reports_unavailable():
    assert EspeakEngine(binary="definitely-not-a-real-binary").available() is False


def test_missing_binary_raises_engine_error():
    engine = EspeakEngine(binary="definitely-not-a-real-binary")
    with pytest.raises(EngineError):
        sr, chunks = engine.synthesize("hi", Voice("en-gb"), Params(0.6, 40000, 0))
        b"".join(chunks)


@pytest.mark.skipif(espeak_missing, reason="espeak-ng not installed")
def test_reads_sample_rate_from_wav_header():
    engine = EspeakEngine()
    sr, chunks = engine.synthesize("hello", Voice("en-gb"), Params(0.6, 40000, 0))
    audio = b"".join(chunks)
    assert sr in (22050, 44100)          # whichever this build emits
    assert not audio.startswith(b"RIFF"), "the WAV header must be stripped"
    assert len(audio) > 1000


@pytest.mark.skipif(espeak_missing, reason="espeak-ng not installed")
class TestEspeakContract(EngineContract):
    engine = EspeakEngine()
    voice_spec = "en-gb"
```

- [ ] **Step 2: Run to verify they fail**

Run: `pytest tests/test_espeak.py -q`
Expected: FAIL, `ModuleNotFoundError: No module named 'speechd_neural.engines.espeak'`

- [ ] **Step 3: Implement**

```python
# src/speechd_neural/engines/espeak.py
"""espeak-ng engine.

Not neural, deliberately. Neural engines depend on model files, GPU runtimes
and large wheels that can each break independently; espeak-ng is a small
binary that essentially always works. An intelligible robotic voice beats
silence, so this engine is the last link in the fallback chain.
"""

from __future__ import annotations

import shutil
import struct
import subprocess
from typing import Iterator

from speechd_neural.engines.base import EngineError, Synthesis
from speechd_neural.params import Params, Voice

WAV_HEADER_BYTES = 44
NEUTRAL_WPM = 175
MIN_WPM, MAX_WPM = 80, 450
CHUNK_BYTES = 8192


def wpm_from_length_scale(length_scale: float, base_length_scale: float = 0.6) -> int:
    """Map a piper-style length scale onto espeak's words-per-minute."""
    if length_scale <= 0:
        return MAX_WPM
    wpm = int(NEUTRAL_WPM * base_length_scale / length_scale)
    return max(MIN_WPM, min(MAX_WPM, wpm))


class EspeakEngine:
    name = "espeak"

    def __init__(self, voice: str = "en-gb", binary: str = "espeak-ng"):
        self._voice = voice
        self._binary = binary

    def available(self) -> bool:
        return shutil.which(self._binary) is not None

    def resolve(self, spec: str | None) -> Voice:
        return Voice(spec or self._voice, None)

    def synthesize(self, text: str, voice: Voice, p: Params) -> Synthesis:
        if not self.available():
            raise EngineError(f"{self._binary} not found on PATH")

        cmd = [
            self._binary,
            "--stdout",
            "-v", voice.model,
            "-s", str(wpm_from_length_scale(p.length_scale)),
        ]
        try:
            proc = subprocess.Popen(
                cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
        except OSError as exc:
            raise EngineError(f"could not start {self._binary}: {exc}") from exc

        assert proc.stdin is not None and proc.stdout is not None
        proc.stdin.write(text.encode())
        proc.stdin.close()

        header = proc.stdout.read(WAV_HEADER_BYTES)
        if len(header) < WAV_HEADER_BYTES or header[:4] != b"RIFF" or header[8:12] != b"WAVE":
            proc.kill()
            raise EngineError(f"{self._binary} did not emit a WAV stream")

        sample_rate = struct.unpack("<I", header[24:28])[0]

        def chunks() -> Iterator[bytes]:
            try:
                while True:
                    data = proc.stdout.read(CHUNK_BYTES)
                    if not data:
                        break
                    yield data
            finally:
                proc.stdout.close()
                proc.wait()

        return sample_rate, chunks()
```

- [ ] **Step 4: Run to verify they pass**

Run: `pytest tests/test_espeak.py -q`
Expected: all pass (the contract subclass adds 5).

- [ ] **Step 5: Commit**

```bash
git add src/speechd_neural/engines/espeak.py tests/test_espeak.py
git commit -m "feat(engines): espeak-ng fallback engine"
```

---

### Task 6: Sink

**Files:**
- Create: `src/speechd_neural/sink.py`
- Test: `tests/test_sink.py`

**Interfaces:**
- Consumes: `Params`, `PITCH_THRESHOLD_CENTS` (Task 3).
- Produces:
  - `Sink` Protocol with `play(sample_rate: int, chunks: Iterator[bytes], p: Params) -> None`
  - `FileSink(path: Path)` — writes raw PCM, records `sample_rate` and `params`
  - `PaplaySink(runner=subprocess.Popen)` — `paplay`, inserting `sox` only when `abs(pitch_cents) >= PITCH_THRESHOLD_CENTS`
  - `SinkError(Exception)`
  - `build_pipeline(sample_rate: int, p: Params) -> list[list[str]]` — the commands the sink would run, exposed so tests can assert on them without spawning anything

- [ ] **Step 1: Write the failing tests**

```python
# tests/test_sink.py
import pytest
from speechd_neural.sink import FileSink, build_pipeline
from speechd_neural.params import Params


def test_file_sink_writes_all_pcm(tmp_path):
    out = tmp_path / "out.raw"
    sink = FileSink(out)
    sink.play(22050, iter([b"ab", b"cd"]), Params(0.6, 40000, 0))
    assert out.read_bytes() == b"abcd"
    assert sink.sample_rate == 22050


def test_pipeline_is_paplay_only_when_pitch_is_neutral():
    cmds = build_pipeline(22050, Params(0.6, 40000, 0))
    assert len(cmds) == 1
    assert cmds[0][0] == "paplay"


def test_pipeline_passes_sample_rate_and_volume_to_paplay():
    cmds = build_pipeline(16000, Params(0.6, 12345, 0))
    joined = " ".join(cmds[0])
    assert "--rate=16000" in joined
    assert "--volume=12345" in joined
    assert "--format=s16le" in joined


def test_pipeline_inserts_sox_above_the_pitch_threshold():
    cmds = build_pipeline(22050, Params(0.6, 40000, 300))
    assert [c[0] for c in cmds] == ["sox", "paplay"]
    assert "300" in cmds[0]


def test_pipeline_skips_sox_below_the_pitch_threshold():
    # 9 cents is inaudible; spawning a process for it is waste.
    cmds = build_pipeline(22050, Params(0.6, 40000, 9))
    assert [c[0] for c in cmds] == ["paplay"]


def test_pipeline_inserts_sox_for_negative_pitch():
    cmds = build_pipeline(22050, Params(0.6, 40000, -300))
    assert [c[0] for c in cmds] == ["sox", "paplay"]
```

- [ ] **Step 2: Run to verify they fail**

Run: `pytest tests/test_sink.py -q`
Expected: FAIL, `ModuleNotFoundError: No module named 'speechd_neural.sink'`

- [ ] **Step 3: Implement**

```python
# src/speechd_neural/sink.py
"""Playback. Shared by every engine, so they all inherit the same volume
and pitch behaviour."""

from __future__ import annotations

import subprocess
from pathlib import Path
from typing import Iterator, Protocol

from speechd_neural.params import PITCH_THRESHOLD_CENTS, Params


class SinkError(Exception):
    """Raised when playback cannot start or fails mid-stream."""


class Sink(Protocol):
    def play(self, sample_rate: int, chunks: Iterator[bytes], p: Params) -> None: ...


def build_pipeline(sample_rate: int, p: Params) -> list[list[str]]:
    """The commands playback would run, innermost first.

    Exposed separately so the shape of the pipeline can be tested without
    spawning any processes.
    """
    paplay = [
        "paplay", "--raw", "--format=s16le",
        f"--rate={sample_rate}", "--channels=1", f"--volume={p.volume}",
    ]
    if abs(p.pitch_cents) < PITCH_THRESHOLD_CENTS:
        return [paplay]

    sox = [
        "sox",
        "-t", "raw", "-r", str(sample_rate), "-e", "signed", "-b", "16", "-c", "1", "-",
        "-t", "raw", "-r", str(sample_rate), "-e", "signed", "-b", "16", "-c", "1", "-",
        "pitch", str(p.pitch_cents),
    ]
    return [sox, paplay]


class FileSink:
    """Writes PCM to a file. Used by tests and by `speechd-neural say --to`."""

    def __init__(self, path: Path):
        self.path = Path(path)
        self.sample_rate: int | None = None
        self.params: Params | None = None

    def play(self, sample_rate: int, chunks: Iterator[bytes], p: Params) -> None:
        self.sample_rate = sample_rate
        self.params = p
        with open(self.path, "wb") as handle:
            for chunk in chunks:
                handle.write(chunk)


class PaplaySink:
    """Plays through PipeWire/PulseAudio, with an optional sox pitch shift."""

    def __init__(self, popen=subprocess.Popen):
        self._popen = popen

    def play(self, sample_rate: int, chunks: Iterator[bytes], p: Params) -> None:
        commands = build_pipeline(sample_rate, p)
        procs: list = []
        try:
            previous_stdout = subprocess.PIPE
            for index, cmd in enumerate(commands):
                stdin = subprocess.PIPE if index == 0 else procs[-1].stdout
                stdout = subprocess.PIPE if index < len(commands) - 1 else None
                procs.append(self._popen(cmd, stdin=stdin, stdout=stdout))
                if index > 0:
                    procs[-2].stdout.close()   # let the upstream see SIGPIPE
        except OSError as exc:
            for proc in procs:
                proc.kill()
            raise SinkError(f"could not start playback: {exc}") from exc

        head = procs[0]
        assert head.stdin is not None
        try:
            for chunk in chunks:
                head.stdin.write(chunk)
        except BrokenPipeError as exc:
            raise SinkError("playback stopped early") from exc
        finally:
            head.stdin.close()
            for proc in procs:
                proc.wait()

        if procs[-1].returncode not in (0, None):
            raise SinkError(f"playback exited {procs[-1].returncode}")
```

- [ ] **Step 4: Run to verify they pass**

Run: `pytest tests/test_sink.py -q`
Expected: 6 passed.

- [ ] **Step 5: Commit**

```bash
git add src/speechd_neural/sink.py tests/test_sink.py
git commit -m "feat(sink): shared playback with conditional pitch shift"
```

---

### Task 7: CUDA library discovery and re-exec

**Files:**
- Create: `src/speechd_neural/cuda.py`
- Test: `tests/test_cuda.py`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `nvidia_lib_paths(site_root: Path | None = None) -> list[Path]`
  - `ensure_cuda_env(argv: list[str], environ: dict, *, site_root=None, exec_fn=os.execve) -> None`
  - `REEXEC_GUARD = "SPEECHD_NEURAL_REEXEC"`

This is the fix for spec defect 2. The nvidia wheels ship CUDA libraries under `site-packages/nvidia/*/lib`, which the dynamic linker must know about **before** the process starts. Rather than pin a python version in the unit, the daemon discovers the paths itself and re-executes once with a corrected environment. The guard variable stops an exec loop.

- [ ] **Step 1: Write the failing tests**

```python
# tests/test_cuda.py
from pathlib import Path
from speechd_neural.cuda import nvidia_lib_paths, ensure_cuda_env, REEXEC_GUARD


def _fake_site(tmp_path, python_version="python3.14"):
    root = tmp_path / ".local/lib" / python_version / "site-packages/nvidia"
    for pkg in ("cublas", "cudnn", "cuda_runtime"):
        (root / pkg / "lib").mkdir(parents=True)
    return tmp_path / ".local/lib"


def test_discovers_every_nvidia_lib_dir(tmp_path):
    site = _fake_site(tmp_path)
    found = nvidia_lib_paths(site)
    assert len(found) == 3
    assert all(p.name == "lib" for p in found)


def test_discovery_survives_a_python_version_bump(tmp_path):
    # The whole point: no version is hardcoded anywhere.
    site = _fake_site(tmp_path, python_version="python3.99")
    assert len(nvidia_lib_paths(site)) == 3


def test_no_nvidia_wheels_yields_nothing(tmp_path):
    (tmp_path / "empty").mkdir()
    assert nvidia_lib_paths(tmp_path / "empty") == []


def test_reexecs_once_when_paths_are_missing(tmp_path):
    site = _fake_site(tmp_path)
    calls = []
    env = {}
    ensure_cuda_env(["daemon.py"], env, site_root=site,
                    exec_fn=lambda *a: calls.append(a))
    assert len(calls) == 1
    new_env = calls[0][2]
    assert new_env[REEXEC_GUARD] == "1"
    assert "cublas" in new_env["LD_LIBRARY_PATH"]


def test_does_not_reexec_when_the_guard_is_set(tmp_path):
    site = _fake_site(tmp_path)
    calls = []
    ensure_cuda_env(["daemon.py"], {REEXEC_GUARD: "1"}, site_root=site,
                    exec_fn=lambda *a: calls.append(a))
    assert calls == []


def test_does_not_reexec_when_paths_are_already_present(tmp_path):
    site = _fake_site(tmp_path)
    present = ":".join(str(p) for p in nvidia_lib_paths(site))
    calls = []
    ensure_cuda_env(["daemon.py"], {"LD_LIBRARY_PATH": present}, site_root=site,
                    exec_fn=lambda *a: calls.append(a))
    assert calls == []


def test_preserves_an_existing_ld_library_path(tmp_path):
    site = _fake_site(tmp_path)
    calls = []
    ensure_cuda_env(["daemon.py"], {"LD_LIBRARY_PATH": "/opt/custom/lib"},
                    site_root=site, exec_fn=lambda *a: calls.append(a))
    assert "/opt/custom/lib" in calls[0][2]["LD_LIBRARY_PATH"]
```

- [ ] **Step 2: Run to verify they fail**

Run: `pytest tests/test_cuda.py -q`
Expected: FAIL, `ModuleNotFoundError: No module named 'speechd_neural.cuda'`

- [ ] **Step 3: Implement**

```python
# src/speechd_neural/cuda.py
"""Locate the CUDA libraries shipped in the nvidia wheels, without pinning
a python version.

The dynamic linker reads LD_LIBRARY_PATH at process start, so setting it from
inside the process is too late. The daemon therefore discovers the paths and
re-executes itself exactly once with a corrected environment. A guard variable
prevents an exec loop, and nothing is cached, because a stale cache is itself
a failure mode.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

REEXEC_GUARD = "SPEECHD_NEURAL_REEXEC"


def _default_site_root() -> Path:
    return Path.home() / ".local/lib"


def nvidia_lib_paths(site_root: Path | None = None) -> list[Path]:
    """Every `nvidia/*/lib` directory under any python version's site-packages."""
    root = Path(site_root) if site_root is not None else _default_site_root()
    if not root.exists():
        return []
    return sorted(
        p for p in root.glob("python*/site-packages/nvidia/*/lib") if p.is_dir()
    )


def ensure_cuda_env(
    argv: list[str],
    environ: dict,
    *,
    site_root: Path | None = None,
    exec_fn=os.execve,
) -> None:
    """Re-exec once with the nvidia lib paths on LD_LIBRARY_PATH, if needed."""
    if environ.get(REEXEC_GUARD):
        return

    paths = nvidia_lib_paths(site_root)
    if not paths:
        return

    current = environ.get("LD_LIBRARY_PATH", "")
    entries = current.split(":") if current else []
    missing = [str(p) for p in paths if str(p) not in entries]
    if not missing:
        return

    new_env = dict(environ)
    new_env["LD_LIBRARY_PATH"] = ":".join(missing + entries) if entries else ":".join(missing)
    new_env[REEXEC_GUARD] = "1"
    exec_fn(sys.executable, [sys.executable, *argv], new_env)
```

- [ ] **Step 4: Run to verify they pass**

Run: `pytest tests/test_cuda.py -q`
Expected: 7 passed.

- [ ] **Step 5: Commit**

```bash
git add src/speechd_neural/cuda.py tests/test_cuda.py
git commit -m "feat(cuda): discover nvidia libs without pinning a python version"
```

---

### Task 8: piper engine with device fallback

**Files:**
- Create: `src/speechd_neural/engines/piper.py`
- Test: `tests/test_piper.py`

**Interfaces:**
- Consumes: `Engine`, `EngineError`, `Synthesis` (Task 4); `Voice`, `Params` (Task 3); `PiperConfig` (Task 2).
- Produces: `PiperEngine(cfg: PiperConfig, loader=None)` with `device: str | None` (resolved after first load), `evict(older_than: float) -> list[str]`, and `loaded_models() -> list[str]`.

`loader` is injected so every device-fallback and caching test runs without a GPU or a model file. Real piper is exercised only by the `@pytest.mark.gpu` contract subclass.

- [ ] **Step 1: Write the failing tests**

```python
# tests/test_piper.py
import pytest
from pathlib import Path
from contract import EngineContract
from speechd_neural.config import PiperConfig, load_config
from speechd_neural.engines.base import EngineError
from speechd_neural.engines.piper import PiperEngine
from speechd_neural.params import Params, Voice


class FakeVoice:
    def __init__(self, sample_rate=22050):
        self.config = type("cfg", (), {"sample_rate": sample_rate})()
        self.calls = []

    def synthesize(self, text, syn_config=None):
        self.calls.append((text, syn_config))
        yield type("chunk", (), {"audio_int16_bytes": b"\x02\x00" * 32})()


def cfg(tmp_path, device="auto"):
    voices = tmp_path / "voices"
    voices.mkdir(exist_ok=True)
    (voices / "test.onnx").write_bytes(b"")
    return PiperConfig(voice_dir=voices, default_voice="test.onnx",
                       length_scale=0.6, device=device)


def test_resolve_none_uses_the_configured_default(tmp_path):
    engine = PiperEngine(cfg(tmp_path), loader=lambda path, use_cuda: FakeVoice())
    assert engine.resolve(None) == Voice("test.onnx", None)


def test_available_is_false_when_the_model_is_absent(tmp_path):
    c = cfg(tmp_path)
    (c.voice_dir / "test.onnx").unlink()
    engine = PiperEngine(c, loader=lambda path, use_cuda: FakeVoice())
    assert engine.available() is False


def test_auto_prefers_cuda(tmp_path):
    seen = []

    def loader(path, use_cuda):
        seen.append(use_cuda)
        return FakeVoice()

    engine = PiperEngine(cfg(tmp_path), loader=loader)
    engine.synthesize("hi", Voice("test.onnx"), Params(0.6, 40000, 0))
    assert seen == [True]
    assert engine.device == "cuda"


def test_auto_falls_back_to_cpu_when_cuda_fails(tmp_path):
    seen = []

    def loader(path, use_cuda):
        seen.append(use_cuda)
        if use_cuda:
            raise RuntimeError("no CUDA provider")
        return FakeVoice()

    engine = PiperEngine(cfg(tmp_path), loader=loader)
    sr, chunks = engine.synthesize("hi", Voice("test.onnx"), Params(0.6, 40000, 0))
    assert b"".join(chunks)
    assert seen == [True, False]
    assert engine.device == "cpu"


def test_device_cpu_never_attempts_cuda(tmp_path):
    seen = []
    engine = PiperEngine(
        cfg(tmp_path, device="cpu"),
        loader=lambda path, use_cuda: (seen.append(use_cuda), FakeVoice())[1],
    )
    engine.synthesize("hi", Voice("test.onnx"), Params(0.6, 40000, 0))
    assert seen == [False]


def test_device_cuda_does_not_fall_back(tmp_path):
    def loader(path, use_cuda):
        raise RuntimeError("no CUDA provider")

    engine = PiperEngine(cfg(tmp_path, device="cuda"), loader=loader)
    with pytest.raises(EngineError):
        engine.synthesize("hi", Voice("test.onnx"), Params(0.6, 40000, 0))


def test_model_is_loaded_once_and_cached(tmp_path):
    loads = []

    def loader(path, use_cuda):
        loads.append(path)
        return FakeVoice()

    engine = PiperEngine(cfg(tmp_path), loader=loader)
    for _ in range(3):
        sr, chunks = engine.synthesize("hi", Voice("test.onnx"), Params(0.6, 40000, 0))
        b"".join(chunks)
    assert len(loads) == 1
    assert engine.loaded_models() == ["test.onnx"]


def test_evict_drops_models_older_than_the_cutoff(tmp_path):
    engine = PiperEngine(cfg(tmp_path), loader=lambda path, use_cuda: FakeVoice())
    engine.synthesize("hi", Voice("test.onnx"), Params(0.6, 40000, 0))
    assert engine.evict(older_than=-1) == ["test.onnx"]   # everything is stale
    assert engine.loaded_models() == []


def test_missing_model_file_raises_engine_error(tmp_path):
    engine = PiperEngine(cfg(tmp_path), loader=lambda path, use_cuda: FakeVoice())
    with pytest.raises(EngineError) as e:
        engine.synthesize("hi", Voice("absent.onnx"), Params(0.6, 40000, 0))
    assert "absent.onnx" in str(e.value)


def test_speaker_id_and_length_scale_reach_piper(tmp_path):
    fake = FakeVoice()
    engine = PiperEngine(cfg(tmp_path), loader=lambda path, use_cuda: fake)
    sr, chunks = engine.synthesize("hi", Voice("test.onnx", 2), Params(0.9, 40000, 0))
    b"".join(chunks)
    _, syn_config = fake.calls[0]
    assert syn_config.speaker_id == 2
    assert syn_config.length_scale == pytest.approx(0.9)


_INSTALLED = load_config().piper
_HAS_MODEL = (_INSTALLED.voice_dir / _INSTALLED.default_voice).exists()


@pytest.mark.gpu
@pytest.mark.skipif(not _HAS_MODEL, reason="no piper model installed")
class TestPiperContract(EngineContract):
    """Real piper against the real configured model. Run with: pytest -m gpu"""

    engine = PiperEngine(_INSTALLED)
    voice_spec = None
```

`voice_spec = None` makes the contract resolve this engine's configured default, which is the only voice guaranteed to exist on an arbitrary machine.

- [ ] **Step 2: Run to verify they fail**

Run: `pytest tests/test_piper.py -q`
Expected: FAIL, `ModuleNotFoundError: No module named 'speechd_neural.engines.piper'`

- [ ] **Step 3: Implement**

```python
# src/speechd_neural/engines/piper.py
"""piper ONNX engine, with CUDA -> CPU fallback and a model cache."""

from __future__ import annotations

import logging
import time
from pathlib import Path
from typing import Iterator

from speechd_neural.config import PiperConfig
from speechd_neural.engines.base import EngineError, Synthesis
from speechd_neural.params import Params, Voice

log = logging.getLogger(__name__)


def _default_loader(path: str, use_cuda: bool):
    from piper.voice import PiperVoice
    return PiperVoice.load(path, use_cuda=use_cuda)


class PiperEngine:
    name = "piper"

    def __init__(self, cfg: PiperConfig, loader=None):
        self._cfg = cfg
        self._loader = loader or _default_loader
        self._models: dict[str, object] = {}
        self._last_used: dict[str, float] = {}
        self.device: str | None = None

    def available(self) -> bool:
        return (self._cfg.voice_dir / self._cfg.default_voice).exists()

    def resolve(self, spec: str | None) -> Voice:
        from speechd_neural.params import parse_voice
        return parse_voice(spec) if spec else Voice(self._cfg.default_voice, None)

    def loaded_models(self) -> list[str]:
        return sorted(self._models)

    def evict(self, older_than: float) -> list[str]:
        """Drop models unused for longer than `older_than` seconds."""
        now = time.monotonic()
        stale = [k for k, t in self._last_used.items() if now - t > older_than]
        for key in stale:
            log.info("evicting model %s", key)
            del self._models[key]
            del self._last_used[key]
        return sorted(stale)

    def _devices_to_try(self) -> list[str]:
        if self.device:                      # decided earlier this session
            return [self.device]
        if self._cfg.device == "cpu":
            return ["cpu"]
        if self._cfg.device == "cuda":
            return ["cuda"]
        return ["cuda", "cpu"]

    def _load(self, model_name: str):
        if model_name in self._models:
            self._last_used[model_name] = time.monotonic()
            return self._models[model_name]

        path = self._cfg.voice_dir / model_name
        if not path.exists():
            raise EngineError(f"model not found: {path}")

        errors = []
        for device in self._devices_to_try():
            try:
                started = time.monotonic()
                voice = self._loader(str(path), use_cuda=(device == "cuda"))
            except Exception as exc:         # onnxruntime raises many types
                log.warning("[WARN] loading %s on %s failed: %s", model_name, device, exc)
                errors.append(f"{device}: {exc}")
                continue
            log.info(
                "loaded %s on %s in %.2fs", model_name, device,
                time.monotonic() - started,
            )
            self.device = device
            self._models[model_name] = voice
            self._last_used[model_name] = time.monotonic()
            return voice

        raise EngineError(f"could not load {model_name} ({'; '.join(errors)})")

    def synthesize(self, text: str, voice: Voice, p: Params) -> Synthesis:
        from piper.config import SynthesisConfig

        model = self._load(voice.model)
        syn_config = SynthesisConfig(
            speaker_id=voice.speaker_id,
            length_scale=p.length_scale,
        )

        def chunks() -> Iterator[bytes]:
            for chunk in model.synthesize(text, syn_config):
                yield chunk.audio_int16_bytes

        return model.config.sample_rate, chunks()
```

Note the `SynthesisConfig` import is inside `synthesize` so the module imports on a machine without piper installed, which the fallback path depends on.

- [ ] **Step 4: Run to verify they pass**

Run: `pytest tests/test_piper.py -q -m "not gpu"`
Expected: 10 passed. Then, on a machine with a real model: `pytest tests/test_piper.py -m gpu` runs the contract suite against real piper (5 more).

- [ ] **Step 5: Commit**

```bash
git add src/speechd_neural/engines/piper.py tests/test_piper.py
git commit -m "feat(engines): piper engine with CUDA to CPU fallback and model cache"
```

---

### Task 9: Engine chain and degradation notice

**Files:**
- Create: `src/speechd_neural/chain.py`
- Test: `tests/test_chain.py`

**Interfaces:**
- Consumes: `Engine`, `EngineError` (Task 4).
- Produces:
  - `EngineChain(engines: list[Engine], notifier: Callable[[str, str], None] | None = None, first_chunk_timeout: float = 10.0)`
  - `EngineChain.synthesize(text, voice_spec, p) -> tuple[str, Synthesis]` — engine name plus synthesis
  - `EngineChain.by_name(name) -> Engine | None`
  - `EngineChain.engines -> list[Engine]` — public accessor used by the daemon
  - `notify_desktop(title: str, body: str) -> None` — best-effort `notify-send`
  - `ChainExhausted(Exception)`

This is spec failure-handling points 3, 4 and 8. The notice fires **once per engine pair per session**: enough to tell you the system degraded, not enough to become noise.

The watchdog (point 8) is here rather than in the daemon because a hang and a
crash should have the same consequence: fall through to the next engine. An
engine that returns a generator which never yields would otherwise block
forever, since `synthesize()` returns before any audio is produced. The chain
therefore pulls the **first** chunk under a timeout and, on expiry, treats the
engine as failed.

- [ ] **Step 1: Write the failing tests**

```python
# tests/test_chain.py
import pytest
from conftest import FakeEngine
from speechd_neural.chain import EngineChain, ChainExhausted
from speechd_neural.params import Params

P = Params(0.6, 40000, 0)


def test_uses_the_first_engine_when_it_works():
    first, second = FakeEngine("first"), FakeEngine("second")
    name, (sr, chunks) = EngineChain([first, second]).synthesize("hi", None, P)
    assert name == "first"
    assert b"".join(chunks)
    assert second.calls == []


def test_falls_through_to_the_next_engine():
    broken, good = FakeEngine("broken", fails=True), FakeEngine("good")
    name, (sr, chunks) = EngineChain([broken, good]).synthesize("hi", None, P)
    assert name == "good"
    assert b"".join(chunks)


def test_raises_when_every_engine_fails():
    chain = EngineChain([FakeEngine("a", fails=True), FakeEngine("b", fails=True)])
    with pytest.raises(ChainExhausted) as e:
        chain.synthesize("hi", None, P)
    assert "a" in str(e.value) and "b" in str(e.value)


def test_degradation_notifies_once_per_session():
    notices = []
    chain = EngineChain(
        [FakeEngine("broken", fails=True), FakeEngine("good")],
        notifier=lambda title, body: notices.append(body),
    )
    for _ in range(5):
        name, (sr, chunks) = chain.synthesize("hi", None, P)
        b"".join(chunks)
    assert len(notices) == 1
    assert "broken" in notices[0] and "good" in notices[0]


def test_no_notice_when_nothing_degrades():
    notices = []
    chain = EngineChain([FakeEngine("fine")], notifier=lambda t, b: notices.append(b))
    chain.synthesize("hi", None, P)
    assert notices == []


def test_by_name_finds_engines():
    chain = EngineChain([FakeEngine("a"), FakeEngine("b")])
    assert chain.by_name("b").name == "b"
    assert chain.by_name("nope") is None


def test_a_failing_notifier_never_breaks_speech():
    def explode(title, body):
        raise RuntimeError("notify-send is missing")

    chain = EngineChain([FakeEngine("broken", fails=True), FakeEngine("good")],
                        notifier=explode)
    name, (sr, chunks) = chain.synthesize("hi", None, P)
    assert name == "good"


def test_by_name_and_engines_expose_the_chain():
    a, b = FakeEngine("a"), FakeEngine("b")
    chain = EngineChain([a, b])
    assert chain.engines == [a, b]


class HangingEngine(FakeEngine):
    """Returns a generator that never yields, simulating a wedged backend."""

    def synthesize(self, text, voice, p):
        import time

        def never():
            time.sleep(3600)
            yield b""

        return 22050, never()


def test_a_hanging_engine_falls_through_to_the_next():
    good = FakeEngine("good")
    chain = EngineChain([HangingEngine("wedged"), good], first_chunk_timeout=0.2)
    name, (sr, chunks) = chain.synthesize("hi", None, P)
    assert name == "good"
    assert b"".join(chunks)


def test_the_watchdog_does_not_truncate_a_healthy_stream():
    engine = FakeEngine("fine", pcm=b"\x07\x00" * 100)
    chain = EngineChain([engine], first_chunk_timeout=5.0)
    name, (sr, chunks) = chain.synthesize("hi", None, P)
    assert b"".join(chunks) == b"\x07\x00" * 100, "the first chunk must be replayed"
```

- [ ] **Step 2: Run to verify they fail**

Run: `pytest tests/test_chain.py -q`
Expected: FAIL, `ModuleNotFoundError: No module named 'speechd_neural.chain'`

- [ ] **Step 3: Implement**

```python
# src/speechd_neural/chain.py
"""Engine fallback. Never fail silently: if a preferred engine breaks, speak
with the next one and say so, once."""

from __future__ import annotations

import logging
import shutil
import subprocess
import threading
from typing import Callable, Iterator

from speechd_neural.engines.base import Engine, EngineError, Synthesis

log = logging.getLogger(__name__)


class ChainExhausted(Exception):
    """Every engine failed. Nothing was spoken."""


def notify_desktop(title: str, body: str) -> None:
    """Best-effort desktop notification. Never raises."""
    if not shutil.which("notify-send"):
        return
    try:
        subprocess.run(
            ["notify-send", "-a", "speechd-neural", "-u", "normal", "--", title, body],
            check=False, timeout=5,
        )
    except Exception:                        # notification must never break speech
        log.debug("notify-send failed", exc_info=True)


def _first_chunk(chunks: Iterator[bytes], timeout: float) -> tuple[bytes, Iterator[bytes]]:
    """Pull the first chunk under a timeout, then hand back the whole stream.

    An engine can hang *after* synthesize() returns, because the generator does
    the real work. Waiting for the first chunk in a worker thread turns that
    hang into an ordinary failure the chain can fall through. The thread is a
    daemon thread, so a genuinely wedged engine cannot keep the process alive.
    """
    box: dict = {}

    def pull():
        try:
            box["chunk"] = next(chunks)
        except StopIteration:
            box["chunk"] = b""
        except Exception as exc:
            box["error"] = exc

    worker = threading.Thread(target=pull, daemon=True)
    worker.start()
    worker.join(timeout)

    if worker.is_alive():
        raise EngineError(f"no audio within {timeout}s")
    if "error" in box:
        raise EngineError(str(box["error"]))

    head = box["chunk"]

    def replayed() -> Iterator[bytes]:
        if head:
            yield head
        yield from chunks

    return head, replayed()


class EngineChain:
    def __init__(
        self,
        engines: list[Engine],
        notifier: Callable[[str, str], None] | None = None,
        first_chunk_timeout: float = 10.0,
    ):
        if not engines:
            raise ValueError("an engine chain needs at least one engine")
        self._engines = engines
        self._notifier = notifier or notify_desktop
        self._announced: set[str] = set()
        self._first_chunk_timeout = first_chunk_timeout

    @property
    def engines(self) -> list[Engine]:
        return list(self._engines)

    def by_name(self, name: str) -> Engine | None:
        return next((e for e in self._engines if e.name == name), None)

    def _announce(self, failed: str, used: str, reason: str) -> None:
        key = f"{failed}->{used}"
        if key in self._announced:
            return
        self._announced.add(key)
        try:
            self._notifier(
                "TTS degraded",
                f"{failed} unavailable, using {used} ({reason})",
            )
        except Exception:                    # a broken notifier must not stop speech
            log.debug("notifier raised", exc_info=True)

    def synthesize(self, text: str, voice_spec: str | None, p) -> tuple[str, Synthesis]:
        preferred = self._engines[0].name
        errors: list[str] = []

        for engine in self._engines:
            try:
                voice = engine.resolve(voice_spec)
                sample_rate, chunks = engine.synthesize(text, voice, p)
                # The watchdog: a hang before the first chunk counts as a failure.
                _, stream = _first_chunk(chunks, self._first_chunk_timeout)
            except Exception as exc:
                log.warning("[WARN] engine %s failed: %s", engine.name, exc)
                errors.append(f"{engine.name}: {exc}")
                continue

            if engine.name != preferred:
                self._announce(preferred, engine.name, errors[0].split(": ", 1)[-1])
            return engine.name, (sample_rate, stream)

        raise ChainExhausted("; ".join(errors))
```

- [ ] **Step 4: Run to verify they pass**

Run: `pytest tests/test_chain.py -q`
Expected: 10 passed. The hanging-engine test should take about 0.2s, not 3600s.

- [ ] **Step 5: Commit**

```bash
git add src/speechd_neural/chain.py tests/test_chain.py
git commit -m "feat(chain): engine fallback, watchdog and degradation notice"
```

---

### Task 10: Wire protocol

**Files:**
- Create: `src/speechd_neural/protocol.py`
- Test: `tests/test_protocol.py`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `MAGIC = b"SPNL"`, `HEADER_BYTES = 8`
  - `encode_request(text, voice, rate, pitch, volume) -> bytes` (one JSON line)
  - `decode_request(line: bytes) -> dict`
  - `encode_header(sample_rate: int) -> bytes`
  - `decode_header(raw: bytes) -> int`
  - `encode_status_request() -> bytes`, and requests carry `"op": "speak" | "status"`
  - `ProtocolError(Exception)`

- [ ] **Step 1: Write the failing tests**

```python
# tests/test_protocol.py
import pytest
from speechd_neural.protocol import (
    MAGIC, HEADER_BYTES, encode_request, decode_request,
    encode_header, decode_header, encode_status_request, ProtocolError,
)


def test_request_round_trips():
    raw = encode_request("hello", "v.onnx:1", rate=0.5, pitch=-0.25, volume=0.0)
    assert raw.endswith(b"\n")
    req = decode_request(raw)
    assert req["op"] == "speak"
    assert req["text"] == "hello"
    assert req["voice"] == "v.onnx:1"
    assert req["rate"] == 0.5
    assert req["pitch"] == -0.25


def test_request_survives_unicode_and_newlines():
    raw = encode_request("café\nsecond line", None, 0, 0, 0)
    assert raw.count(b"\n") == 1, "the payload must stay on a single line"
    assert decode_request(raw)["text"] == "café\nsecond line"


def test_status_request():
    assert decode_request(encode_status_request())["op"] == "status"


def test_header_round_trips():
    raw = encode_header(22050)
    assert len(raw) == HEADER_BYTES
    assert raw.startswith(MAGIC)
    assert decode_header(raw) == 22050


def test_bad_magic_is_rejected():
    with pytest.raises(ProtocolError):
        decode_header(b"XXXX" + b"\x00\x00\x00\x00")


def test_short_header_is_rejected():
    with pytest.raises(ProtocolError):
        decode_header(b"SPNL")


def test_malformed_request_is_rejected():
    with pytest.raises(ProtocolError):
        decode_request(b"not json\n")
```

- [ ] **Step 2: Run to verify they fail**

Run: `pytest tests/test_protocol.py -q`
Expected: FAIL, `ModuleNotFoundError: No module named 'speechd_neural.protocol'`

- [ ] **Step 3: Implement**

```python
# src/speechd_neural/protocol.py
"""Wire format between the front-end client and the daemon.

Request:  one JSON object on a single line, UTF-8.
Response: an 8-byte header (MAGIC + uint32 sample rate, little endian),
          then raw s16le mono PCM until the socket closes.
"""

from __future__ import annotations

import json
import struct

MAGIC = b"SPNL"
HEADER_BYTES = 8


class ProtocolError(Exception):
    """Raised on a malformed request or response header."""


def encode_request(
    text: str,
    voice: str | None,
    rate: float,
    pitch: float,
    volume: float,
) -> bytes:
    payload = {
        "op": "speak",
        "text": text,
        "voice": voice,
        "rate": rate,
        "pitch": pitch,
        "volume": volume,
    }
    # ensure_ascii keeps any newline inside the text escaped, so the request
    # stays exactly one line on the wire.
    return (json.dumps(payload, ensure_ascii=True) + "\n").encode("utf-8")


def encode_status_request() -> bytes:
    return (json.dumps({"op": "status"}) + "\n").encode("utf-8")


def decode_request(line: bytes) -> dict:
    try:
        payload = json.loads(line.decode("utf-8"))
    except (ValueError, UnicodeDecodeError) as exc:
        raise ProtocolError(f"malformed request: {exc}") from exc
    if not isinstance(payload, dict) or "op" not in payload:
        raise ProtocolError("request must be an object with an 'op' key")
    return payload


def encode_header(sample_rate: int) -> bytes:
    return MAGIC + struct.pack("<I", sample_rate)


def decode_header(raw: bytes) -> int:
    if len(raw) < HEADER_BYTES:
        raise ProtocolError("short response header")
    if raw[:4] != MAGIC:
        raise ProtocolError(f"bad magic: {raw[:4]!r}")
    return struct.unpack("<I", raw[4:8])[0]
```

- [ ] **Step 4: Run to verify they pass**

Run: `pytest tests/test_protocol.py -q`
Expected: 7 passed.

- [ ] **Step 5: Commit**

```bash
git add src/speechd_neural/protocol.py tests/test_protocol.py
git commit -m "feat(protocol): wire format for the daemon socket"
```

---

### Task 11: Daemon

**Files:**
- Create: `src/speechd_neural/daemon.py`
- Test: `tests/test_daemon.py`

**Interfaces:**
- Consumes: `Config` (Task 2), `EngineChain`/`ChainExhausted` (Task 9), protocol helpers (Task 10), `map_params` (Task 3), `ensure_cuda_env` (Task 7).
- Produces:
  - `Daemon(chain: EngineChain, cfg: Config)` with `handle(conn)` and `serve(server_socket)`
  - `status_payload(chain, cfg, started_at) -> dict`
  - `socket_path() -> Path`
  - `main() -> int`

Idle timeout comes from config, never a literal — that is one of the spec's named regression tests.

- [ ] **Step 1: Write the failing tests**

```python
# tests/test_daemon.py
import json
import socket
import threading
import pytest
from conftest import FakeEngine
from speechd_neural.chain import EngineChain
from speechd_neural.config import Config, CoreConfig, EngineConfig, PiperConfig, SinkConfig
from speechd_neural.daemon import Daemon
from speechd_neural.protocol import (
    encode_request, encode_status_request, decode_header, HEADER_BYTES,
)


def make_config(idle_timeout=600, tmp_path=None):
    return Config(
        core=CoreConfig(idle_timeout=idle_timeout, model_evict=900),
        engine=EngineConfig(),
        piper=PiperConfig(voice_dir=(tmp_path or __import__("pathlib").Path("/tmp"))),
        sink=SinkConfig(),
    )


def roundtrip(daemon, request: bytes) -> bytes:
    """Run one request through the daemon over a real socketpair."""
    left, right = socket.socketpair()
    thread = threading.Thread(target=daemon.handle, args=(right,))
    thread.start()
    left.sendall(request)
    out = b""
    while True:
        data = left.recv(4096)
        if not data:
            break
        out += data
    thread.join(timeout=5)
    left.close()
    return out


def test_speak_returns_header_then_pcm(tmp_path):
    engine = FakeEngine(sample_rate=16000, pcm=b"\x03\x00" * 10)
    daemon = Daemon(EngineChain([engine]), make_config(tmp_path=tmp_path))
    out = roundtrip(daemon, encode_request("hello", None, 0, 0, 0))
    assert decode_header(out[:HEADER_BYTES]) == 16000
    assert out[HEADER_BYTES:] == b"\x03\x00" * 10


def test_params_reach_the_engine(tmp_path):
    engine = FakeEngine()
    daemon = Daemon(EngineChain([engine]), make_config(tmp_path=tmp_path))
    roundtrip(daemon, encode_request("hi", None, rate=1.0, pitch=0.5, volume=0.0))
    _, _, params = engine.calls[0]
    assert params.length_scale == pytest.approx(0.3)
    assert params.pitch_cents == 300


def test_status_reports_engines_and_config(tmp_path):
    daemon = Daemon(
        EngineChain([FakeEngine("first"), FakeEngine("second")]),
        make_config(idle_timeout=42, tmp_path=tmp_path),
    )
    out = roundtrip(daemon, encode_status_request())
    payload = json.loads(out.decode())
    assert payload["engines"] == ["first", "second"]
    assert payload["idle_timeout"] == 42


def test_idle_timeout_comes_from_config_not_a_literal(tmp_path):
    # Regression test named in the spec.
    daemon = Daemon(EngineChain([FakeEngine()]), make_config(idle_timeout=7, tmp_path=tmp_path))
    assert daemon.idle_timeout == 7


def test_every_engine_failing_closes_without_a_header(tmp_path):
    daemon = Daemon(
        EngineChain([FakeEngine("a", fails=True)]),
        make_config(tmp_path=tmp_path),
    )
    out = roundtrip(daemon, encode_request("hi", None, 0, 0, 0))
    assert out == b"", "no header means the client knows nothing was spoken"


def test_malformed_request_closes_without_a_header(tmp_path):
    daemon = Daemon(EngineChain([FakeEngine()]), make_config(tmp_path=tmp_path))
    assert roundtrip(daemon, b"garbage\n") == b""
```

- [ ] **Step 2: Run to verify they fail**

Run: `pytest tests/test_daemon.py -q`
Expected: FAIL, `ModuleNotFoundError: No module named 'speechd_neural.daemon'`

- [ ] **Step 3: Implement**

```python
# src/speechd_neural/daemon.py
"""Socket server. Owns lifetime and eviction policy; knows nothing about ONNX."""

from __future__ import annotations

import json
import logging
import os
import select
import socket
import sys
import time
from pathlib import Path

from speechd_neural.chain import ChainExhausted, EngineChain
from speechd_neural.config import Config, load_config
from speechd_neural.params import map_params
from speechd_neural.protocol import (
    ProtocolError, decode_request, encode_header,
)

log = logging.getLogger(__name__)

SOCKET_NAME = "speechd-neural.sock"


def socket_path() -> Path:
    runtime = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
    return Path(runtime) / SOCKET_NAME


def status_payload(chain: EngineChain, cfg: Config, started_at: float) -> dict:
    engines = [e.name for e in chain.engines]
    piper = chain.by_name("piper")
    return {
        "engines": engines,
        "device": getattr(piper, "device", None),
        "models": piper.loaded_models() if hasattr(piper, "loaded_models") else [],
        "idle_timeout": cfg.core.idle_timeout,
        "model_evict": cfg.core.model_evict,
        "uptime": round(time.monotonic() - started_at, 1),
    }


class Daemon:
    def __init__(self, chain: EngineChain, cfg: Config):
        self._chain = chain
        self._cfg = cfg
        self._started_at = time.monotonic()

    @property
    def idle_timeout(self) -> int:
        return self._cfg.core.idle_timeout

    def handle(self, conn: socket.socket) -> None:
        try:
            data = b""
            while b"\n" not in data:
                chunk = conn.recv(4096)
                if not chunk:
                    break
                data += chunk
            if not data.strip():
                return

            request = decode_request(data.split(b"\n", 1)[0])

            if request["op"] == "status":
                payload = status_payload(self._chain, self._cfg, self._started_at)
                conn.sendall(json.dumps(payload).encode())
                return

            params = map_params(
                float(request.get("rate", 0.0)),
                float(request.get("pitch", 0.0)),
                float(request.get("volume", 0.0)),
                base_length_scale=self._cfg.piper.length_scale,
                base_volume=self._cfg.sink.base_volume,
            )
            name, (sample_rate, chunks) = self._chain.synthesize(
                request["text"], request.get("voice"), params
            )
            log.info("speaking via %s at %d Hz", name, sample_rate)

            conn.sendall(encode_header(sample_rate))
            for chunk in chunks:
                conn.sendall(chunk)

        except (ProtocolError, ChainExhausted) as exc:
            # Close without a header. The client treats that as "nothing spoken"
            # and exits non-zero, so speech-dispatcher sees the failure.
            log.error("[ERROR] %s", exc)
        except (BrokenPipeError, ConnectionResetError):
            log.info("client went away mid-stream")
        except Exception:
            log.exception("[ERROR] unhandled error serving a client")
        finally:
            try:
                conn.close()
            except OSError:
                pass

    def serve(self, server: socket.socket) -> None:
        log.info("daemon ready (idle timeout %ds)", self.idle_timeout)
        while True:
            readable, _, _ = select.select([server], [], [], self.idle_timeout)
            if not readable:
                log.info("idle for %ds, exiting", self.idle_timeout)
                return
            conn, _ = server.accept()
            conn.setblocking(True)
            self.handle(conn)
            for engine in self._chain.engines:
                if hasattr(engine, "evict"):
                    engine.evict(older_than=self._cfg.core.model_evict)


def _server_socket() -> socket.socket:
    """Prefer systemd socket activation; otherwise bind our own."""
    try:
        from systemd.daemon import listen_fds
        fds = listen_fds()
        if fds:
            log.info("using systemd socket activation")
            return socket.fromfd(fds[0], socket.AF_UNIX, socket.SOCK_STREAM)
    except ImportError:
        pass

    path = socket_path()
    path.unlink(missing_ok=True)
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.bind(str(path))
    sock.listen(4)
    log.info("listening on %s", path)
    return sock


def build_chain(cfg: Config) -> EngineChain:
    from speechd_neural.engines.espeak import EspeakEngine
    from speechd_neural.engines.piper import PiperEngine

    registry = {"piper": lambda: PiperEngine(cfg.piper), "espeak": EspeakEngine}
    names = [cfg.engine.default, *cfg.engine.fallback]
    engines = [registry[n]() for n in names if n in registry]
    return EngineChain(engines)


def main() -> int:
    from speechd_neural.cuda import ensure_cuda_env

    logging.basicConfig(
        stream=sys.stderr, level=logging.INFO,
        format="%(levelname)s %(name)s: %(message)s",
    )
    # Must happen before onnxruntime is imported anywhere.
    ensure_cuda_env(sys.argv, os.environ)

    cfg = load_config()
    daemon = Daemon(build_chain(cfg), cfg)
    server = _server_socket()
    try:
        daemon.serve(server)
    finally:
        server.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 4: Run to verify they pass**

Run: `pytest tests/test_daemon.py -q`
Expected: 6 passed.

- [ ] **Step 5: Commit**

```bash
git add src/speechd_neural/daemon.py tests/test_daemon.py
git commit -m "feat(daemon): socket server with config-driven lifetime"
```

---

### Task 12: Client and front-end

**Files:**
- Create: `src/speechd_neural/client.py`, `src/speechd_neural/run.py`
- Test: `tests/test_run.py`

**Interfaces:**
- Consumes: protocol (Task 10), sink (Task 6), chain (Task 9), config (Task 2), params (Task 3).
- Produces:
  - `speak_via_daemon(text, voice, rate, pitch, volume, *, sink, socket_path=None, timeout=2.0) -> bool`
  - `speak_in_process(text, voice, rate, pitch, volume, *, sink, cfg) -> bool`
  - `run.main(environ=None, sink=None) -> int` — exit 0 only when audio was produced

This closes the "duplicated pipeline" defect: the daemon-unavailable path reuses `EngineChain` and the same sink in-process rather than reimplementing synthesis.

- [ ] **Step 1: Write the failing tests**

```python
# tests/test_run.py
import pytest
from pathlib import Path
from speechd_neural import run
from speechd_neural.sink import FileSink


def env(**overrides):
    base = {"DATA": "hello", "VOICE": "", "RATE": "0", "PITCH": "0", "VOLUME": "0"}
    base.update(overrides)
    return base


def test_exits_non_zero_when_nothing_was_spoken(tmp_path, monkeypatch):
    # Regression test named in the spec: the old runner exited 0 regardless.
    monkeypatch.setattr(run, "speak_via_daemon", lambda *a, **k: False)
    monkeypatch.setattr(run, "speak_in_process", lambda *a, **k: False)
    assert run.main(env(), sink=FileSink(tmp_path / "out.raw")) != 0


def test_exits_zero_when_the_daemon_speaks(tmp_path, monkeypatch):
    monkeypatch.setattr(run, "speak_via_daemon", lambda *a, **k: True)
    assert run.main(env(), sink=FileSink(tmp_path / "out.raw")) == 0


def test_falls_back_in_process_when_the_daemon_is_absent(tmp_path, monkeypatch):
    calls = []
    monkeypatch.setattr(run, "speak_via_daemon", lambda *a, **k: False)
    monkeypatch.setattr(run, "speak_in_process",
                        lambda *a, **k: (calls.append(1), True)[1])
    assert run.main(env(), sink=FileSink(tmp_path / "out.raw")) == 0
    assert len(calls) == 1


def test_empty_text_is_a_no_op_success(tmp_path, monkeypatch):
    monkeypatch.setattr(run, "speak_via_daemon",
                        lambda *a, **k: pytest.fail("must not be called"))
    assert run.main(env(DATA=""), sink=FileSink(tmp_path / "out.raw")) == 0


def test_unset_parameters_default_to_neutral(tmp_path, monkeypatch):
    seen = {}

    def capture(text, voice, rate, pitch, volume, **k):
        seen.update(rate=rate, pitch=pitch, volume=volume)
        return True

    monkeypatch.setattr(run, "speak_via_daemon", capture)
    run.main({"DATA": "hi"}, sink=FileSink(tmp_path / "out.raw"))
    assert seen == {"rate": 0.0, "pitch": 0.0, "volume": 0.0}


def test_non_numeric_parameters_fall_back_to_neutral(tmp_path, monkeypatch):
    seen = {}

    def capture(text, voice, rate, pitch, volume, **k):
        seen.update(rate=rate)
        return True

    monkeypatch.setattr(run, "speak_via_daemon", capture)
    run.main(env(RATE="not-a-number"), sink=FileSink(tmp_path / "out.raw"))
    assert seen["rate"] == 0.0
```

- [ ] **Step 2: Run to verify they fail**

Run: `pytest tests/test_run.py -q`
Expected: FAIL, `ModuleNotFoundError: No module named 'speechd_neural.run'`

- [ ] **Step 3: Implement the client**

```python
# src/speechd_neural/client.py
"""Talks to the daemon and drives the sink.

Playback happens here rather than in the daemon so that this process blocks
for exactly as long as audio plays. sd_generic uses our exit as the signal
that the message is finished, which is what keeps speech-dispatcher's
queueing correct.
"""

from __future__ import annotations

import logging
import socket
from pathlib import Path
from typing import Iterator

from speechd_neural.protocol import (
    HEADER_BYTES, ProtocolError, decode_header, encode_request,
)

log = logging.getLogger(__name__)


def _stream(sock: socket.socket) -> Iterator[bytes]:
    while True:
        data = sock.recv(65536)
        if not data:
            return
        yield data


def speak_via_daemon(
    text: str,
    voice: str | None,
    rate: float,
    pitch: float,
    volume: float,
    *,
    sink,
    socket_path: Path | None = None,
    timeout: float = 2.0,
    base_volume: int = 40000,
) -> bool:
    """Returns True when audio was played, False when the daemon is unusable."""
    from speechd_neural.daemon import socket_path as default_socket_path
    from speechd_neural.params import map_params

    path = socket_path or default_socket_path()
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(timeout)
    try:
        sock.connect(str(path))
    except OSError as exc:
        log.info("daemon unavailable (%s), falling back in process", exc)
        sock.close()
        return False

    try:
        sock.sendall(encode_request(text, voice, rate, pitch, volume))

        header = b""
        while len(header) < HEADER_BYTES:
            chunk = sock.recv(HEADER_BYTES - len(header))
            if not chunk:
                log.error("[ERROR] daemon closed without speaking")
                return False
            header += chunk

        sample_rate = decode_header(header)
        sock.settimeout(None)

        # Recomputed here only for the sink's volume and pitch. The daemon
        # already applied the rate during synthesis, so base_length_scale is
        # 1.0: the length_scale this produces is deliberately unused.
        params = map_params(rate, pitch, volume,
                            base_length_scale=1.0, base_volume=base_volume)
        sink.play(sample_rate, _stream(sock), params)
        return True
    except (ProtocolError, OSError) as exc:
        log.error("[ERROR] daemon exchange failed: %s", exc)
        return False
    finally:
        sock.close()
```

- [ ] **Step 4: Implement the front-end**

```python
# src/speechd_neural/run.py
"""sd_generic front-end.

speech-dispatcher invokes this with VOICE, DATA, RATE, PITCH and VOLUME in the
environment. Our exit status is the contract: zero means the message was
spoken, non-zero means it was not.
"""

from __future__ import annotations

import logging
import os
import sys

from speechd_neural.client import speak_via_daemon

log = logging.getLogger(__name__)


def _number(environ: dict, key: str) -> float:
    try:
        return float(environ.get(key) or 0.0)
    except (TypeError, ValueError):
        log.warning("[WARN] %s=%r is not a number, using 0", key, environ.get(key))
        return 0.0


def speak_in_process(text, voice, rate, pitch, volume, *, sink, cfg=None) -> bool:
    """Fallback when the daemon cannot be reached.

    Reuses the same chain and sink as the daemon, so there is exactly one
    synthesis pipeline in the codebase.
    """
    from speechd_neural.chain import ChainExhausted
    from speechd_neural.config import load_config
    from speechd_neural.daemon import build_chain
    from speechd_neural.params import map_params

    cfg = cfg or load_config()
    params = map_params(rate, pitch, volume,
                        base_length_scale=cfg.piper.length_scale,
                        base_volume=cfg.sink.base_volume)
    try:
        _, (sample_rate, chunks) = build_chain(cfg).synthesize(text, voice, params)
        sink.play(sample_rate, chunks, params)
        return True
    except ChainExhausted as exc:
        log.error("[ERROR] every engine failed: %s", exc)
        return False


def main(environ: dict | None = None, sink=None) -> int:
    logging.basicConfig(
        stream=sys.stderr, level=logging.INFO,
        format="%(levelname)s speechd-neural: %(message)s",
    )
    environ = os.environ if environ is None else environ

    text = environ.get("DATA") or ""
    if not text.strip():
        return 0                      # nothing to say is not a failure

    if sink is None:
        from speechd_neural.sink import PaplaySink
        sink = PaplaySink()

    voice = environ.get("VOICE") or None
    rate = _number(environ, "RATE")
    pitch = _number(environ, "PITCH")
    volume = _number(environ, "VOLUME")

    from speechd_neural.config import load_config
    cfg = load_config()

    if speak_via_daemon(text, voice, rate, pitch, volume, sink=sink,
                        base_volume=cfg.sink.base_volume):
        return 0
    if speak_in_process(text, voice, rate, pitch, volume, sink=sink, cfg=cfg):
        return 0

    log.error("[ERROR] nothing was spoken")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 5: Run to verify they pass**

Run: `pytest tests/test_run.py -q`
Expected: 6 passed. Then run the whole suite: `pytest -q`.

- [ ] **Step 6: Commit**

```bash
git add src/speechd_neural/client.py src/speechd_neural/run.py tests/test_run.py
git commit -m "feat(run): sd_generic front-end with an in-process fallback"
```

---

### Task 13: CLI

**Files:**
- Create: `src/speechd_neural/cli.py`
- Test: `tests/test_cli.py`

**Interfaces:**
- Consumes: everything above.
- Produces: `main(argv: list[str] | None = None) -> int` with subcommands `warm`, `status`, `say`, `test`, `engines`.

`test` is the health-check the spec calls for: every engine against every device, printed as an `[OK]`/`[FAIL]` table.

- [ ] **Step 1: Write the failing tests**

```python
# tests/test_cli.py
import pytest
from speechd_neural import cli


def test_engines_lists_configured_engines(capsys, monkeypatch):
    monkeypatch.setattr(cli, "_chain_names", lambda cfg: ["piper", "espeak"])
    assert cli.main(["engines"]) == 0
    assert "piper" in capsys.readouterr().out


def test_unknown_subcommand_exits_non_zero(capsys):
    with pytest.raises(SystemExit) as e:
        cli.main(["nonsense"])
    assert e.value.code != 0


def test_no_subcommand_prints_usage(capsys):
    assert cli.main([]) != 0


def test_say_returns_non_zero_when_nothing_spoke(monkeypatch):
    monkeypatch.setattr(cli, "speak_via_daemon", lambda *a, **k: False)
    monkeypatch.setattr(cli, "speak_in_process", lambda *a, **k: False)
    assert cli.main(["say", "hello"]) != 0


def test_test_reports_ok_and_fail_per_engine(capsys, monkeypatch):
    monkeypatch.setattr(cli, "_probe_engine",
                        lambda name, cfg: (name == "espeak", "" if name == "espeak" else "no model"))
    monkeypatch.setattr(cli, "_chain_names", lambda cfg: ["piper", "espeak"])
    assert cli.main(["test"]) != 0        # a failing engine means a failing run
    out = capsys.readouterr().out
    assert "[OK]" in out and "[FAIL]" in out
    assert "no model" in out
```

- [ ] **Step 2: Run to verify they fail**

Run: `pytest tests/test_cli.py -q`
Expected: FAIL, `ModuleNotFoundError: No module named 'speechd_neural.cli'`

- [ ] **Step 3: Implement**

```python
# src/speechd_neural/cli.py
"""speechd-neural CLI: warm, status, say, test, engines."""

from __future__ import annotations

import argparse
import json
import socket
import sys

from speechd_neural.client import speak_via_daemon
from speechd_neural.config import load_config
from speechd_neural.protocol import encode_status_request
from speechd_neural.run import speak_in_process


def _chain_names(cfg) -> list[str]:
    return [cfg.engine.default, *cfg.engine.fallback]


def _probe_engine(name: str, cfg) -> tuple[bool, str]:
    """Try one engine end to end without playing audio."""
    from speechd_neural.daemon import build_chain
    from speechd_neural.params import Params

    engine = build_chain(cfg).by_name(name)
    if engine is None:
        return False, "not configured"
    try:
        if not engine.available():
            return False, "unavailable (missing binary or model)"
        voice = engine.resolve(None)
        _, chunks = engine.synthesize("test", voice, Params(0.6, 40000, 0))
        return (True, "") if b"".join(chunks) else (False, "produced no audio")
    except Exception as exc:
        return False, str(exc)


def _cmd_engines(args, cfg) -> int:
    for name in _chain_names(cfg):
        print(name)
    return 0


def _cmd_test(args, cfg) -> int:
    failures = 0
    for name in _chain_names(cfg):
        ok, detail = _probe_engine(name, cfg)
        if ok:
            print(f"[OK]   {name}")
        else:
            failures += 1
            print(f"[FAIL] {name}: {detail}")
    return 1 if failures else 0


def _cmd_status(args, cfg) -> int:
    from speechd_neural.daemon import socket_path

    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(2)
    try:
        sock.connect(str(socket_path()))
        sock.sendall(encode_status_request())
        payload = b""
        while True:
            data = sock.recv(4096)
            if not data:
                break
            payload += data
    except OSError:
        print("[WARN] daemon not running (it starts on the next utterance)")
        return 1
    finally:
        sock.close()

    for key, value in json.loads(payload.decode()).items():
        print(f"{key}: {value}")
    return 0


def _cmd_warm(args, cfg) -> int:
    from speechd_neural.sink import FileSink
    import tempfile

    with tempfile.NamedTemporaryFile(suffix=".raw") as tmp:
        ok = speak_via_daemon(" ", None, 0, 0, 0, sink=FileSink(tmp.name))
    print("[OK] daemon warm" if ok else "[FAIL] could not warm the daemon")
    return 0 if ok else 1


def _cmd_say(args, cfg) -> int:
    from speechd_neural.sink import FileSink, PaplaySink

    sink = FileSink(args.to) if args.to else PaplaySink()
    text = " ".join(args.text)
    if speak_via_daemon(text, args.voice, 0, 0, 0, sink=sink):
        return 0
    if speak_in_process(text, args.voice, 0, 0, 0, sink=sink, cfg=cfg):
        return 0
    print("[ERROR] nothing was spoken", file=sys.stderr)
    return 1


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="speechd-neural")
    sub = parser.add_subparsers(dest="command")

    sub.add_parser("engines", help="list configured engines in fallback order")
    sub.add_parser("test", help="probe every engine and print an OK/FAIL table")
    sub.add_parser("status", help="ask the running daemon what it is doing")
    sub.add_parser("warm", help="start the daemon and preload the model")

    say = sub.add_parser("say", help="speak some text")
    say.add_argument("text", nargs="+")
    say.add_argument("--voice", default=None)
    say.add_argument("--to", default=None, help="write raw PCM here instead of playing")

    args = parser.parse_args(argv)
    if not args.command:
        parser.print_usage(sys.stderr)
        return 2

    cfg = load_config()
    handlers = {
        "engines": _cmd_engines, "test": _cmd_test, "status": _cmd_status,
        "warm": _cmd_warm, "say": _cmd_say,
    }
    return handlers[args.command](args, cfg)


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 4: Run to verify they pass**

Run: `pytest tests/test_cli.py -q`
Expected: 5 passed.

- [ ] **Step 5: Commit**

```bash
git add src/speechd_neural/cli.py tests/test_cli.py
git commit -m "feat(cli): warm, status, say, test and engines subcommands"
```

---

### Task 14: Install script, units and module config

**Files:**
- Create: `install.sh`, `conf/speechd-neural.conf`, `conf/speechd-neural.service.in`, `conf/speechd-neural.socket.in`
- Test: `tests/test_install.sh` (a shell check run by hand)

**Interfaces:**
- Consumes: the package.
- Produces: an installed tree under `$HOME` and a `speechd-neural` speech-dispatcher module. No file outside `$HOME` is touched.

The `.in` suffix marks templates: `@BIN@` and `@LIBEXEC@` are substituted at install time, so no path is ever committed.

- [ ] **Step 1: Write the module config**

`AddVoice` lines carry over from the existing setup so voices keep their names.

```
# conf/speechd-neural.conf
Debug 0
GenericExecuteSynth "VOICE=\"$VOICE\" DATA=\"$DATA\" RATE=\"$RATE\" PITCH=\"$PITCH\" VOLUME=\"$VOLUME\" exec @LIBEXEC@/run"

AddVoice "en"    "FEMALE1"      "en_GB-aru-medium.onnx"
AddVoice "en"    "FEMALE2"      "en_GB-southern_english_female-low.onnx"
AddVoice "en"    "FEMALE3"      "en_GB-cori-high.onnx"
AddVoice "en"    "FEMALE4"      "en_GB-semaine-medium.onnx:0"
AddVoice "en"    "MALE1"        "en_GB-semaine-medium.onnx:2"
AddVoice "en"    "MALE2"        "en_GB-semaine-medium.onnx:1"
AddVoice "en"    "CHILD_FEMALE" "en_GB-semaine-medium.onnx:3"
AddVoice "en-US" "FEMALE1"      "en_US-lessac-medium.onnx"
DefaultVoice "en_GB-cori-high.onnx"

GenericRateAdd 0
GenericRateMultiply 1
GenericPitchAdd 0
GenericPitchMultiply 1
GenericVolumeAdd 0
GenericVolumeMultiply 1
GenericDelimiters "|"
GenericMaxChunkLength 99999
```

- [ ] **Step 2: Write the unit templates**

Note the absence of any `LD_LIBRARY_PATH` or python version: `cuda.py` handles that at runtime.

```ini
# conf/speechd-neural.service.in
[Unit]
Description=speechd-neural TTS daemon
Requires=speechd-neural.socket

[Service]
Type=exec
ExecStart=@PYTHON@ -m speechd_neural.daemon
Environment="PYTHONPATH=@LIBROOT@"
Restart=no
TimeoutStopSec=5
Slice=session.slice

[Install]
WantedBy=default.target
```

```ini
# conf/speechd-neural.socket.in
[Unit]
Description=speechd-neural TTS daemon socket

[Socket]
ListenStream=%t/speechd-neural.sock
SocketMode=0600

[Install]
WantedBy=sockets.target
```

- [ ] **Step 3: Write `install.sh`**

```bash
#!/usr/bin/env bash
# Install speechd-neural into the current user's XDG directories.
# Nothing outside $HOME is touched. Re-running is safe.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

XDG_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
LIBEXEC="$HOME/.local/libexec/speechd-neural"
BIN="$HOME/.local/bin"
UNITS="$XDG_CONFIG/systemd/user"
SPEECHD_MODULES="$XDG_CONFIG/speech-dispatcher/modules"

PYTHON="$(command -v python3)"

mkdir -p "$LIBEXEC" "$BIN" "$UNITS" "$SPEECHD_MODULES" "$XDG_CONFIG/speechd-neural"

# The package is used from the repo, so development needs no reinstall.
ln -sfn "$REPO/src/speechd_neural" "$LIBEXEC/speechd_neural"

cat > "$LIBEXEC/run" <<EOF
#!/usr/bin/env bash
exec "$PYTHON" -c 'import sys; sys.path.insert(0, "$LIBEXEC"); from speechd_neural.run import main; sys.exit(main())'
EOF
chmod +x "$LIBEXEC/run"

cat > "$BIN/speechd-neural" <<EOF
#!/usr/bin/env bash
exec "$PYTHON" -c 'import sys; sys.path.insert(0, "$LIBEXEC"); from speechd_neural.cli import main; sys.exit(main())' "\$@"
EOF
chmod +x "$BIN/speechd-neural"

sed -e "s|@PYTHON@|$PYTHON|g" -e "s|@LIBROOT@|$LIBEXEC|g" \
    "$REPO/conf/speechd-neural.service.in" > "$UNITS/speechd-neural.service"
cp "$REPO/conf/speechd-neural.socket.in" "$UNITS/speechd-neural.socket"

sed -e "s|@LIBEXEC@|$LIBEXEC|g" \
    "$REPO/conf/speechd-neural.conf" > "$SPEECHD_MODULES/speechd-neural.conf"

systemctl --user daemon-reload
systemctl --user enable --now speechd-neural.socket

echo "[OK] installed"
echo "Next: add this line to $XDG_CONFIG/speech-dispatcher/speechd.conf"
echo '  AddModule "speechd-neural" "sd_generic" "speechd-neural.conf"'
echo "Then test without switching over:  spd-say -o speechd-neural 'hello'"
```

- [ ] **Step 4: Run the installer and verify placement**

```bash
cd ~/git/github.com/cadrianmae/speechd-neural
./install.sh
test -x ~/.local/libexec/speechd-neural/run && echo "[OK] front-end"
test -x ~/.local/bin/speechd-neural && echo "[OK] cli"
grep -q python3 ~/.config/systemd/user/speechd-neural.service && echo "[OK] unit templated"
! grep -qE 'python3\.[0-9]+' ~/.config/systemd/user/speechd-neural.service \
  && echo "[OK] no python version pinned"
speechd-neural engines
speechd-neural test
```

Expected: every `[OK]` line prints, `engines` lists `piper` and `espeak`, and `test` shows `[OK] espeak` at minimum.

- [ ] **Step 5: Commit**

```bash
git add install.sh conf/
git commit -m "feat(install): templated install into XDG paths"
```

---

### Task 15: Cutover and verification

**Files:**
- Modify: `~/.config/speech-dispatcher/speechd.conf`
- Create: `docs/install.md`

**Interfaces:**
- Consumes: a completed install from Task 14.
- Produces: a verified working module, still with the old one available for rollback.

- [ ] **Step 1: Register the module without switching the default**

Add to `~/.config/speech-dispatcher/speechd.conf`, leaving `DefaultModule` alone:

```
AddModule "speechd-neural" "sd_generic" "speechd-neural.conf"
```

Then restart speech-dispatcher so it re-reads its config:

```bash
systemctl --user restart speech-dispatcherd.service 2>/dev/null || pkill -u "$USER" speech-dispatcher || true
```

- [ ] **Step 2: Verify the new module side by side with the old one**

```bash
spd-say -o speechd-neural -w "new module, sentence one, two, three"
spd-say -o piper-generic  -w "old module, sentence one, two, three"
```

Expected: both speak, and they sound the same. If the new one is noticeably faster or slower, the `length_scale` mapping is wrong.

- [ ] **Step 3: Verify the measured defects are actually fixed**

```bash
# Warm latency should match the old warm figure of about 0.7s
speechd-neural warm
time spd-say -o speechd-neural -w "warm timing check"

# Cancel must still clean up
spd-say -o speechd-neural "a deliberately long sentence that will be interrupted" &
sleep 2; spd-say -C; sleep 1
pgrep -c paplay || echo "[OK] no orphaned playback"

# Failing loudly: point at a non-existent model and confirm espeak takes over
speechd-neural say --voice does-not-exist.onnx "fallback check"
echo "exit=$?  (expect 0, spoken by espeak, with a degradation notification)"

# The journal replaces the old /tmp logs
journalctl --user -u speechd-neural -n 20 --no-pager
```

- [ ] **Step 4: Cut over**

Change `DefaultModule` in `speechd.conf` to `speechd-neural`, restart speech-dispatcher, and confirm a bare `spd-say "hello"` uses the new module.

Rollback at any point is reverting that one line. The old module and its units are left untouched, and the two sockets have different paths so both can coexist.

- [ ] **Step 5: Write `docs/install.md`**

````markdown
# Installing speechd-neural

Requires python 3.11+, speech-dispatcher, and `paplay`. `sox` is optional and
only used for pitch shifting. At least one engine must be usable: `espeak-ng`
for the fallback, and `piper-tts` plus a voice model for neural synthesis.

## Install

```bash
git clone <repo-url> speechd-neural
cd speechd-neural
./install.sh
```

This writes only into `$HOME`: the package is symlinked into
`~/.local/libexec/speechd-neural/`, the CLI into `~/.local/bin/`, systemd user
units into `~/.config/systemd/user/`, and the module config into
`~/.config/speech-dispatcher/modules/`.

## Register the module

Add to `~/.config/speech-dispatcher/speechd.conf`:

```
AddModule "speechd-neural" "sd_generic" "speechd-neural.conf"
```

Restart speech-dispatcher, then check it without changing your default:

```bash
speechd-neural test
spd-say -o speechd-neural -w "hello"
```

## Switch over

Set `DefaultModule speechd-neural` in `speechd.conf` and restart
speech-dispatcher.

## Roll back

Revert `DefaultModule` to its previous value and restart speech-dispatcher.
Nothing else needs undoing.

## Health checks

```bash
speechd-neural status                        # daemon, device, cached models
speechd-neural engines                       # fallback order
journalctl --user -u speechd-neural -f       # logs
```

## Uninstall

Stage 1 ships no uninstaller. Remove
`~/.local/libexec/speechd-neural/`, `~/.local/bin/speechd-neural`, the two
`speechd-neural.*` unit files, and the module config by hand, then drop the
`AddModule` line.
````

- [ ] **Step 6: Commit**

```bash
git add docs/install.md
git commit -m "docs: install, cutover and rollback"
```

---

## Post-stage-1 checklist

Not tasks, but the soak conditions from the spec's migration section. Only after these hold should the old `~/.config/speech-dispatcher/piper/` tree, the `piper-daemon` units, and the `~/.cache/piper-*` files be deleted:

- [ ] A week of daily use with no unexplained silence
- [ ] At least one observed degradation notification that was accurate
- [ ] `speechd-neural test` passing from a cold boot

Deferred to stage 2 by decision: packaging metadata, an uninstaller, CI, published documentation, and the licence choice. Project B (notification TTS) gets its own spec on top of this.
