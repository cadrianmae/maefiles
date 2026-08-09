# notify-tts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A daemon that speaks desktop notifications aloud while a global toggle is on, without ever interfering with the notifications themselves.

**Architecture:** Four layers with hard boundaries — a DBus monitor that only observes, a pure filter holding every rule, a bounded single-worker queue, and a speaker that shells out to `spd-say`. The bus, the clock and the audio device are all injected, so almost the entire suite runs without any of them.

**Tech Stack:** python 3.11+ (stdlib `tomllib`), PyGObject (`Gio`/`GLib`) for DBus, pytest, `spd-say` from speech-dispatcher, systemd user units.

**Design doc:** `~/docs/specs/2026-08-09-notify-tts-design.md` (moved into the repo in Task 1).

## Verified before planning

The riskiest assumption was checked against the live session bus on 2026-08-09, not assumed. A private `Gio.DBusConnection` accepted `BecomeMonitor` and captured a real notification:

```
[OK] BecomeMonitor accepted
[OK] captured: app='SpikeApp' summary='Spike summary line' replaces_id=0 hints=['sender-pid', 'urgency']
```

The working spike code appears verbatim in Task 9. Note the observed hint set for a plain `notify-send`: `sender-pid` and `urgency` only. Synchronous/OSD hints appear only on notifications that carry them, so the OSD rule cannot be verified from a synthetic notification and is tested at the unit level instead.

## Global Constraints

- Python 3.11 or later. `tomllib` is stdlib from 3.11; no TOML dependency may be added.
- PyGObject is the only non-stdlib dependency, and it is already present system-wide. Do not add others.
- No python version hardcoded anywhere — not in code, not in config, not in systemd units.
- No absolute path to a particular user's home in code or config defaults. Use `Path.home()` or XDG lookups.
- The config file is optional. Every setting has a working default.
- systemd units are templated at install time, never shipped with paths baked in.
- Nothing is written outside `$HOME`.
- **The daemon must never interfere with notification delivery.** It observes the bus; it never sits in the path. A failure to speak must never prevent a notification being displayed.
- Logs go to stderr for the journal. No log files under `/tmp`.
- Prose in British English. No emoji or non-keyboard characters in code, comments, or output — use `[OK]`, `[WARN]`, `[ERROR]` tags.
- Repo: `~/git/github.com/cadrianmae/notify-tts`. Package: `src/notify_tts/`.
- Run tests as `PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 pytest -q`. The global `pytest` on this machine is broken by an unrelated stray `langsmith` plugin missing `requests_toolbelt`. That is not a bug in this project and must not be "fixed" here.

## File Structure

```
~/git/github.com/cadrianmae/notify-tts/
    README.md
    .gitignore
    pyproject.toml
    install.sh
    uninstall.sh
    docs/design.md                the spec, moved here
    conf/notify-tts.service.in    systemd unit template
    src/notify_tts/
        __init__.py
        model.py                  the Notification record
        config.py                 TOML load, defaults
        state.py                  the on/off toggle
        filters.py                every rule, pure
        formatting.py             app + summary, truncation
        speaker.py                spd-say invocation
        queue.py                  bounded queue, single worker
        monitor.py                DBus, observation only
        daemon.py                 wiring, counters, main
        cli.py                    on | off | toggle | status | test
    tests/
        fakes.py                  FakeSpeaker, FakeClock
        test_model.py
        test_config.py
        test_state.py
        test_filters.py
        test_formatting.py
        test_speaker.py
        test_queue.py
        test_monitor.py
        test_daemon.py
        test_cli.py
        test_install.sh
```

---

### Task 1: Repo scaffold

**Files:**
- Create: `README.md`, `.gitignore`, `pyproject.toml`, `src/notify_tts/__init__.py`, `tests/test_smoke.py`
- Move: `~/docs/specs/2026-08-09-notify-tts-design.md` -> `docs/design.md`

**Interfaces:**
- Consumes: nothing.
- Produces: an importable `notify_tts` package and a working `pytest` invocation. Every later task assumes tests run from the repo root with `src/` and `tests/` on the import path.

- [ ] **Step 1: Create the repo and skeleton**

```bash
mkdir -p ~/git/github.com/cadrianmae/notify-tts
cd ~/git/github.com/cadrianmae/notify-tts
git init -b main
mkdir -p src/notify_tts tests docs conf
touch src/notify_tts/__init__.py
```

- [ ] **Step 2: Write `pyproject.toml`**

`pythonpath` includes `tests` from the start, so `fakes` imports by bare name.

```toml
[project]
name = "notify-tts"
version = "0.1.0"
description = "Speak desktop notifications aloud, on a global toggle"
requires-python = ">=3.11"

[tool.pytest.ini_options]
pythonpath = ["src", "tests"]
testpaths = ["tests"]
markers = [
    "bus: requires a real session bus or audio device",
]
```

- [ ] **Step 3: Write `.gitignore`**

```
__pycache__/
*.py[cod]
.pytest_cache/
*.egg-info/
.venv/
.superpowers/
```

- [ ] **Step 4: Write `README.md`**

```markdown
# notify-tts

Speaks desktop notifications aloud while a global toggle is on.

A consumer of speech-dispatcher rather than a synthesiser: voices, engines and
fallback behaviour come from whichever output module speech-dispatcher is
configured with.

Status: in development.

See `docs/design.md` for the design and the measurements behind it.
```

- [ ] **Step 5: Move the design doc into the repo**

```bash
cd ~
yadm rm --cached docs/specs/2026-08-09-notify-tts-design.md
mv docs/specs/2026-08-09-notify-tts-design.md \
   ~/git/github.com/cadrianmae/notify-tts/docs/design.md
printf '%s\n' \
  '# notify-tts design' '' \
  'Moved into the project repository:' \
  '`~/git/github.com/cadrianmae/notify-tts/docs/design.md`' \
  > docs/specs/2026-08-09-notify-tts-design.md
yadm add docs/specs/2026-08-09-notify-tts-design.md
yadm commit -m "docs(specs): move notify-tts design into its repo"
```

- [ ] **Step 6: Write the smoke test**

```python
# tests/test_smoke.py
def test_package_imports():
    import notify_tts
    assert notify_tts is not None
```

- [ ] **Step 7: Run it**

Run: `cd ~/git/github.com/cadrianmae/notify-tts && PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 pytest -q`
Expected: 1 passed.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "chore: scaffold repository"
```

---

### Task 2: The Notification record

**Files:**
- Create: `src/notify_tts/model.py`
- Test: `tests/test_model.py`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `Notification(app: str, summary: str, body: str, replaces_id: int, hints: frozenset[str], urgency: int)` — frozen dataclass
  - `Notification.from_notify_args(args: tuple) -> Notification` — builds one from an unpacked DBus `Notify` body
  - `OSD_HINTS: frozenset[str]`

Hints are reduced to a frozenset of their **keys** at the boundary. The filter only ever asks whether a hint is present, never its value, so carrying the full variant dictionary deeper would be needless coupling to DBus types.

- [ ] **Step 1: Write the failing tests**

```python
# tests/test_model.py
import pytest
from notify_tts.model import Notification, OSD_HINTS

# The real signature is (susssasa{sv}i): app, replaces_id, icon, summary,
# body, actions, hints, expire_timeout.
def args(app="App", replaces_id=0, summary="Summary", body="Body",
         hints=None, urgency=1):
    h = {"urgency": urgency, "sender-pid": 1234}
    h.update(hints or {})
    return (app, replaces_id, "icon", summary, body, [], h, -1)


def test_builds_from_notify_args():
    n = Notification.from_notify_args(args(app="Proton Mail", summary="New message"))
    assert n.app == "Proton Mail"
    assert n.summary == "New message"
    assert n.body == "Body"
    assert n.replaces_id == 0


def test_hints_reduced_to_keys():
    n = Notification.from_notify_args(args(hints={"x-canonical-private-synchronous": "volume"}))
    assert "x-canonical-private-synchronous" in n.hints
    assert isinstance(n.hints, frozenset)


def test_urgency_extracted_from_hints():
    assert Notification.from_notify_args(args(urgency=2)).urgency == 2


def test_missing_urgency_defaults_to_normal():
    a = list(args())
    a[6] = {"sender-pid": 1}
    assert Notification.from_notify_args(tuple(a)).urgency == 1


def test_replaces_id_preserved():
    assert Notification.from_notify_args(args(replaces_id=42)).replaces_id == 42


def test_is_frozen():
    n = Notification.from_notify_args(args())
    with pytest.raises(Exception):
        n.app = "other"


def test_osd_hints_is_a_frozenset_of_known_hints():
    assert "x-canonical-private-synchronous" in OSD_HINTS
    assert isinstance(OSD_HINTS, frozenset)
