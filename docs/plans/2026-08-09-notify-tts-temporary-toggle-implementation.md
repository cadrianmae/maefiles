# notify-tts Temporary Toggle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `notify-tts on 30m` and `notify-tts off 1h` — a toggle that reverts to the opposite state when its window expires.

**Architecture:** The state file gains content, because presence-means-on cannot express "off until a time". It stores an absolute instant, and expiry is evaluated lazily on the existing per-notification toggle read, so there is no timer, no scheduled job and no daemon involvement.

**Tech Stack:** python 3.11+, pytest. No new dependencies.

**Design doc:** `~/docs/specs/2026-08-09-notify-tts-temporary-toggle.md`

**Base state:** 30 commits, 105 tests passing, daemon installed and running with the toggle off.

## Global Constraints

- Python 3.11 or later. PyGObject is the only permitted non-stdlib dependency; add nothing.
- No python version hardcoded anywhere; no absolute path to a particular user's home in code or defaults.
- The config file stays optional with working defaults.
- Nothing written outside `$HOME`. Logs to stderr for the journal, never files under `/tmp`.
- British English. No emoji — the tags `[OK]`, `[WARN]`, `[ERROR]` are the PRESCRIBED replacement and must be kept.
- Run tests as `PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 pytest -q`. The global `pytest` is broken by an unrelated stray `langsmith` plugin; that is not this project's bug and must not be "fixed" here.
- **Two clocks, deliberately.** The filter uses `time.monotonic` for dedup and rate limiting, which are relative windows. Expiry uses wall-clock `time.time`, because an absolute instant must survive a suspend or reboot. Do not unify them.
- **Migration matters.** The live state file today is created by `touch` and is therefore empty. Empty content must read as `on`, or upgrading would silently flip a user's toggle.

## File Structure

```
src/notify_tts/
    duration.py      NEW  parse a duration string to seconds
    state.py         REWRITTEN  state file format, lazy expiry, remaining time
    cli.py           MODIFIED  durations on on/off, remaining time in status
tests/
    test_duration.py NEW
    test_state.py    EXTENDED
    test_cli.py      EXTENDED
docs/
    install.md       MODIFIED  document the new commands
```

---

### Task 1: Duration parsing

**Files:**
- Create: `src/notify_tts/duration.py`
- Test: `tests/test_duration.py`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `parse_duration(text: str) -> int` — returns whole seconds
  - `DurationError(ValueError)`

A bare integer means minutes, because that is the common case and `on 30` should work. Suffixed units are accepted for everything else. Zero and negatives are rejected rather than accepted, because `on 0` is far more likely to be a typo than an intention, and silently expiring immediately would look like the feature is broken.

- [ ] **Step 1: Write the failing tests**

```python
# tests/test_duration.py
import pytest
from notify_tts.duration import DurationError, parse_duration


def test_bare_number_means_minutes():
    assert parse_duration("30") == 30 * 60
    assert parse_duration("1") == 60


def test_single_units():
    assert parse_duration("45s") == 45
    assert parse_duration("30m") == 30 * 60
    assert parse_duration("2h") == 2 * 60 * 60
    assert parse_duration("1d") == 24 * 60 * 60


def test_combined_units():
    assert parse_duration("1h30m") == 90 * 60
    assert parse_duration("1h30m15s") == 90 * 60 + 15


def test_units_are_case_insensitive():
    assert parse_duration("30M") == 30 * 60
    assert parse_duration("2H") == 2 * 60 * 60


def test_surrounding_whitespace_is_tolerated():
    assert parse_duration("  30m  ") == 30 * 60


@pytest.mark.parametrize("bad", [
    "",           # nothing
    "   ",        # whitespace only
    "m",          # a unit with no number
    "30x",        # unknown unit
    "abc",        # not a duration at all
    "-5",         # negative bare
    "-5m",        # negative suffixed
    "0",          # zero is a typo, not an instruction
    "0m",
    "1.5h",       # fractions are not supported; 90m says it better
    "30m20",      # trailing bare number after a unit is ambiguous
])
def test_rejections(bad):
    with pytest.raises(DurationError):
        parse_duration(bad)


def test_error_message_names_the_input():
    # The user typed it; the error should show it back to them.
    with pytest.raises(DurationError) as e:
        parse_duration("30x")
    assert "30x" in str(e.value)


def test_very_long_durations_are_allowed():
    # No arbitrary cap. A week off is a legitimate thing to want.
    assert parse_duration("7d") == 7 * 24 * 60 * 60
```

