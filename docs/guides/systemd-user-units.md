# systemd --user units

User-scoped systemd services and timers tracked in this repo. All run unprivileged under `cadrianmae`; none require root. Manage via `systemctl --user` and `journalctl --user`.

## Inventory

| Unit | Type | Purpose | Schedule |
|---|---|---|---|
| `build-memory.service` | oneshot | Rebuild per-project Claude memory summaries | via `build-memory.timer` |
| `build-memory.timer` | timer | Daily 23:00 + 15 min jitter; catches up missed runs | `OnCalendar=daily` |
| `memory-notify.service` | oneshot | Desktop notification when RAM > 85 % | via `memory-notify.timer` |
| `memory-notify.timer` | timer | Every 1 min after boot | `OnUnitActiveSec=1min` |
| `piper-daemon.service` | exec | Persistent Piper TTS model cache (Unix socket) | manual (`enable --now`) |
| `todoist-ai.service` | simple | Long-running Todoist AI agent | `Restart=on-failure` |
| `yadm-secrets-check.service` | oneshot | Check `pass` entries against manifest TTL; writes `~/.cache/yadm-secrets-stale` + sends notification when stale | via `yadm-secrets-check.timer` |
| `yadm-secrets-check.timer` | timer | Daily + 15 min jitter; persistent (catches up after laptop-was-off) | `OnCalendar=daily` |

## Common operations

```bash
# Enable + start
systemctl --user enable --now <unit>

# Status / logs
systemctl --user status <unit>
journalctl --user -u <unit> -n 50 --no-pager
journalctl --user -u <unit> -f

# Force-run a oneshot now (timer-driven units)
systemctl --user start <unit>

# List all timers + next-fire
systemctl --user list-timers --all

# Reload after editing a unit file
systemctl --user daemon-reload
```

## Per-unit detail

### `build-memory.{service,timer}`

Runs `~/.local/bin/build-memory --all` daily at 23:00. Reads the last 30 days of Claude transcripts per project, writes 200–300 word summaries to each project's `.claude/memory.md`. Aggregated into a single Claude API call. Low priority: `Nice=19` + `IOSchedulingClass=idle`.

### `memory-notify.{service,timer}`

Polls `free` every minute. Emits a desktop notification when RAM crosses the warning threshold. Pairs with the watchdog scripts in [Memory management](memory-management.md).

### `piper-daemon.service`

Keeps Piper TTS models resident in RAM. Listens on `piper-daemon.socket`. Required by `spd-say` for low-latency voice synthesis. See [Audio stack](audio.md) for the full speech-dispatcher chain.

### `todoist-ai.service`

`npx @doist/todoist-ai` long-running agent. Network-dependent — waits on `network-online.target`. Restarts on failure with a 10 s back-off.

### `yadm-secrets-check.{service,timer}`

Daily TTL audit of secrets in `pass`. Runs `~/bin/yadm-refresh-secrets --notify-only`:

- Does **not** prompt for `bw` unlock — non-interactive only.
- Writes `~/.cache/yadm-secrets-stale` if stale entries exist.
- Triggers a desktop notification.
- The user runs `~/bin/yadm-refresh-secrets` interactively when they see the nudge.

`Persistent=true` so a missed window (laptop off overnight) catches up on next boot. `RandomizedDelaySec=900` keeps machines from hitting BWS in lockstep.

## Where they live

```
~/.config/systemd/user/
  build-memory.service       build-memory.timer
  memory-notify.service      memory-notify.timer
  piper-daemon.service
  todoist-ai.service
  yadm-secrets-check.service yadm-secrets-check.timer
```

## Related

- [Audio stack](audio.md) — `piper-daemon.service` is the cache layer for `spd-say`
- [Memory management](memory-management.md) — `memory-notify.*` is the alert pipeline
- [Loading keys](../runbooks/loading-keys.md) — interactive counterpart to `yadm-secrets-check`