```

- [ ] **Step 2: Run to verify they fail**

Run: `PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 pytest tests/test_model.py -q`
Expected: FAIL, `ModuleNotFoundError: No module named 'notify_tts.model'`

- [ ] **Step 3: Implement**

```python
# src/notify_tts/model.py
"""The notification record.

DBus types stop here. Everything downstream sees a plain frozen dataclass,
which is what lets the filter be tested without a bus.
"""

from __future__ import annotations

from dataclasses import dataclass

# Hints marking a notification as a transient on-screen display: volume and
# brightness overlays that fire repeatedly while a key is held.
OSD_HINTS = frozenset({
    "x-canonical-private-synchronous",
    "x-dunst-stack-tag",
    "synchronous",
})

URGENCY_NORMAL = 1


@dataclass(frozen=True)
class Notification:
    app: str
    summary: str
    body: str
    replaces_id: int
    hints: frozenset[str]
    urgency: int = URGENCY_NORMAL

    @classmethod
    def from_notify_args(cls, args: tuple) -> "Notification":
        """Build from an unpacked org.freedesktop.Notifications.Notify body.

        Signature (susssasa{sv}i): app_name, replaces_id, app_icon, summary,
        body, actions, hints, expire_timeout.
        """
        app, replaces_id, _icon, summary, body, _actions, hints, _timeout = args
        urgency = hints.get("urgency", URGENCY_NORMAL)
        try:
            urgency = int(urgency)
        except (TypeError, ValueError):
            urgency = URGENCY_NORMAL
        return cls(
            app=app or "",
            summary=summary or "",
            body=body or "",
            replaces_id=int(replaces_id or 0),
            hints=frozenset(hints.keys()),
            urgency=urgency,
        )
```

- [ ] **Step 4: Run to verify they pass**

Run: `PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 pytest tests/test_model.py -q`
Expected: 7 passed.

- [ ] **Step 5: Commit**

```bash
git add src/notify_tts/model.py tests/test_model.py
git commit -m "feat(model): Notification record decoupled from DBus types"
```

---

### Task 3: Configuration

**Files:**
- Create: `src/notify_tts/config.py`
- Test: `tests/test_config.py`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `load_config(path: Path | None = None) -> Config`
  - `Config` with `speech: SpeechConfig`, `filter: FilterConfig`
  - `SpeechConfig(priority="message", max_chars=200, include_body=False, voice="")`
  - `FilterConfig(denylist=("spotify","vesktop"), dedup_seconds=10, max_per_minute=12, skip_replaces=True)`
  - `DEFAULT_CONFIG_PATH: Path`, `ConfigError(Exception)`

Same shape as speechd-neural's config deliberately: unknown keys and unknown sections raise rather than being ignored, because a silently-ignored typo is the "why isn't my setting working" failure this project cannot afford.

- [ ] **Step 1: Write the failing tests**

```python
# tests/test_config.py
import pytest
from pathlib import Path
from notify_tts.config import load_config, ConfigError


def test_defaults_apply_when_file_missing(tmp_path):
    cfg = load_config(tmp_path / "nope.toml")
    assert cfg.speech.priority == "message"
    assert cfg.speech.max_chars == 200
    assert cfg.speech.include_body is False
    assert cfg.filter.dedup_seconds == 10
    assert cfg.filter.max_per_minute == 12
    assert cfg.filter.skip_replaces is True


def test_denylist_defaults_are_not_empty(tmp_path):
    # Ships non-empty on purpose: media players emit one notification per track.
    assert len(load_config(tmp_path / "nope.toml").filter.denylist) > 0


def test_file_overrides_defaults(tmp_path):
    p = tmp_path / "config.toml"
    p.write_text('[speech]\nmax_chars = 50\n\n[filter]\ndenylist = ["foo"]\n')
    cfg = load_config(p)
    assert cfg.speech.max_chars == 50
    assert cfg.filter.denylist == ("foo",)
    assert cfg.speech.priority == "message"  # untouched key keeps its default


def test_unknown_key_raises(tmp_path):
    p = tmp_path / "config.toml"
    p.write_text('[speech]\nmax_charz = 50\n')
    with pytest.raises(ConfigError) as e:
        load_config(p)
    assert "max_charz" in str(e.value)


def test_unknown_section_raises(tmp_path):
    p = tmp_path / "config.toml"
    p.write_text('[speach]\nmax_chars = 50\n')
    with pytest.raises(ConfigError):
        load_config(p)


def test_invalid_priority_raises(tmp_path):
    # A typo here silently changes whether bursts are spoken or dropped.
    p = tmp_path / "config.toml"
    p.write_text('[speech]\npriority = "mesage"\n')
    with pytest.raises(ConfigError) as e:
        load_config(p)
    assert "mesage" in str(e.value)


def test_malformed_toml_raises(tmp_path):
    p = tmp_path / "config.toml"
    p.write_text("not = = toml")
    with pytest.raises(ConfigError):
        load_config(p)


def test_denylist_is_normalised_to_lowercase(tmp_path):
    p = tmp_path / "config.toml"
    p.write_text('[filter]\ndenylist = ["Spotify", "VESKTOP"]\n')
    assert load_config(p).filter.denylist == ("spotify", "vesktop")
```

- [ ] **Step 2: Run to verify they fail**

Run: `PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 pytest tests/test_config.py -q`
Expected: FAIL, `ModuleNotFoundError: No module named 'notify_tts.config'`

- [ ] **Step 3: Implement**

```python
# src/notify_tts/config.py
"""Configuration. The file is optional; every value has a default."""

from __future__ import annotations

import os
import tomllib
from dataclasses import dataclass, fields, replace
from pathlib import Path

VALID_PRIORITIES = ("important", "message", "text", "notification", "progress")


class ConfigError(Exception):
    """Malformed TOML, an unrecognised key, or an invalid value."""


def _xdg_config_home() -> Path:
    return Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config")


DEFAULT_CONFIG_PATH = _xdg_config_home() / "notify-tts" / "config.toml"


@dataclass(frozen=True)
class SpeechConfig:
    priority: str = "message"
    max_chars: int = 200
    include_body: bool = False
    voice: str = ""


@dataclass(frozen=True)
class FilterConfig:
    denylist: tuple[str, ...] = ("spotify", "vesktop")
    dedup_seconds: int = 10
    max_per_minute: int = 12
    skip_replaces: bool = True


@dataclass(frozen=True)
class Config:
    speech: SpeechConfig
    filter: FilterConfig


def _apply(section: str, base, raw: dict):
    known = {f.name for f in fields(base)}
    unknown = set(raw) - known
    if unknown:
        raise ConfigError(
            f"unknown key(s) in [{section}]: {', '.join(sorted(unknown))}"
        )
    updates = {}
    for key, value in raw.items():
        if isinstance(getattr(base, key), tuple):
            value = tuple(str(v).lower() for v in value)
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

    unknown = set(raw) - {"speech", "filter"}
    if unknown:
        raise ConfigError(f"unknown section(s): {', '.join(sorted(unknown))}")

    cfg = Config(
        speech=_apply("speech", SpeechConfig(), raw.get("speech", {})),
        filter=_apply("filter", FilterConfig(), raw.get("filter", {})),
    )

    if cfg.speech.priority not in VALID_PRIORITIES:
        raise ConfigError(
            f"invalid priority {cfg.speech.priority!r}, "
            f"expected one of: {', '.join(VALID_PRIORITIES)}"
        )
    return cfg
```

- [ ] **Step 4: Run to verify they pass**

Run: `PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 pytest tests/test_config.py -q`
Expected: 8 passed.

- [ ] **Step 5: Commit**

```bash
git add src/notify_tts/config.py tests/test_config.py
git commit -m "feat(config): optional TOML config with key and value validation"
```

---

### Task 4: The toggle

**Files:**
- Create: `src/notify_tts/state.py`
- Test: `tests/test_state.py`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `state_path() -> Path`
  - `is_enabled(path: Path | None = None) -> bool`
  - `set_enabled(value: bool, path: Path | None = None) -> None`
  - `toggle(path: Path | None = None) -> bool` — returns the new state

Presence of the file means on. A file rather than a config key so toggling is atomic, needs no parser, and cannot corrupt configuration.

- [ ] **Step 1: Write the failing tests**

```python
# tests/test_state.py
from notify_tts.state import is_enabled, set_enabled, toggle, state_path


def test_absent_file_means_off(tmp_path):
    assert is_enabled(tmp_path / "enabled") is False


def test_set_enabled_creates_and_removes(tmp_path):
    p = tmp_path / "enabled"
    set_enabled(True, p)
    assert p.exists() and is_enabled(p) is True
    set_enabled(False, p)
    assert not p.exists() and is_enabled(p) is False