- [ ] **Step 2: Run to verify they fail**

Run: `PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 pytest tests/test_duration.py -q`
Expected: FAIL, `ModuleNotFoundError: No module named 'notify_tts.duration'`

- [ ] **Step 3: Implement**

```python
# src/notify_tts/duration.py
"""Parse a human-written duration into seconds.

A bare integer means minutes, because `on 30` is the common case and should
not require a suffix. Everything else is written with units.
"""

from __future__ import annotations

import re

UNITS = {"s": 1, "m": 60, "h": 60 * 60, "d": 24 * 60 * 60}

_BARE = re.compile(r"^\d+$")
_PAIRS = re.compile(r"(\d+)([smhd])")
_SHAPE = re.compile(r"^(?:\d+[smhd])+$")


class DurationError(ValueError):
    """The text is not a duration this understands."""


def parse_duration(text: str) -> int:
    """Return whole seconds. Raises DurationError on anything unusable."""
    raw = (text or "").strip().lower()

    if not raw:
        raise DurationError("no duration given")

    if _BARE.match(raw):
        seconds = int(raw) * UNITS["m"]
    elif _SHAPE.match(raw):
        # The shape check rejects trailing or leading junk that findall
        # would otherwise skip over silently, such as "30m20" or "x30m".
        seconds = sum(int(n) * UNITS[u] for n, u in _PAIRS.findall(raw))
    else:
        raise DurationError(f"not a duration: {text!r}")

    if seconds <= 0:
        raise DurationError(f"duration must be greater than zero: {text!r}")

    return seconds
```

- [ ] **Step 4: Run to verify they pass**

Run: `PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 pytest tests/test_duration.py -q`
Expected: 21 passed.

- [ ] **Step 5: Commit**

```bash
git add src/notify_tts/duration.py tests/test_duration.py
git commit -m "feat(duration): parse durations, bare numbers meaning minutes"
```

---

### Task 2: The state file gains content

**Files:**
- Rewrite: `src/notify_tts/state.py`
- Test: `tests/test_state.py` (extend; keep every existing test passing)

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `ToggleState(speaking: bool, until: float | None)` — frozen dataclass; `until` is the instant the current state ends, or None for indefinite
  - `read_state(path: Path | None = None, now: float | None = None) -> ToggleState`
  - `write_state(speaking: bool, until: float | None = None, path: Path | None = None) -> None`
  - `is_enabled(path: Path | None = None, now: float | None = None) -> bool` — unchanged signature plus an injectable clock
  - `set_enabled(value: bool, path: Path | None = None, until: float | None = None) -> None`
  - `toggle(path: Path | None = None, now: float | None = None) -> bool`
  - `state_path() -> Path` — unchanged
  - `remaining_seconds(state: ToggleState, now: float | None = None) -> float | None`

**The file format**, one line:

```
on                       on indefinitely
on until <epoch>         on now, off from that instant
off until <epoch>        off now, on from that instant
```

Absent, empty, unreadable or unrecognised means **off**, except that an *empty* file means **on** — that is the pre-existing `touch`-created format and must keep working, or upgrading silently flips the user's toggle. An `off` line is never written, because absence already means off and two representations of one state will eventually disagree.

- [ ] **Step 1: Write the failing tests**

Keep the existing tests in this file unchanged; add these.

