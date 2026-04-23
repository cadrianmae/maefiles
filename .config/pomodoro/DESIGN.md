# Pomodoro Timer — Design

## Why
Replace the passive tmux-pomodoro-plus plugin (silent status bar, no logging)
with a CLI timer that actually interrupts, speaks, and records what was worked on.

## Core choice
[openpomodoro-cli](https://github.com/open-pomodoro/openpomodoro-cli) — plain-text
session storage, optional per-tomato tags and descriptions, state hooks at
`start` / `break` / `stop`, format-string status output (`%R`, `%c`, `%g`, `%d`, `%t`).

Not a daemon — state is file-based. A tmux pane running `cycle.sh` provides the
blocking "long process" role; tmux-resurrect keeps it alive across restarts.

## Paths
- State (hardcoded by tool): `~/.pomodoro/{settings, current, history/, hooks/}`
- Custom scripts + sounds: `~/.config/pomodoro/`
- Cache (task desc/tags bridge start→break/stop): `~/.pomodoro/_cache/`
- Daily notes target: `~/Documents/Computer Science TU856/Year 4/logs/YYYY-MM-DD.md`

## Components
- `orchestrator.sh` — invoked by hooks; plays sting, speaks voice line, logs to Obsidian
- `cycle.sh` — 4-tomato auto-advance cycle (work → break → … → long break)
- `watcher.sh` — polls status, fires milestone announcements at T-5 min and T-1 min
- `design-sounds.sh` — reproducibly regenerates the 4 sox stings
- `~/.pomodoro/hooks/{start,break,stop}` — thin shims that delegate to orchestrator

## Audio
**Voice:** `spd-say -w` (speech-dispatcher, defaults to cori — `en_GB-cori-high`)

**Stings** (sox, stereo 44.1kHz, lo-fi minimal aesthetic with timer character):

| File | Role | Design |
|---|---|---|
| `work-start.wav` | Focus session start | 2-bar swung triangle motif in C major over C4 tonic pedal bass |
| `break-start.wav` | Tomato complete, break begins | 4-bar chord progression Em – C – D – Em; swung triangle melody bars 1-3 (Idea 2 motif, 5-3-1-3 chord tones); bar 4 = staggered Em triad (E-G-B, 80ms offsets) with sine bell partials, 4s logarithmic decay |
| `all-done.wav` | Cycle complete | 4-bar progression C – F – G – C; same swung triangle motif; bar 4 = staggered C-major triad (C-E-G) with sine bell partials, 4s logarithmic decay |
| `milestone.wav` | T-5 / T-1 min warning | 6 swung triangle ticks (1800Hz long / 1500Hz short), clock-pendulum feel, subtle bass thumps on long positions |

Swing: 2:1 ratio (long note 0.33s, short 0.17s per pair).
All sounds: chord bell chords normalised `-1` (max loudness, no clip), final output
`norm -6` after reverb, 1.5s trailing silence so reverb tail decays naturally.

## Voice content
Each state transition speaks a composed line:
- **start**: "Focus session started. Tomato N of 4. Task: DESC. X of GOAL done today."
- **break**: "Tomato complete. Take a break. Finished: DESC. X of GOAL done today."
- **stop**: "Session ended. X of GOAL done today."
- **milestones**: "5 minutes remaining." / "One minute remaining."

`DESC`/`TAGS` caching: orchestrator saves them on `start` hook and restores on
`break`/`stop` (the pomodoro's state has switched by then, so live status is empty).

## Obsidian logging
Appends under a `## Pomodoros` heading in today's daily note. Creates both the
note file and the heading if missing.

Example entries:
```
## Pomodoros
- 10:00 started — write section 3.3 [fyp]
- 10:25 complete — write section 3.3 (3/8)
- 11:40 session ended (7/8)
```

## Daily workflow
```bash
cycle.sh "write §3.3" -t fyp    # in a dedicated tmux pane — blocks through full cycle
pomodoro status                  # from any other shell
pomodoro history --json | jq .   # structured query
```

## tmux status indicator
tmux2k plugin at `~/.tmux/plugins/tmux2k/plugins/pomodoro.sh` polls
`pomodoro status -f "%R/%L %c%!g"` and prints e.g. `🍅 18/25 2/8` when active,
empty when idle. Added to `@tmux2k-right-plugins` as `pomodoro`.

## Claude Code integration
Hook at `~/.claude/hooks/pomodoro-context.sh` emits current pomodoro state into
Claude's context on `SessionStart` (always) and `UserPromptSubmit` (15-min cooldown).