def test_set_enabled_is_idempotent(tmp_path):
    p = tmp_path / "enabled"
    set_enabled(True, p)
    set_enabled(True, p)
    assert is_enabled(p) is True
    set_enabled(False, p)
    set_enabled(False, p)
    assert is_enabled(p) is False


def test_toggle_returns_new_state(tmp_path):
    p = tmp_path / "enabled"
    assert toggle(p) is True
    assert toggle(p) is False


def test_parent_directory_is_created(tmp_path):
    p = tmp_path / "deep" / "nested" / "enabled"
    set_enabled(True, p)
    assert p.exists()


def test_default_path_is_under_home():
    assert str(state_path()).startswith(str(__import__("pathlib").Path.home()))
```

- [ ] **Step 2: Run to verify they fail**

Run: `PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 pytest tests/test_state.py -q`
Expected: FAIL, `ModuleNotFoundError: No module named 'notify_tts.state'`

- [ ] **Step 3: Implement**

```python
# src/notify_tts/state.py
"""The global on/off toggle.

Presence of the state file means on. Deliberately not a config key: toggling
must be atomic, parser-free, and incapable of corrupting configuration.
"""

from __future__ import annotations

import os
from pathlib import Path


def _xdg_state_home() -> Path:
    return Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state")


def state_path() -> Path:
    return _xdg_state_home() / "notify-tts" / "enabled"


def is_enabled(path: Path | None = None) -> bool:
    return (path or state_path()).exists()


def set_enabled(value: bool, path: Path | None = None) -> None:
    p = path or state_path()
    if value:
        p.parent.mkdir(parents=True, exist_ok=True)
        p.touch()
    else:
        p.unlink(missing_ok=True)


def toggle(path: Path | None = None) -> bool:
    p = path or state_path()
    new = not is_enabled(p)
    set_enabled(new, p)
    return new
```

- [ ] **Step 4: Run to verify they pass**

Run: `PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 pytest tests/test_state.py -q`
Expected: 6 passed.

- [ ] **Step 5: Commit**

```bash
git add src/notify_tts/state.py tests/test_state.py
git commit -m "feat(state): file-backed global toggle"
```

---

### Task 5: The filter

**Files:**
- Create: `src/notify_tts/filters.py`, `tests/fakes.py`
- Test: `tests/test_filters.py`

**Interfaces:**
- Consumes: `Notification`, `OSD_HINTS` (Task 2); `FilterConfig` (Task 3); `is_enabled` (Task 4).
- Produces:
  - `Decision(speak: bool, reason: str)` — frozen dataclass
  - `NotificationFilter(cfg: FilterConfig, clock: Callable[[], float] = time.monotonic, enabled: Callable[[], bool] = is_enabled)`
  - `NotificationFilter.decide(n: Notification) -> Decision`
  - `NotificationFilter.counters -> dict[str, int]`
  - `SELF_APPS: frozenset[str]`
  - `FakeClock` in `tests/fakes.py`

This is the heart of the project and the bulk of its tests. It is pure: a notification plus configuration in, a decision out. No bus, no audio, and an injected clock so windows are asserted at their boundaries rather than slept through.

Rule order matters and is itself tested, because two rules can match the same notification and the reported reason must be deterministic.

- [ ] **Step 1: Write the fakes**

```python
# tests/fakes.py
class FakeClock:
    """A monotonic clock under test control."""

    def __init__(self, now=0.0):
        self.now = now

    def __call__(self):
        return self.now

    def advance(self, seconds):
        self.now += seconds


class FakeSpeaker:
    """Records what would have been spoken.

    The signature must match Speaker.speak(text, cfg) exactly — a fake that
    accepts a different shape would let a real call-site mismatch pass.
    """

    def __init__(self, fails=False):
        self.spoken = []
        self.configs = []
        self.fails = fails

    def speak(self, text, cfg):
        if self.fails:
            raise RuntimeError("speaker failed")
        self.spoken.append(text)
        self.configs.append(cfg)
        return True
```

- [ ] **Step 2: Write the failing tests**

```python
# tests/test_filters.py
import pytest
from fakes import FakeClock
from notify_tts.config import FilterConfig
from notify_tts.filters import NotificationFilter, Decision, SELF_APPS
from notify_tts.model import Notification


def note(app="App", summary="Summary", body="", replaces_id=0, hints=()):
    return Notification(app=app, summary=summary, body=body,
                        replaces_id=replaces_id, hints=frozenset(hints))


def make(cfg=None, clock=None, enabled=True):
    return NotificationFilter(
        cfg or FilterConfig(denylist=("spotify",)),
        clock=clock or FakeClock(),
        enabled=lambda: enabled,
    )


def test_ordinary_notification_is_spoken():
    assert make().decide(note()).speak is True


def test_toggle_off_blocks_everything():
    d = make(enabled=False).decide(note())
    assert d.speak is False and d.reason == "disabled"


def test_own_notifications_are_never_spoken():
    # A feedback loop, and worse: when speechd-neural reports that speech is
    # degraded, speaking that through the degraded speech system loses the warning.
    for app in SELF_APPS:
        d = make().decide(note(app=app))
        assert d.speak is False and d.reason == "self"


def test_self_check_is_case_insensitive():
    assert make().decide(note(app="Speechd-Neural")).speak is False


def test_osd_hints_are_skipped():
    d = make().decide(note(hints=["x-canonical-private-synchronous"]))
    assert d.speak is False and d.reason == "osd"


def test_replacement_of_an_existing_notification_is_skipped():
    d = make().decide(note(replaces_id=7))
    assert d.speak is False and d.reason == "replaces"


def test_replacement_is_spoken_when_skip_replaces_is_off():
    cfg = FilterConfig(denylist=(), skip_replaces=False)
    assert make(cfg=cfg).decide(note(replaces_id=7)).speak is True


def test_denylisted_app_is_skipped():
    d = make().decide(note(app="Spotify"))
    assert d.speak is False and d.reason == "denylist"


def test_empty_summary_is_skipped():
    d = make().decide(note(summary="   "))
    assert d.speak is False and d.reason == "empty"


def test_duplicate_within_the_window_is_skipped():
    clock = FakeClock()
    f = make(clock=clock)
    assert f.decide(note()).speak is True
    clock.advance(5)
    d = f.decide(note())
    assert d.speak is False and d.reason == "duplicate"


def test_duplicate_after_the_window_is_spoken():
    clock = FakeClock()
    f = make(clock=clock)
    assert f.decide(note()).speak is True
    clock.advance(11)  # dedup_seconds defaults to 10
    assert f.decide(note()).speak is True


def test_same_summary_from_a_different_app_is_not_a_duplicate():
    f = make()
    assert f.decide(note(app="One")).speak is True
    assert f.decide(note(app="Two")).speak is True


def test_rate_limit_drops_beyond_the_cap():
    cfg = FilterConfig(denylist=(), max_per_minute=3, dedup_seconds=0)
    clock = FakeClock()
    f = make(cfg=cfg, clock=clock)
    for i in range(3):
        assert f.decide(note(summary=f"s{i}")).speak is True
    d = f.decide(note(summary="s4"))
    assert d.speak is False and d.reason == "rate"


def test_rate_limit_window_slides():
    cfg = FilterConfig(denylist=(), max_per_minute=2, dedup_seconds=0)
    clock = FakeClock()
    f = make(cfg=cfg, clock=clock)
    f.decide(note(summary="a"))
    f.decide(note(summary="b"))
    assert f.decide(note(summary="c")).speak is False
    clock.advance(61)
    assert f.decide(note(summary="d")).speak is True


def test_disabled_wins_over_every_other_rule():
    # Order matters: a denylisted app while disabled reports "disabled".
    d = make(enabled=False).decide(note(app="Spotify", summary=""))
    assert d.reason == "disabled"


def test_self_wins_over_denylist():
    cfg = FilterConfig(denylist=("speechd-neural",))
    assert make(cfg=cfg).decide(note(app="speechd-neural")).reason == "self"


def test_counters_track_every_outcome():
    f = make()
    f.decide(note())
    f.decide(note(app="Spotify"))
    f.decide(note(summary=""))
    assert f.counters["spoken"] == 1
    assert f.counters["denylist"] == 1
    assert f.counters["empty"] == 1
```

- [ ] **Step 3: Run to verify they fail**

Run: `PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 pytest tests/test_filters.py -q`
Expected: FAIL, `ModuleNotFoundError: No module named 'notify_tts.filters'`

- [ ] **Step 4: Implement**

```python
# src/notify_tts/filters.py
"""Every rule deciding whether a notification is spoken.

Pure by design: a notification plus configuration in, a decision out. The clock
and the toggle are injected, so the whole of this module is testable without a
bus, an audio device, or a sleep.
"""

from __future__ import annotations

import time
from collections import deque
from dataclasses import dataclass
from typing import Callable

from notify_tts.config import FilterConfig
from notify_tts.model import OSD_HINTS, Notification
from notify_tts.state import is_enabled