```python
# append to tests/test_state.py
import pytest
from notify_tts.state import (
    ToggleState, is_enabled, read_state, remaining_seconds, set_enabled,
    toggle, write_state,
)

NOW = 1_000_000.0


def test_empty_file_means_on_for_backward_compatibility(tmp_path):
    # The pre-existing format was a touch-created empty file. Upgrading must
    # not silently flip a user's toggle.
    p = tmp_path / "enabled"
    p.write_text("")
    assert is_enabled(p, now=NOW) is True


def test_plain_on_line_means_on(tmp_path):
    p = tmp_path / "enabled"
    p.write_text("on\n")
    assert is_enabled(p, now=NOW) is True


def test_on_until_is_on_before_the_instant(tmp_path):
    p = tmp_path / "enabled"
    write_state(True, until=NOW + 60, path=p)
    assert is_enabled(p, now=NOW) is True
    assert is_enabled(p, now=NOW + 59) is True


def test_on_until_is_off_at_and_after_the_instant(tmp_path):
    # The boundary is deliberate: equal counts as expired.
    p = tmp_path / "enabled"
    write_state(True, until=NOW + 60, path=p)
    assert is_enabled(p, now=NOW + 60) is False
    assert is_enabled(p, now=NOW + 61) is False


def test_off_until_is_off_before_and_on_after(tmp_path):
    p = tmp_path / "enabled"
    write_state(False, until=NOW + 60, path=p)
    assert is_enabled(p, now=NOW) is False
    assert is_enabled(p, now=NOW + 60) is True


def test_setting_a_state_clears_any_previous_window(tmp_path):
    p = tmp_path / "enabled"
    write_state(False, until=NOW + 3600, path=p)
    set_enabled(True, path=p)
    assert read_state(p, now=NOW).until is None
    assert is_enabled(p, now=NOW + 7200) is True


def test_off_indefinitely_removes_the_file(tmp_path):
    p = tmp_path / "enabled"
    write_state(True, path=p)
    set_enabled(False, path=p)
    assert not p.exists()


def test_off_until_writes_a_file(tmp_path):
    # "off until" cannot be expressed by absence, so it must persist.
    p = tmp_path / "enabled"
    set_enabled(False, path=p, until=NOW + 60)
    assert p.exists()
    assert is_enabled(p, now=NOW) is False


@pytest.mark.parametrize("content", [
    "garbage",
    "on until",
    "on until nonsense",
    "off until",
    "until 123",
    "on until 1 2 3",
])
def test_malformed_content_reads_as_off(tmp_path, content):
    # A state file is not hand-edited, so a parse failure means something is
    # wrong and silence is the safer failure.
    p = tmp_path / "enabled"
    p.write_text(content)
    assert is_enabled(p, now=NOW) is False


def test_absent_file_is_off(tmp_path):
    assert is_enabled(tmp_path / "nope", now=NOW) is False


def test_read_state_reports_the_window(tmp_path):
    p = tmp_path / "enabled"
    write_state(True, until=NOW + 120, path=p)
    state = read_state(p, now=NOW)
    assert state.speaking is True
    assert state.until == NOW + 120


def test_read_state_reports_the_reverted_state_after_expiry(tmp_path):
    p = tmp_path / "enabled"
    write_state(True, until=NOW + 60, path=p)
    state = read_state(p, now=NOW + 61)
    assert state.speaking is False
    assert state.until is None, "an expired window is no longer in force"


def test_remaining_seconds(tmp_path):
    p = tmp_path / "enabled"
    write_state(True, until=NOW + 90, path=p)
    assert remaining_seconds(read_state(p, now=NOW), now=NOW) == 90
    assert remaining_seconds(ToggleState(True, None), now=NOW) is None


def test_toggle_clears_a_window(tmp_path):
    p = tmp_path / "enabled"
    write_state(True, until=NOW + 3600, path=p)
    assert toggle(p, now=NOW) is False
    assert read_state(p, now=NOW).until is None


def test_written_file_is_a_single_line(tmp_path):
    p = tmp_path / "enabled"
    write_state(True, until=NOW + 60, path=p)
    assert len(p.read_text().strip().splitlines()) == 1
```