# Never spoken. notify-tts speaking its own output is a loop; speaking
# speechd-neural's degradation notice through the degraded speech system loses
# exactly the warning that mattered.
SELF_APPS = frozenset({"notify-tts", "speechd-neural"})

RATE_WINDOW_SECONDS = 60


@dataclass(frozen=True)
class Decision:
    speak: bool
    reason: str


class NotificationFilter:
    def __init__(
        self,
        cfg: FilterConfig,
        clock: Callable[[], float] = time.monotonic,
        enabled: Callable[[], bool] = is_enabled,
    ):
        self._cfg = cfg
        self._clock = clock
        self._enabled = enabled
        self._recent: dict[tuple[str, str], float] = {}
        self._spoken_at: deque[float] = deque()
        self.counters: dict[str, int] = {}

    def _count(self, reason: str) -> None:
        self.counters[reason] = self.counters.get(reason, 0) + 1

    def _reject(self, reason: str) -> Decision:
        self._count(reason)
        return Decision(False, reason)

    def decide(self, n: Notification) -> Decision:
        # Order is deliberate and tested: the earliest matching rule wins, so
        # the reported reason is deterministic when several would match.
        if not self._enabled():
            return self._reject("disabled")

        app = n.app.strip().lower()

        if app in SELF_APPS:
            return self._reject("self")

        if n.hints & OSD_HINTS:
            return self._reject("osd")

        if self._cfg.skip_replaces and n.replaces_id:
            return self._reject("replaces")

        if app in self._cfg.denylist:
            return self._reject("denylist")

        if not n.summary.strip():
            return self._reject("empty")

        now = self._clock()
        key = (app, n.summary)
        last = self._recent.get(key)
        if last is not None and now - last < self._cfg.dedup_seconds:
            return self._reject("duplicate")

        while self._spoken_at and now - self._spoken_at[0] >= RATE_WINDOW_SECONDS:
            self._spoken_at.popleft()
        if len(self._spoken_at) >= self._cfg.max_per_minute:
            return self._reject("rate")

        self._recent[key] = now
        self._spoken_at.append(now)
        self._count("spoken")
        return Decision(True, "spoken")
```

- [ ] **Step 5: Run to verify they pass**

Run: `PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 pytest tests/test_filters.py -q`
Expected: 18 passed.

- [ ] **Step 6: Commit**

```bash
git add src/notify_tts/filters.py tests/fakes.py tests/test_filters.py
git commit -m "feat(filters): every speak-or-skip rule, pure and clock-injected"
```

---

### Task 6: Formatting

**Files:**
- Create: `src/notify_tts/formatting.py`
- Test: `tests/test_formatting.py`

**Interfaces:**
- Consumes: `Notification` (Task 2); `SpeechConfig` (Task 3).
- Produces: `format_utterance(n: Notification, cfg: SpeechConfig) -> str`

The 200-character default comes from a measurement: 392 characters took 18.66s, and speech-dispatcher serialises, so one long utterance blocks everything behind it.

- [ ] **Step 1: Write the failing tests**

```python
# tests/test_formatting.py
from notify_tts.config import SpeechConfig
from notify_tts.formatting import format_utterance
from notify_tts.model import Notification


def note(app="Proton Mail", summary="New message", body="Body text"):
    return Notification(app=app, summary=summary, body=body,
                        replaces_id=0, hints=frozenset())


def test_app_and_summary_by_default():
    assert format_utterance(note(), SpeechConfig()) == "Proton Mail: New message"


def test_body_included_when_configured():
    out = format_utterance(note(), SpeechConfig(include_body=True))
    assert out == "Proton Mail: New message. Body text"


def test_body_omitted_when_empty_even_if_configured():
    out = format_utterance(note(body=""), SpeechConfig(include_body=True))
    assert out == "Proton Mail: New message"


def test_truncated_to_max_chars():
    out = format_utterance(note(summary="x" * 500), SpeechConfig(max_chars=50))
    assert len(out) <= 50


def test_truncation_does_not_split_a_word():
    n = note(app="A", summary="alpha bravo charlie delta")
    out = format_utterance(n, SpeechConfig(max_chars=15))
    assert not out.rstrip().endswith("charl")
    assert len(out) <= 15


def test_missing_app_name_omits_the_prefix():
    assert format_utterance(note(app=""), SpeechConfig()) == "New message"


def test_whitespace_is_collapsed():
    n = note(summary="line one\nline  two\ttab")
    assert format_utterance(n, SpeechConfig()) == "Proton Mail: line one line two tab"


def test_unicode_survives():
    n = note(app="Café", summary="naïve résumé")
    assert format_utterance(n, SpeechConfig()) == "Café: naïve résumé"
```

- [ ] **Step 2: Run to verify they fail**

Run: `PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 pytest tests/test_formatting.py -q`
Expected: FAIL, `ModuleNotFoundError: No module named 'notify_tts.formatting'`

- [ ] **Step 3: Implement**

```python
# src/notify_tts/formatting.py
"""Turn a notification into the sentence that gets spoken.

The length cap is not arbitrary: 392 characters was measured at 18.66s, and
speech-dispatcher serialises requests, so an uncapped body blocks every
notification behind it.
"""

from __future__ import annotations

from notify_tts.config import SpeechConfig
from notify_tts.model import Notification


def _collapse(text: str) -> str:
    return " ".join(text.split())


def _truncate(text: str, limit: int) -> str:
    if len(text) <= limit:
        return text
    cut = text[:limit]
    # Prefer a word boundary, but only if one is reasonably near the end;
    # otherwise a long unbroken token would collapse the whole utterance.
    space = cut.rfind(" ")
    if space > limit // 2:
        cut = cut[:space]
    return cut.rstrip()


def format_utterance(n: Notification, cfg: SpeechConfig) -> str:
    app = _collapse(n.app)
    summary = _collapse(n.summary)

    text = f"{app}: {summary}" if app else summary

    if cfg.include_body:
        body = _collapse(n.body)
        if body:
            text = f"{text}. {body}"

    return _truncate(text, cfg.max_chars)
```

- [ ] **Step 4: Run to verify they pass**

Run: `PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 pytest tests/test_formatting.py -q`
Expected: 8 passed.

- [ ] **Step 5: Commit**

```bash
git add src/notify_tts/formatting.py tests/test_formatting.py
git commit -m "feat(formatting): app plus summary, collapsed and capped"
```

---

### Task 7: The speaker

**Files:**
- Create: `src/notify_tts/speaker.py`
- Test: `tests/test_speaker.py`

**Interfaces:**
- Consumes: `SpeechConfig` (Task 3).
- Produces:
  - `build_argv(text: str, cfg: SpeechConfig) -> list[str]`
  - `Speaker(runner=subprocess.run, timeout: float = 30.0)` with `speak(text, cfg) -> bool`
  - `SpeakerError(Exception)`

`build_argv` is separate from running it, exactly as `build_pipeline` was in speechd-neural, so argv can be asserted without spawning anything.

- [ ] **Step 1: Write the failing tests**

```python
# tests/test_speaker.py
import subprocess
from notify_tts.config import SpeechConfig
from notify_tts.speaker import Speaker, build_argv


def test_argv_uses_spd_say_and_waits():
    argv = build_argv("hello", SpeechConfig())
    assert argv[0] == "spd-say"
    assert "-w" in argv, "must wait, so the queue paces itself against real speech"


def test_argv_carries_the_configured_priority():
    argv = build_argv("hello", SpeechConfig(priority="message"))
    assert "-P" in argv and argv[argv.index("-P") + 1] == "message"


def test_argv_omits_voice_when_unset():
    assert "-y" not in build_argv("hello", SpeechConfig())


def test_argv_includes_voice_when_set():
    argv = build_argv("hello", SpeechConfig(voice="FEMALE2"))
    assert argv[argv.index("-y") + 1] == "FEMALE2"


def test_text_is_passed_after_a_double_dash():
    # Without it, a summary beginning with "-" would be parsed as a flag.
    argv = build_argv("-not-a-flag", SpeechConfig())
    assert argv[-2] == "--" and argv[-1] == "-not-a-flag"


def test_speak_returns_true_on_success():
    calls = []

    def runner(argv, **kw):
        calls.append((argv, kw))
        return subprocess.CompletedProcess(argv, 0)

    assert Speaker(runner=runner).speak("hi", SpeechConfig()) is True
    assert calls[0][1]["timeout"] == 30.0


def test_speak_returns_false_on_non_zero_exit():
    def runner(argv, **kw):
        return subprocess.CompletedProcess(argv, 1)

    assert Speaker(runner=runner).speak("hi", SpeechConfig()) is False


def test_timeout_returns_false_rather_than_raising():
    # A hung speech system must drop one utterance, not stall the queue.
    def runner(argv, **kw):
        raise subprocess.TimeoutExpired(argv, 30)

    assert Speaker(runner=runner).speak("hi", SpeechConfig()) is False


def test_missing_binary_returns_false_rather_than_raising():
    def runner(argv, **kw):
        raise FileNotFoundError("spd-say")

    assert Speaker(runner=runner).speak("hi", SpeechConfig()) is False
```

- [ ] **Step 2: Run to verify they fail**

Run: `PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 pytest tests/test_speaker.py -q`
Expected: FAIL, `ModuleNotFoundError: No module named 'notify_tts.speaker'`

- [ ] **Step 3: Implement**

```python
# src/notify_tts/speaker.py
"""Speech, delegated entirely to speech-dispatcher.

This project synthesises nothing. Voices, engines, fallback and failure
handling all belong to whichever output module speechd is configured with.
"""

from __future__ import annotations

import logging
import subprocess

from notify_tts.config import SpeechConfig

log = logging.getLogger(__name__)


class SpeakerError(Exception):
    """Raised only for programming errors; runtime failures return False."""


def build_argv(text: str, cfg: SpeechConfig) -> list[str]:
    argv = ["spd-say", "-w", "-P", cfg.priority]
    if cfg.voice:
        argv += ["-y", cfg.voice]
    # "--" so a summary starting with a hyphen is not parsed as a flag.
    argv += ["--", text]
    return argv


class Speaker:
    def __init__(self, runner=subprocess.run, timeout: float = 30.0):
        self._runner = runner
        self._timeout = timeout

    def speak(self, text: str, cfg: SpeechConfig) -> bool:
        """Speak text. Returns False on any failure; never raises.

        Failing to speak one notification must never stall the queue or kill
        the daemon.
        """
        argv = build_argv(text, cfg)
        try:
            result = self._runner(argv, timeout=self._timeout)
        except subprocess.TimeoutExpired:
            log.warning("[WARN] spd-say timed out after %ss, dropping", self._timeout)
            return False
        except FileNotFoundError:
            log.error("[ERROR] spd-say not found on PATH")
            return False
        except Exception:
            log.exception("[ERROR] speaking failed")
            return False

        if result.returncode != 0:
            log.warning("[WARN] spd-say exited %s", result.returncode)
            return False
        return True
```

- [ ] **Step 4: Run to verify they pass**

Run: `PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 pytest tests/test_speaker.py -q`
Expected: 9 passed.

- [ ] **Step 5: Commit**

```bash
git add src/notify_tts/speaker.py tests/test_speaker.py
git commit -m "feat(speaker): spd-say invocation that never raises"
```

---

### Task 8: The queue

**Files:**
- Create: `src/notify_tts/queue.py`
- Test: `tests/test_queue.py`

**Interfaces:**
- Consumes: `SpeechConfig` (Task 3).
- Produces:
  - `SpeechQueue(speaker, cfg: SpeechConfig, maxsize: int = 8)` with `submit(text) -> bool`, `start()`, `stop(timeout=5)`, `counters: dict[str, int]`

Bounded, dropping the **oldest** when full: speech is far slower than notifications can arrive, and when a backlog forms the newest notification is the one most likely still to matter. A single worker, because speech-dispatcher serialises anyway.

- [ ] **Step 1: Write the failing tests**

```python
# tests/test_queue.py
import threading
import time
from fakes import FakeSpeaker
from notify_tts.config import SpeechConfig
from notify_tts.queue import SpeechQueue


def drain(q, expected, timeout=2.0):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if len(q._speaker.spoken) >= expected:
            return True
        time.sleep(0.01)
    return False


def test_submitted_text_is_spoken():
    q = SpeechQueue(FakeSpeaker(), SpeechConfig())
    q.start()
    try:
        q.submit("hello")
        assert drain(q, 1)
        assert q._speaker.spoken == ["hello"]
    finally:
        q.stop()


def test_order_is_preserved():
    q = SpeechQueue(FakeSpeaker(), SpeechConfig())
    q.start()
    try:
        for w in ("one", "two", "three"):
            q.submit(w)
        assert drain(q, 3)
        assert q._speaker.spoken == ["one", "two", "three"]
    finally:
        q.stop()


def test_full_queue_drops_the_oldest():
    # Worker not started, so nothing drains: the queue fills deterministically.
    q = SpeechQueue(FakeSpeaker(), SpeechConfig(), maxsize=2)
    assert q.submit("a") is True
    assert q.submit("b") is True
    assert q.submit("c") is False        # reports the drop
    assert list(q._queue.queue) == ["b", "c"]
    assert q.counters["dropped"] == 1


def test_a_failing_speaker_does_not_kill_the_worker():
    speaker = FakeSpeaker(fails=True)
    q = SpeechQueue(speaker, SpeechConfig())
    q.start()
    try:
        q.submit("first")
        q.submit("second")
        time.sleep(0.2)
        assert q._thread.is_alive(), "the worker must survive a speaker failure"
        assert q.counters.get("failed", 0) >= 1
    finally:
        q.stop()


def test_stop_is_idempotent():
    q = SpeechQueue(FakeSpeaker(), SpeechConfig())
    q.start()
    q.stop()
    q.stop()
    assert not q._thread.is_alive()
```

- [ ] **Step 2: Run to verify they fail**

Run: `PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 pytest tests/test_queue.py -q`
Expected: FAIL, `ModuleNotFoundError: No module named 'notify_tts.queue'`

- [ ] **Step 3: Implement**

```python
# src/notify_tts/queue.py
"""A bounded queue with one worker.

Bounded because speech is far slower than notifications can arrive, and an
unbounded backlog is how the predecessor setup became unusable. One worker
because speech-dispatcher serialises requests anyway, so concurrency would buy
nothing and only reorder speech.
"""

from __future__ import annotations

import logging
import queue as _queue
import threading

from notify_tts.config import SpeechConfig

log = logging.getLogger(__name__)

_SENTINEL = object()


class SpeechQueue:
    def __init__(self, speaker, cfg: SpeechConfig, maxsize: int = 8):
        self._speaker = speaker
        self._cfg = cfg
        self._queue: _queue.Queue = _queue.Queue(maxsize=maxsize)
        self._thread: threading.Thread | None = None
        self._lock = threading.Lock()
        self.counters: dict[str, int] = {}

    def _count(self, key: str) -> None:
        self.counters[key] = self.counters.get(key, 0) + 1

    def submit(self, text: str) -> bool:
        """Queue text. Returns False when something had to be dropped.

        Drops the OLDEST on overflow: during a backlog the newest notification
        is the one most likely still to matter.
        """
        with self._lock:
            dropped = False
            while True:
                try:
                    self._queue.put_nowait(text)
                    break
                except _queue.Full:
                    try:
                        self._queue.get_nowait()
                        self._count("dropped")
                        dropped = True
                    except _queue.Empty:      # drained concurrently
                        continue
            return not dropped

    def _run(self) -> None:
        while True:
            item = self._queue.get()
            if item is _SENTINEL:
                return
            try:
                if self._speaker.speak(item, self._cfg):
                    self._count("spoken")
                else:
                    self._count("failed")
            except Exception:
                # A malformed item or a broken speaker must never kill the
                # worker; the daemon has to outlive individual failures.
                self._count("failed")
                log.exception("[ERROR] speaking an item failed")

    def start(self) -> None:
        self._thread = threading.Thread(target=self._run, daemon=True)
        self._thread.start()

    def stop(self, timeout: float = 5.0) -> None:
        if self._thread is None or not self._thread.is_alive():
            return
        self._queue.put(_SENTINEL)
        self._thread.join(timeout)
```

- [ ] **Step 4: Run to verify they pass**

Run: `PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 pytest tests/test_queue.py -q`
Expected: 5 passed.

- [ ] **Step 5: Commit**

```bash
git add src/notify_tts/queue.py tests/test_queue.py
git commit -m "feat(queue): bounded single-worker queue that drops the oldest"
```

---

### Task 9: The DBus monitor

**Files:**
- Create: `src/notify_tts/monitor.py`
- Test: `tests/test_monitor.py`

**Interfaces:**
- Consumes: `Notification` (Task 2).
- Produces:
  - `Monitor(on_notification: Callable[[Notification], None])` with `connect()`, `run()`, `stop()`
  - `MATCH_RULE: str`
  - `MonitorError(Exception)`

**The code below is adapted from a spike that was run against the live session bus and verified to work.** Do not substitute a different DBus approach.

Two details that are load-bearing:
- A **private** connection is required. `BecomeMonitor` puts a connection into a monitor-only state, so using the process's shared bus connection would break every other use of it.
- The filter callback must return `None`. It observes; it must never consume or alter the message, because this daemon must not sit in the notification delivery path.

- [ ] **Step 1: Write the failing tests**

```python
# tests/test_monitor.py
import pytest
from notify_tts.model import Notification
from notify_tts.monitor import MATCH_RULE, decode_message