- [ ] **Step 2: Run to verify they fail**

Run: `PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 pytest tests/test_state.py -q`
Expected: FAIL on the import of `ToggleState`, `read_state`, `remaining_seconds`, `write_state`.

- [ ] **Step 3: Implement**

```python
# src/notify_tts/state.py
"""The global toggle, with optional expiry.

The file's content encodes the state:

    on                  on indefinitely
    on until <epoch>    on now, off from that instant
    off until <epoch>   off now, on from that instant

An absent file means off. An EMPTY file means on: that is the format the
earlier touch-based implementation wrote, and upgrading must not silently
flip a user's toggle.

An `off` line is never written, because absence already means off and two
representations of one state will eventually disagree.

Instants are absolute wall-clock seconds rather than durations, so a window
behaves correctly across a suspend or a reboot. Expiry is evaluated lazily on
read: is_enabled() already runs on every notification, so no timer is needed
and there is nothing to drift or leak.
"""

from __future__ import annotations

import logging
import os
import time
from dataclasses import dataclass
from pathlib import Path

log = logging.getLogger(__name__)


@dataclass(frozen=True)
class ToggleState:
    speaking: bool
    until: float | None = None


def _xdg_state_home() -> Path:
    return Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state")


def state_path() -> Path:
    return _xdg_state_home() / "notify-tts" / "enabled"


def _parse(content: str) -> ToggleState | None:
    """Parse file content. Returns None when it is not understood."""
    text = content.strip().lower()

    if not text:
        return ToggleState(True)          # the pre-existing touch format
    if text == "on":
        return ToggleState(True)

    parts = text.split()
    if len(parts) == 3 and parts[0] in ("on", "off") and parts[1] == "until":
        try:
            return ToggleState(parts[0] == "on", float(parts[2]))
        except ValueError:
            return None
    return None


def read_state(path: Path | None = None, now: float | None = None) -> ToggleState:
    """The state as it stands right now, with any expired window resolved."""
    p = path or state_path()
    now = time.time() if now is None else now

    try:
        content = p.read_text()
    except FileNotFoundError:
        return ToggleState(False)
    except OSError as exc:
        log.warning("[WARN] could not read the toggle state: %s", exc)
        return ToggleState(False)

    parsed = _parse(content)
    if parsed is None:
        log.warning("[WARN] unrecognised toggle state, treating as off")
        return ToggleState(False)

    if parsed.until is not None and now >= parsed.until:
        # The window has elapsed; the state is now its opposite, indefinitely.
        return ToggleState(not parsed.speaking)
    return parsed


def write_state(
    speaking: bool,
    until: float | None = None,
    path: Path | None = None,
) -> None:
    p = path or state_path()

    if not speaking and until is None:
        p.unlink(missing_ok=True)         # absence already means off
        return

    p.parent.mkdir(parents=True, exist_ok=True)
    word = "on" if speaking else "off"
    line = word if until is None else f"{word} until {until:.0f}"
    p.write_text(line + "\n")


def is_enabled(path: Path | None = None, now: float | None = None) -> bool:
    return read_state(path, now).speaking


def set_enabled(
    value: bool,
    path: Path | None = None,
    until: float | None = None,
) -> None:
    """Set the state, discarding any window previously in force."""
    write_state(value, until, path)


def toggle(path: Path | None = None, now: float | None = None) -> bool:
    """Flip the effective state, clearing any window. Returns the new state."""
    new = not is_enabled(path, now)
    set_enabled(new, path)
    return new


def remaining_seconds(
    state: ToggleState,
    now: float | None = None,
) -> float | None:
    if state.until is None:
        return None
    now = time.time() if now is None else now
    return max(0.0, state.until - now)
```

- [ ] **Step 4: Run to verify they pass**

Run: `PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 pytest tests/test_state.py -q`
Then the full suite. Every one of the 105 existing tests must still pass — in particular the filter tests, which call `is_enabled` indirectly.

- [ ] **Step 5: Commit**

```bash
git add src/notify_tts/state.py tests/test_state.py
git commit -m "feat(state): store an expiry instant, resolved lazily on read"
```

---

### Task 3: Human-readable remaining time

**Files:**
- Modify: `src/notify_tts/duration.py`
- Test: `tests/test_duration.py`

**Interfaces:**
- Consumes: nothing.
- Produces: `format_remaining(seconds: float) -> str`

It lives beside the parser because they are inverses of each other, and keeping them together makes a mismatch obvious.

- [ ] **Step 1: Write the failing tests**

```python
# append to tests/test_duration.py
from notify_tts.duration import format_remaining


def test_formats_minutes():
    assert format_remaining(12 * 60) == "12m"


def test_formats_hours_and_minutes():
    assert format_remaining(64 * 60) == "1h 4m"


def test_formats_whole_hours_without_stray_minutes():
    assert format_remaining(2 * 60 * 60) == "2h"


def test_under_a_minute_is_worded_not_numeric():
    # "0m remaining" reads as though it has already expired.
    assert format_remaining(30) == "under a minute"
    assert format_remaining(1) == "under a minute"


def test_zero_and_negative_are_worded_the_same():
    assert format_remaining(0) == "under a minute"
    assert format_remaining(-5) == "under a minute"


def test_days_are_expressed_in_hours():
    # A window measured in days is unusual; hours stay comparable at a glance.
    assert format_remaining(25 * 60 * 60) == "25h"
```

- [ ] **Step 2: Run to verify they fail**

Run: `PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 pytest tests/test_duration.py -q`
Expected: FAIL, cannot import `format_remaining`.

- [ ] **Step 3: Implement**

```python
# append to src/notify_tts/duration.py
def format_remaining(seconds: float) -> str:
    """Render a remaining duration for a human reading `status`."""
    total = int(seconds)
    if total < 60:
        return "under a minute"

    hours, minutes = divmod(total // 60, 60)
    if not hours:
        return f"{minutes}m"
    if not minutes:
        return f"{hours}h"
    return f"{hours}h {minutes}m"
```

- [ ] **Step 4: Run to verify they pass**

Run: `PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 pytest tests/test_duration.py -q`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add src/notify_tts/duration.py tests/test_duration.py
git commit -m "feat(duration): render remaining time for a human"
```

---

### Task 4: The CLI accepts durations

**Files:**
- Modify: `src/notify_tts/cli.py`
- Test: `tests/test_cli.py` (extend; keep every existing test passing)

**Interfaces:**
- Consumes: `parse_duration`, `format_remaining`, `DurationError` (Tasks 1 and 3); `read_state`, `remaining_seconds`, `set_enabled`, `state_path`, `toggle` (Task 2).
- Produces: `on` and `off` accept an optional duration argument; `status` shows the window.

`toggle` deliberately takes no duration: it means "whatever it is now, make it the other thing", and a window on top of that is hard to predict.

- [ ] **Step 1: Write the failing tests**

```python
# append to tests/test_cli.py
def test_on_with_a_duration_sets_a_window(tmp_path, monkeypatch):
    p = tmp_path / "enabled"
    monkeypatch.setattr(cli, "state_path", lambda: p)
    assert cli.main(["on", "30m"]) == 0
    assert "on until" in p.read_text()


def test_off_with_a_duration_writes_a_file(tmp_path, monkeypatch):
    p = tmp_path / "enabled"
    monkeypatch.setattr(cli, "state_path", lambda: p)
    assert cli.main(["off", "1h"]) == 0
    assert "off until" in p.read_text()


def test_on_without_a_duration_is_indefinite(tmp_path, monkeypatch):
    p = tmp_path / "enabled"
    monkeypatch.setattr(cli, "state_path", lambda: p)
    cli.main(["on"])
    assert p.read_text().strip() == "on"