class FakeMessage:
    """Stands in for Gio.DBusMessage without needing a bus."""

    def __init__(self, body):
        self._body = body

    def get_body(self):
        return self._body


class FakeBody:
    def __init__(self, unpacked):
        self._unpacked = unpacked

    def unpack(self):
        return self._unpacked


def notify_args(app="App", summary="Summary"):
    return (app, 0, "icon", summary, "body", [], {"urgency": 1}, -1)


def test_match_rule_targets_only_notify_method_calls():
    assert "org.freedesktop.Notifications" in MATCH_RULE
    assert "member='Notify'" in MATCH_RULE
    assert "type='method_call'" in MATCH_RULE


def test_decodes_a_notify_message():
    n = decode_message(FakeMessage(FakeBody(notify_args(app="Proton Mail"))))
    assert isinstance(n, Notification)
    assert n.app == "Proton Mail"


def test_message_with_no_body_is_ignored():
    assert decode_message(FakeMessage(None)) is None


def test_malformed_body_is_ignored_rather_than_raising():
    # A daemon that dies on one odd message stops reading every later one.
    assert decode_message(FakeMessage(FakeBody(("too", "few")))) is None


def test_unpack_failure_is_ignored():
    class Boom:
        def unpack(self):
            raise RuntimeError("bad variant")

    assert decode_message(FakeMessage(Boom())) is None
```

- [ ] **Step 2: Run to verify they fail**

Run: `PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 pytest tests/test_monitor.py -q`
Expected: FAIL, `ModuleNotFoundError: No module named 'notify_tts.monitor'`

- [ ] **Step 3: Implement**

```python
# src/notify_tts/monitor.py
"""Observe Notify calls on the session bus.

Verified against the live bus before implementation: a private connection
accepts BecomeMonitor and captures real notifications.

This module observes and nothing else. It never consumes, delays or alters a
message, because a notification must be displayed whether or not it is spoken.
"""

from __future__ import annotations

import logging
import os
from typing import Callable

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

from notify_tts.model import Notification  # noqa: E402

log = logging.getLogger(__name__)

MATCH_RULE = (
    "type='method_call',"
    "interface='org.freedesktop.Notifications',"
    "member='Notify'"
)


class MonitorError(Exception):
    """The session bus is unreachable, or monitoring was refused."""


def decode_message(message) -> Notification | None:
    """Turn a DBus message into a Notification, or None if it is not usable."""
    try:
        body = message.get_body()
        if body is None:
            return None
        args = body.unpack()
        if not isinstance(args, tuple) or len(args) < 8:
            return None
        return Notification.from_notify_args(args)
    except Exception:
        # One malformed message must not stop us reading every later one.
        log.debug("ignoring an undecodable message", exc_info=True)
        return None


class Monitor:
    def __init__(self, on_notification: Callable[[Notification], None]):
        self._on_notification = on_notification
        self._conn = None
        self._loop = GLib.MainLoop()

    def connect(self) -> None:
        address = os.environ.get("DBUS_SESSION_BUS_ADDRESS")
        if not address:
            raise MonitorError("DBUS_SESSION_BUS_ADDRESS is not set")

        try:
            # A PRIVATE connection: BecomeMonitor puts the connection into a
            # monitor-only state, which would break any shared use of it.
            conn = Gio.DBusConnection.new_for_address_sync(
                address,
                Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT
                | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION,
                None, None,
            )
            conn.set_exit_on_close(False)
            conn.call_sync(
                "org.freedesktop.DBus", "/org/freedesktop/DBus",
                "org.freedesktop.DBus.Monitoring", "BecomeMonitor",
                GLib.Variant("(asu)", ([MATCH_RULE], 0)),
                GLib.VariantType("()"), Gio.DBusCallFlags.NONE, -1, None,
            )
        except GLib.Error as exc:
            raise MonitorError(f"could not become a bus monitor: {exc}") from exc

        conn.add_filter(self._on_message)
        self._conn = conn
        log.info("monitoring notifications on the session bus")

    def _on_message(self, connection, message, incoming):
        notification = decode_message(message)
        if notification is not None:
            try:
                self._on_notification(notification)
            except Exception:
                log.exception("[ERROR] handling a notification failed")
        # Returning None leaves the message untouched. This daemon observes;
        # it must never sit in the delivery path.
        return None

    def run(self) -> None:
        self._loop.run()

    def stop(self) -> None:
        self._loop.quit()
```

- [ ] **Step 4: Run to verify they pass**

Run: `PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 pytest tests/test_monitor.py -q`
Expected: 5 passed.

- [ ] **Step 5: Verify against the real bus by hand**

```bash
cd ~/git/github.com/cadrianmae/notify-tts
PYTHONPATH=src python3 -c "
from notify_tts.monitor import Monitor
from gi.repository import GLib
m = Monitor(lambda n: (print(f'[OK] {n.app}: {n.summary}'), m.stop()))
m.connect()
GLib.timeout_add_seconds(10, lambda: (print('[FAIL] nothing captured'), m.stop())[1])
m.run()
" &
sleep 2
notify-send -a "RealApp" "Real summary"
wait
```

Expected: `[OK] RealApp: Real summary`. Report the output verbatim.

- [ ] **Step 6: Commit**

```bash
git add src/notify_tts/monitor.py tests/test_monitor.py
git commit -m "feat(monitor): observe Notify calls without entering the delivery path"
```

---

### Task 10: The daemon

**Files:**
- Create: `src/notify_tts/daemon.py`
- Test: `tests/test_daemon.py`

**Interfaces:**
- Consumes: everything from Tasks 2 to 9.
- Produces:
  - `Daemon(cfg, filter_, queue, monitor_factory=Monitor)` with `handle(n: Notification) -> None`, `run() -> int`, `counters: dict[str, int]`
  - `status_payload(daemon) -> dict`
  - `main() -> int`

The daemon owns wiring and counters, nothing else. It is tested by driving `handle()` directly with notifications, so no bus is involved.

- [ ] **Step 1: Write the failing tests**

```python
# tests/test_daemon.py
from fakes import FakeClock, FakeSpeaker
from notify_tts.config import Config, FilterConfig, SpeechConfig
from notify_tts.daemon import Daemon, status_payload
from notify_tts.filters import NotificationFilter
from notify_tts.model import Notification
from notify_tts.queue import SpeechQueue


def note(app="App", summary="Summary", **kw):
    return Notification(app=app, summary=summary, body=kw.get("body", ""),
                        replaces_id=kw.get("replaces_id", 0),
                        hints=frozenset(kw.get("hints", ())))


def build(enabled=True, speech=None, filt=None):
    cfg = Config(speech=speech or SpeechConfig(),
                 filter=filt or FilterConfig(denylist=("spotify",)))
    speaker = FakeSpeaker()
    q = SpeechQueue(speaker, cfg.speech)
    f = NotificationFilter(cfg.filter, clock=FakeClock(), enabled=lambda: enabled)
    return Daemon(cfg, f, q), speaker, q


def test_an_accepted_notification_is_queued():
    d, speaker, q = build()
    d.handle(note())
    assert list(q._queue.queue) == ["App: Summary"]


def test_a_filtered_notification_is_not_queued():
    d, speaker, q = build()
    d.handle(note(app="Spotify"))
    assert list(q._queue.queue) == []


def test_nothing_is_queued_while_disabled():
    d, speaker, q = build(enabled=False)
    d.handle(note())
    assert list(q._queue.queue) == []


def test_the_formatted_text_is_what_gets_queued():
    d, speaker, q = build(speech=SpeechConfig(max_chars=12))
    d.handle(note(app="Proton", summary="a very long summary indeed"))
    assert len(list(q._queue.queue)[0]) <= 12


def test_counters_are_reported():
    d, speaker, q = build()
    d.handle(note())
    d.handle(note(app="Spotify"))
    payload = status_payload(d)
    assert payload["seen"] == 2
    assert payload["filter"]["spoken"] == 1
    assert payload["filter"]["denylist"] == 1
    assert payload["enabled"] is True


def test_a_handler_exception_does_not_escape():
    # The monitor calls handle() from the bus callback; an escape there would
    # take down message processing entirely.
    d, speaker, q = build()
    d._filter = None          # force an AttributeError inside handle
    d.handle(note())          # must not raise
```

- [ ] **Step 2: Run to verify they fail**

Run: `PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 pytest tests/test_daemon.py -q`
Expected: FAIL, `ModuleNotFoundError: No module named 'notify_tts.daemon'`

- [ ] **Step 3: Implement**

```python
# src/notify_tts/daemon.py
"""Wiring and counters. Owns no rules of its own."""

from __future__ import annotations

import logging
import sys

from notify_tts.config import Config, load_config
from notify_tts.filters import NotificationFilter
from notify_tts.formatting import format_utterance
from notify_tts.model import Notification
from notify_tts.queue import SpeechQueue
from notify_tts.speaker import Speaker
from notify_tts.state import is_enabled

log = logging.getLogger(__name__)


def status_payload(daemon: "Daemon") -> dict:
    return {
        "enabled": is_enabled(),
        "seen": daemon.counters.get("seen", 0),
        "filter": dict(daemon._filter.counters) if daemon._filter else {},
        "queue": dict(daemon._queue.counters),
    }


class Daemon:
    def __init__(self, cfg: Config, filter_, queue, monitor_factory=None):
        self._cfg = cfg
        self._filter = filter_
        self._queue = queue
        self._monitor_factory = monitor_factory
        self._monitor = None
        self.counters: dict[str, int] = {}

    def handle(self, n: Notification) -> None:
        """Called from the bus callback. Must never raise."""
        try:
            self.counters["seen"] = self.counters.get("seen", 0) + 1
            decision = self._filter.decide(n)
            if not decision.speak:
                log.debug("skipped (%s): %s", decision.reason, n.summary)
                return
            self._queue.submit(format_utterance(n, self._cfg.speech))
        except Exception:
            log.exception("[ERROR] handling a notification failed")

    def run(self) -> int:
        from notify_tts.monitor import Monitor, MonitorError

        factory = self._monitor_factory or Monitor
        self._queue.start()
        try:
            self._monitor = factory(self.handle)
            self._monitor.connect()
        except MonitorError as exc:
            log.error("[ERROR] %s", exc)
            self._queue.stop()
            return 1

        log.info("notify-tts ready (toggle is %s)", "on" if is_enabled() else "off")
        try:
            self._monitor.run()
        except KeyboardInterrupt:
            pass
        finally:
            self._queue.stop()
        return 0


def main() -> int:
    logging.basicConfig(
        stream=sys.stderr, level=logging.INFO,
        format="%(levelname)s notify-tts: %(message)s",
    )
    cfg = load_config()
    queue = SpeechQueue(Speaker(), cfg.speech)
    filter_ = NotificationFilter(cfg.filter)
    return Daemon(cfg, filter_, queue).run()


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 4: Run to verify they pass**

Run: `PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 pytest tests/test_daemon.py -q`
Expected: 6 passed. Then the full suite.

- [ ] **Step 5: Commit**

```bash
git add src/notify_tts/daemon.py tests/test_daemon.py
git commit -m "feat(daemon): wiring, counters and a handler that never raises"
```

---

### Task 11: The CLI

**Files:**
- Create: `src/notify_tts/cli.py`
- Test: `tests/test_cli.py`

**Interfaces:**
- Consumes: `state` (Task 4), `config` (Task 3), `Speaker` (Task 7).
- Produces: `main(argv: list[str] | None = None) -> int` with `on`, `off`, `toggle`, `status`, `test`.

`status` must work whether or not the daemon is running, since "is this thing on?" is the question it exists to answer.

- [ ] **Step 1: Write the failing tests**

```python
# tests/test_cli.py
import pytest
from notify_tts import cli


def test_on_enables(tmp_path, monkeypatch, capsys):
    p = tmp_path / "enabled"
    monkeypatch.setattr(cli, "state_path", lambda: p)
    assert cli.main(["on"]) == 0
    assert p.exists()
    assert "[OK]" in capsys.readouterr().out


def test_off_disables(tmp_path, monkeypatch):
    p = tmp_path / "enabled"
    p.parent.mkdir(parents=True, exist_ok=True)
    p.touch()
    monkeypatch.setattr(cli, "state_path", lambda: p)
    assert cli.main(["off"]) == 0
    assert not p.exists()


def test_toggle_flips_twice(tmp_path, monkeypatch):
    p = tmp_path / "enabled"
    monkeypatch.setattr(cli, "state_path", lambda: p)
    cli.main(["toggle"])
    assert p.exists()
    cli.main(["toggle"])
    assert not p.exists()


def test_status_reports_off_without_a_running_daemon(tmp_path, monkeypatch, capsys):
    monkeypatch.setattr(cli, "state_path", lambda: tmp_path / "enabled")
    assert cli.main(["status"]) == 0
    assert "off" in capsys.readouterr().out.lower()


def test_no_subcommand_prints_usage():
    assert cli.main([]) != 0


def test_unknown_subcommand_exits_non_zero():
    with pytest.raises(SystemExit) as e:
        cli.main(["nonsense"])
    assert e.value.code != 0


def test_test_subcommand_speaks_and_reports(monkeypatch, capsys):
    spoken = []
    monkeypatch.setattr(cli, "_speak_test", lambda cfg: (spoken.append(1), True)[1])
    assert cli.main(["test"]) == 0
    assert spoken and "[OK]" in capsys.readouterr().out


def test_test_subcommand_reports_failure(monkeypatch, capsys):
    monkeypatch.setattr(cli, "_speak_test", lambda cfg: False)
    assert cli.main(["test"]) != 0
    assert "[FAIL]" in capsys.readouterr().out
```

- [ ] **Step 2: Run to verify they fail**

Run: `PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 pytest tests/test_cli.py -q`
Expected: FAIL, `ModuleNotFoundError: No module named 'notify_tts.cli'`

- [ ] **Step 3: Implement**

```python
# src/notify_tts/cli.py
"""notify-tts CLI: on, off, toggle, status, test."""

from __future__ import annotations

import argparse
import sys

from notify_tts.config import load_config
from notify_tts.speaker import Speaker
from notify_tts.state import is_enabled, set_enabled, state_path, toggle


def _speak_test(cfg) -> bool:
    return Speaker().speak("notify-tts is working", cfg.speech)


def _cmd_on(args, cfg) -> int:
    set_enabled(True, state_path())
    print("[OK] notifications will be spoken")
    return 0


def _cmd_off(args, cfg) -> int:
    set_enabled(False, state_path())
    print("[OK] notifications are silent")
    return 0


def _cmd_toggle(args, cfg) -> int:
    now = toggle(state_path())
    print(f"[OK] notifications are now {'spoken' if now else 'silent'}")
    return 0


def _cmd_status(args, cfg) -> int:
    on = is_enabled(state_path())
    print(f"toggle:   {'on' if on else 'off'}")
    print(f"state:    {state_path()}")
    print(f"priority: {cfg.speech.priority}")
    print(f"max_chars:{cfg.speech.max_chars}")
    print(f"denylist: {', '.join(cfg.filter.denylist) or '(empty)'}")
    return 0


def _cmd_test(args, cfg) -> int:
    if _speak_test(cfg):
        print("[OK] spoke a test phrase")
        return 0
    print("[FAIL] could not speak; check speech-dispatcher", file=sys.stdout)
    return 1


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="notify-tts")
    sub = parser.add_subparsers(dest="command")
    for name, help_text in (
        ("on", "speak notifications"),
        ("off", "stop speaking notifications"),
        ("toggle", "flip between on and off"),
        ("status", "show the toggle and effective configuration"),
        ("test", "speak a test phrase"),
    ):
        sub.add_parser(name, help=help_text)

    args = parser.parse_args(argv)
    if not args.command:
        parser.print_usage(sys.stderr)
        return 2

    cfg = load_config()
    handlers = {
        "on": _cmd_on, "off": _cmd_off, "toggle": _cmd_toggle,
        "status": _cmd_status, "test": _cmd_test,
    }
    return handlers[args.command](args, cfg)


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 4: Run to verify they pass**

Run: `PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 pytest tests/test_cli.py -q`
Expected: 8 passed. Then the full suite.

- [ ] **Step 5: Commit**

```bash
git add src/notify_tts/cli.py tests/test_cli.py
git commit -m "feat(cli): on, off, toggle, status and test"
```

---

### Task 12: Install, uninstall and the unit

**Files:**
- Create: `install.sh`, `uninstall.sh`, `conf/notify-tts.service.in`, `tests/test_install.sh`

**Interfaces:**
- Consumes: the package.
- Produces: an installed tree under `$HOME` and a running user service. No file outside `$HOME` is touched.

An uninstaller ships from the outset here, rather than being deferred as it was in the sibling project.

- [ ] **Step 1: Write the unit template**

`@PYTHON@` and `@LIBEXEC@` are substituted at install time, so no path is ever committed. No python version appears.

```ini
# conf/notify-tts.service.in
[Unit]
Description=Speak desktop notifications
PartOf=graphical-session.target
After=graphical-session.target

[Service]
Type=exec
ExecStart=@PYTHON@ -m notify_tts.daemon
Environment="PYTHONPATH=@LIBEXEC@"
Restart=always
RestartSec=5
Slice=session.slice