def test_a_bad_duration_exits_non_zero_and_changes_nothing(tmp_path, monkeypatch, capsys):
    p = tmp_path / "enabled"
    monkeypatch.setattr(cli, "state_path", lambda: p)
    assert cli.main(["on", "banana"]) != 0
    assert not p.exists(), "a rejected command must not half-apply"
    assert "[ERROR]" in capsys.readouterr().err


def test_the_confirmation_names_the_window(tmp_path, monkeypatch, capsys):
    p = tmp_path / "enabled"
    monkeypatch.setattr(cli, "state_path", lambda: p)
    cli.main(["on", "30m"])
    assert "30m" in capsys.readouterr().out


def test_status_shows_the_remaining_window(tmp_path, monkeypatch, capsys):
    p = tmp_path / "enabled"
    monkeypatch.setattr(cli, "state_path", lambda: p)
    cli.main(["on", "30m"])
    cli.main(["status"])
    out = capsys.readouterr().out
    assert "temporary" in out
    assert "remaining" in out
    assert "until:" in out


def test_status_without_a_window_is_unchanged(tmp_path, monkeypatch, capsys):
    p = tmp_path / "enabled"
    monkeypatch.setattr(cli, "state_path", lambda: p)
    cli.main(["on"])
    cli.main(["status"])
    out = capsys.readouterr().out
    assert "temporary" not in out
    assert "until:" not in out


def test_toggle_rejects_a_duration():
    # argparse should refuse it rather than silently ignoring it.
    with pytest.raises(SystemExit):
        cli.main(["toggle", "30m"])
```

- [ ] **Step 2: Run to verify they fail**

Run: `PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 pytest tests/test_cli.py -q`
Expected: failures on the new tests.

- [ ] **Step 3: Implement**

Replace the `on`, `off` and `status` handlers and their parser wiring. Keep `_daemon_status`, `_speak_test` and the `_status_line` helper exactly as they are.

```python
# in src/notify_tts/cli.py, replacing the on/off/status handlers

import time

from notify_tts.duration import DurationError, format_remaining, parse_duration
from notify_tts.state import (
    read_state, remaining_seconds, set_enabled, state_path, toggle,
)


def _window_from(args) -> tuple[float | None, str | None]:
    """Return (instant, human duration), or (None, None) for indefinite.

    Raises DurationError for anything unparseable, so the caller can refuse
    the whole command rather than half-applying it.
    """
    text = getattr(args, "duration", None)
    if not text:
        return None, None
    seconds = parse_duration(text)
    return time.time() + seconds, format_remaining(seconds)


def _set(args, speaking: bool) -> int:
    try:
        until, human = _window_from(args)
    except DurationError as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 2

    set_enabled(speaking, state_path(), until)

    if human:
        state = "spoken" if speaking else "silent"
        opposite = "silent" if speaking else "spoken"
        print(f"[OK] notifications {state} for {human}, then {opposite}")
    else:
        print(
            "[OK] notifications will be spoken" if speaking
            else "[OK] notifications are silent"
        )
    return 0


def _cmd_on(args, cfg) -> int:
    return _set(args, True)


def _cmd_off(args, cfg) -> int:
    return _set(args, False)


def _cmd_status(args, cfg) -> int:
    state = read_state(state_path())
    remaining = remaining_seconds(state)

    word = "on" if state.speaking else "off"
    if remaining is not None:
        word = f"{word} (temporary, {format_remaining(remaining)} remaining)"

    _status_line("toggle", word)
    if state.until is not None:
        _status_line("until", time.strftime("%H:%M on %d %b", time.localtime(state.until)))
    _status_line("daemon", _daemon_status())
    _status_line("state", str(state_path()))
    _status_line("priority", cfg.speech.priority)
    _status_line("max_chars", str(cfg.speech.max_chars))
    _status_line("denylist", ", ".join(cfg.filter.denylist) or "(empty)")
    return 0