[Install]
WantedBy=graphical-session.target
```

- [ ] **Step 2: Write `install.sh`**

```bash
#!/usr/bin/env bash
# Install notify-tts into the current user's XDG directories.
# Nothing outside $HOME is touched. Re-running is safe.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

XDG_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
LIBEXEC="$HOME/.local/libexec/notify-tts"
BIN="$HOME/.local/bin"
UNITS="$XDG_CONFIG/systemd/user"

PYTHON="$(command -v python3)"

mkdir -p "$LIBEXEC" "$BIN" "$UNITS" "$XDG_CONFIG/notify-tts"

# Used from the repo, so development needs no reinstall.
ln -sfn "$REPO/src/notify_tts" "$LIBEXEC/notify_tts"

cat > "$BIN/notify-tts" <<EOF
#!/usr/bin/env bash
export PYTHONPATH="$LIBEXEC\${PYTHONPATH:+:\$PYTHONPATH}"
exec "$PYTHON" -m notify_tts.cli "\$@"
EOF
chmod +x "$BIN/notify-tts"

sed -e "s|@PYTHON@|$PYTHON|g" -e "s|@LIBEXEC@|$LIBEXEC|g" \
    "$REPO/conf/notify-tts.service.in" > "$UNITS/notify-tts.service"

systemctl --user daemon-reload
systemctl --user enable --now notify-tts.service

echo "[OK] installed"
echo "Turn speech on with:  notify-tts on"
```

- [ ] **Step 3: Write `uninstall.sh`**

```bash
#!/usr/bin/env bash
# Remove notify-tts. Keeps the config unless --purge is given.
set -euo pipefail

XDG_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_STATE="${XDG_STATE_HOME:-$HOME/.local/state}"
LIBEXEC="$HOME/.local/libexec/notify-tts"
BIN="$HOME/.local/bin/notify-tts"
UNITS="$XDG_CONFIG/systemd/user"

PURGE=0
[ "${1:-}" = "--purge" ] && PURGE=1

systemctl --user disable --now notify-tts.service 2>/dev/null || true
rm -f "$UNITS/notify-tts.service"
systemctl --user daemon-reload 2>/dev/null || true

rm -rf "$LIBEXEC"
rm -f "$BIN"
rm -rf "$XDG_STATE/notify-tts"

if [ "$PURGE" -eq 1 ]; then
    rm -rf "$XDG_CONFIG/notify-tts"
    echo "[OK] removed, including configuration"
else
    echo "[OK] removed. Configuration kept at $XDG_CONFIG/notify-tts"
    echo "     Use --purge to remove it too."
fi
```

- [ ] **Step 4: Write `tests/test_install.sh`**

```bash
#!/usr/bin/env bash
# Install/uninstall round trip. Run by hand; not part of the pytest suite.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fails=0

check()     { if "$@" >/dev/null 2>&1; then echo "[OK]   $*"; else echo "[ERROR] $*"; fails=$((fails+1)); fi; }
check_not() { if "$@" >/dev/null 2>&1; then echo "[ERROR] unexpectedly true: $*"; fails=$((fails+1)); else echo "[OK]   not: $*"; fi; }

"$REPO/install.sh" >/dev/null

check test -x "$HOME/.local/bin/notify-tts"
check test -L "$HOME/.local/libexec/notify-tts/notify_tts"
check test -f "${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/notify-tts.service"
check systemctl --user is-active --quiet notify-tts.service
check_not grep -qE 'python3\.[0-9]+' "$REPO/conf/notify-tts.service.in"
check_not grep -q "$HOME" "$REPO/conf/notify-tts.service.in"

"$REPO/uninstall.sh" >/dev/null

check_not test -e "$HOME/.local/bin/notify-tts"
check_not test -e "$HOME/.local/libexec/notify-tts"
check_not systemctl --user is-active --quiet notify-tts.service

echo
[ "$fails" -eq 0 ] && echo "[OK] all checks passed" || echo "[ERROR] $fails check(s) failed"
exit "$fails"
```

- [ ] **Step 5: Run the round trip**

```bash
cd ~/git/github.com/cadrianmae/notify-tts
chmod +x install.sh uninstall.sh tests/test_install.sh
./tests/test_install.sh
```

Expected: `[OK] all checks passed`. Then install again for Task 13:

```bash
./install.sh && notify-tts status
```

- [ ] **Step 6: Commit**

```bash
git add install.sh uninstall.sh conf/ tests/test_install.sh
git commit -m "feat(install): templated install with an uninstaller"
```

---

### Task 13: End-to-end verification

**Files:**
- Create: `docs/install.md`

**Interfaces:**
- Consumes: a completed install from Task 12.
- Produces: evidence the whole thing works, and the document a user needs.

This is the first time the daemon reads real notifications aloud. It will make sound.

- [ ] **Step 1: Confirm the daemon is running and silent by default**

```bash
systemctl --user is-active notify-tts.service
notify-tts status
notify-send -a "QuietTest" "This must not be spoken"
```

Expected: active, toggle `off`, and **silence**. Report whether anything was spoken; anything audible here is a defect.

- [ ] **Step 2: Turn it on and hear a notification**

```bash
notify-tts on
notify-send -a "Proton Mail" "New message from Ciaran"
```

Expected: "Proton Mail: New message from Ciaran". Report verbatim what was heard.

- [ ] **Step 3: Verify each filter rule against the live bus**

```bash
# Denylisted app: silent
notify-send -a "Spotify" "Track change that should be silent"

# Empty summary: silent
notify-send -a "EmptyTest" ""

# Duplicate within the window: spoken once, not twice
notify-send -a "DupTest" "Duplicate check"; sleep 1; notify-send -a "DupTest" "Duplicate check"

# The feedback-loop guard: silent
notify-send -a "speechd-neural" "TTS degraded: piper to espeak"
```

Report which were spoken and which were not, against what each rule predicts.

- [ ] **Step 4: Verify the toggle takes effect immediately**

```bash
notify-tts off
notify-send -a "OffTest" "Must be silent"
notify-tts on
notify-send -a "OnTest" "Must be spoken"
```

Expected: no restart needed for either transition, because the toggle is read per notification.

- [ ] **Step 5: Verify counters and the journal**

```bash
notify-tts status
journalctl --user -u notify-tts -n 30 --no-pager
```

Expected: counters reflecting the tests above, and logs in the journal rather than a file.

- [ ] **Step 6: Confirm notifications still display when speech is broken**

```bash
notify-tts on
sudo systemctl stop speech-dispatcherd 2>/dev/null || pkill -u "$USER" speech-dispatcher || true
notify-send -a "ResilienceTest" "This must still appear on screen"
```

Expected: the notification is **displayed** even though nothing can speak it. This is the project's governing constraint, so report explicitly whether the notification appeared.

- [ ] **Step 7: Write `docs/install.md`**

````markdown
# Installing notify-tts

Requires python 3.11+, PyGObject, and a working speech-dispatcher setup
(`spd-say` on PATH). It synthesises nothing itself.

## Install

```bash
git clone <repo-url> notify-tts
cd notify-tts
./install.sh
```

Installs into `~/.local/libexec/notify-tts`, `~/.local/bin/notify-tts`, and a
systemd user unit. Nothing is written outside `$HOME`.

## Use

```bash
notify-tts on        # speak notifications
notify-tts off       # stop
notify-tts toggle
notify-tts status    # toggle state, effective config, counters
notify-tts test      # speak a test phrase
```

The daemon starts silent. Notifications are only spoken while the toggle is on,
and the toggle takes effect immediately without a restart.

## Configure

`~/.config/notify-tts/config.toml` is optional; every setting has a default.

```toml
[speech]
priority     = "message"   # all notifications spoken, in order
max_chars    = 200
include_body = false

[filter]
denylist       = ["spotify", "vesktop"]
dedup_seconds  = 10
max_per_minute = 12
```

## Troubleshooting

Nothing is spoken: check `notify-tts status` for the toggle, then
`notify-tts test` to confirm speech works at all, then
`journalctl --user -u notify-tts` for the skip reason.

A specific app is never spoken: check the denylist, and note that
notifications which update an existing one (progress bars) are skipped by
design.

## Uninstall

```bash
./uninstall.sh            # keeps your config
./uninstall.sh --purge    # removes it too
```
````

- [ ] **Step 8: Commit**

```bash
git add docs/install.md
git commit -m "docs: install, configuration and troubleshooting"
```

---

## Post-implementation

Not tasks, but worth doing once it has run for a few days:

- [ ] Tune the denylist against what actually turns out to be noisy
- [ ] Decide whether `include_body` is wanted for any particular app, which would need per-app configuration and is deliberately not built yet
- [ ] Consider a window-manager keybinding for `notify-tts toggle`

Deferred by decision: any status-bar integration, per-app allowlists, speaking notification actions, and anything to do with synthesis, which belongs to the output module.