```

And in `main()`, give `on` and `off` an optional positional argument, leaving `toggle` without one:

```python
    for name, help_text in (
        ("status", "show the toggle and effective configuration"),
        ("test", "speak a test phrase"),
    ):
        sub.add_parser(name, help=help_text)

    sub.add_parser("toggle", help="flip between on and off")

    for name, help_text in (
        ("on", "speak notifications, optionally for a limited time"),
        ("off", "stop speaking notifications, optionally for a limited time"),
    ):
        p = sub.add_parser(name, help=help_text)
        p.add_argument(
            "duration", nargs="?", default=None,
            help="e.g. 30 (minutes), 45s, 30m, 1h30m. Omit for indefinite.",
        )
```

- [ ] **Step 4: Run to verify they pass**

Run: `PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 pytest tests/test_cli.py -q`, then the full suite.

- [ ] **Step 5: Commit**

```bash
git add src/notify_tts/cli.py tests/test_cli.py
git commit -m "feat(cli): accept a duration on on and off, show it in status"
```

---

### Task 5: Live verification and documentation

**Files:**
- Modify: `docs/install.md`

**Interfaces:**
- Consumes: a working build.
- Produces: evidence the feature works against the installed daemon, and documentation for it.

The daemon is installed and running with the toggle off. Reinstall first so the installed tree picks up the changes, then verify. This will produce real speech.

- [ ] **Step 1: Reinstall and confirm nothing regressed**

```bash
./install.sh
notify-tts status
```

Expected: daemon running, toggle off, and the status block still aligned.

- [ ] **Step 2: Verify a temporary ON window end to end**

```bash
notify-tts on 2m
notify-tts status
notify-send -a "WindowTest" "Spoken inside the window"
```

Expected: the confirmation names the window, `status` shows `temporary` with remaining time and an `until:` line, and the notification is spoken. Report each verbatim.

- [ ] **Step 3: Verify expiry without touching anything**

Rather than waiting, prove expiry by writing a window that has already elapsed and confirming the state reads as reverted:

```bash
printf 'on until %s\n' "$(( $(date +%s) - 1 ))" > ~/.local/state/notify-tts/enabled
notify-tts status
notify-send -a "ExpiredTest" "Must not be spoken"
```

Expected: `status` reports `off` with no window, and nothing is spoken. Confirm from the journal that the skip reason was `disabled`.

- [ ] **Step 4: Verify a temporary OFF window**

```bash
notify-tts off 2m
notify-tts status
notify-send -a "SnoozeTest" "Must not be spoken"
```

Expected: silent, `status` shows the window and that it reverts to on.

- [ ] **Step 5: Verify the migration path**

This is the one that would bite a real upgrade. Recreate the old format and confirm it still means on:

```bash
notify-tts off
: > ~/.local/state/notify-tts/enabled     # the old touch-created format
notify-tts status
```

Expected: `toggle: on`. An empty file must not read as off.

- [ ] **Step 6: Leave it clean**

```bash
notify-tts off
notify-tts status
```

Expected: off, no window, daemon running.

- [ ] **Step 7: Document it**

Add to `docs/install.md`, in the Use section:

````markdown
Both `on` and `off` accept an optional duration, after which the toggle reverts
to the opposite state:

```bash
notify-tts on 30        # speak for 30 minutes, then go silent
notify-tts on 1h30m     # the same, written precisely
notify-tts off 45m      # stay silent for 45 minutes, then resume
```

A bare number means minutes. Units `s`, `m`, `h` and `d` can be combined.
`status` shows how long is left.

Expiry is evaluated when the next notification arrives rather than by a timer,
so a window costs nothing while nothing is happening, and one that elapses
while the machine is suspended is correctly expired on wake.
````

- [ ] **Step 8: Commit**

```bash
git add docs/install.md
git commit -m "docs: document temporary on and off windows"
```

---

## Post-implementation

- [ ] Consider a window-manager binding for `notify-tts on 30m`, the most likely everyday use
- [ ] Watch whether reverting to the opposite is the right default in practice, or whether restoring the previous state would suit better — the spec chose the opposite for predictability, and only use will settle it
