# memory-notify: pre-freeze warning

Date: 2026-08-02
Status: Implemented 2026-08-02
Supersedes: the threshold-per-resource `memory-notify` timer (disabled 2026-08-02 02:45)

## Problem

The machine thrash-locks and the kernel OOM killer takes processes down with it.
Three global OOM events in seven days, all the same offender:

| Date | Killed | Size |
|---|---|---|
| 2026-07-28 16:04 | `2.1.220` (PrismLauncher Java) | 7.2 GB anon-rss |
| 2026-07-31 18:20 | `2.1.220` (PrismLauncher Java) | 8.0 GB anon-rss |
| 2026-08-02 02:49 | `java` (PrismLauncher) | 3.3 GB anon + 5.3 GB shmem |

The 2026-08-02 event also killed `noctalia`, the desktop bar, leaving no shell.

The goal is a warning early enough to close applications before the freeze, so
the user does not lose work. It is not a memory gauge.

### Why the old design failed

The previous script alerted on RAM percent with four independent notification
streams (RAM warning/critical, swap warning/critical). On a 16 GB box with
zswap, 85-91% RAM is the steady state, not an event, so it fired constantly:
387 timer invocations per day, with a 1-minute critical cooldown meaning a
notification every minute during any sustained busy period.

Two root causes:

1. **Wrong signal.** RAM percent is always high here. It does not distinguish
   "lots of cache" from "about to die".
2. **Level-triggered.** It re-notified whenever the value was still high,
   rather than when the situation changed.

A third problem was fatal to the actual goal: the timer polled every 60 s,
while the Java process ramps in seconds. The old design could first notice
*during* the freeze, when the desktop is already unresponsive.

## Requirements

Gathered 2026-08-02, Q1-Q6.

| # | Requirement |
|---|---|
| R1 | Prompt action ("close something") **and** provide ambient awareness |
| R2 | One notification that escalates in place; never stacks |
| R3 | Silent while sustained-bad; speaks again only on measurable worsening |
| R4 | Never suppressed (no do-not-disturb, no quiet hours, no focus mode) |
| R5 | Signal is combined headroom gated by PSI, not RAM percent |
| R6 | Must name what to close - a generic "pressure high" is not actionable |
| R7 | Must warn before the freeze, not during it |

R6 emerged from the user's own framing: "this should get me to start closing
some applications." An alert that cannot name the offender fails its purpose.

## Approach

Chosen: **bash service with an adaptive-rate loop.**

Rejected alternatives:

- **`psi-notify`** (packaged, Fedora 1.3.1). Zero maintenance and true PSI
  triggers, but its message cannot name the offending process (fails R6) and
  it has no silent-until-worse semantics (fails R3).
- **bash + C `poll()` helper.** Same notification as the chosen approach with
  sub-second rather than 1 s latency - a gain that does not change the outcome
  when the ramp takes tens of seconds. Costs a compiled binary in a
  yadm-tracked dotfiles repo plus a build step per machine. Parked for
  possible later exploration.

## Architecture

| Path | Role |
|---|---|
| `~/.local/bin/memory-notify` | Long-running bash loop: read, decide, notify |
| `~/bin/lib/memory-notify/core.sh` | Pure decision logic: parsing, tier classification, the `decide` state machine |
| `~/bin/lib/memory-notify/notify.sh` | Notification rendering: body text, consumer naming, `notify-send` argument assembly |
| `~/.config/systemd/user/memory-notify.service` | `Type=exec`, `Restart=always`, `Slice=session.slice` |
| `~/.config/systemd/user/memory-notify.timer` | **Deleted** - replaced by the service |

The unit is `WantedBy=graphical-session.target`, deliberately *not* bound to
`niri.service`. Unlike the bar, a memory warning is not desktop-specific and
should work under Plasma too. It requires only a notification daemon.

### Adaptive rate

```
headroom > 25%    ->  sleep 10s     calm
headroom <= 25%   ->  sleep 2s      watching
headroom <= 15%   ->  sleep 1s      ramp in progress
```

One process performing two `/proc` reads per tick, versus the old design
spawning a fresh bash plus `free` plus four `awk` calls every 60 s. Cheaper at
idle and roughly 60x faster when it matters.

The rate thresholds (25%, 15%) are deliberately *above* the alert thresholds
(20%, 10%). The loop speeds up shortly before it has anything to say, so the
transition into WARNING or CRITICAL is already being sampled at 2 s or 1 s
rather than being discovered up to 10 s late. They are not meant to match.

## Signal

```
headroom% = (MemAvailable + SwapFree) / (MemTotal + SwapTotal) x 100
psi       = /proc/pressure/memory -> full avg10
```

`avg10`, not `avg60`: on 2026-08-02 `full avg60` only reached 12.98 well into
the event, whereas `avg10` moves within seconds. For a pre-freeze warning the
fast average is the point.

PSI is the gate that keeps false alarms out. A healthy system sits near zero
even at high RAM usage, so requiring real stall time means the alert carries
information when it arrives.

| Tier | Entry condition |
|---|---|
| WARNING | headroom <= 20% **and** `full avg10` >= 5 |
| CRITICAL | headroom <= 10% **and** `full avg10` >= 10 |
| OK | only via the recovery gate below - **not** simply "headroom > 20%" |

Tiers are sticky downward: once WARNING or CRITICAL is entered, the state
never falls back merely because a reading improved. The only route back to OK
is the recovery gate (`headroom >= 30% and full avg10 < 2`). This is what
makes the hysteresis real - without it a reading of 21% would silently reset
to OK and the next dip to 20% would alert all over again.

Validation against the 2026-08-02 event: at 02:35 the machine was at 7.5%
headroom with `full avg60` 3.32; the freeze hit at 02:49. These thresholds
would have raised CRITICAL around 02:35, giving roughly 14 minutes of warning.

These numbers are derived from a single night's data and are the most likely
part of this design to need tuning in use.

## State machine

```
   OK --headroom<=20 & psi>=5--> WARNING --headroom<=10 & psi>=10--> CRITICAL
    ^                                |                                  |
    +---------- headroom>=30 & psi<2 +----------------------------------+
                  (recovery, with hysteresis)
```

- Alert **only on tier increase**. Sitting at CRITICAL for an hour is silent.
- **Degradation exception:** the script records the headroom at the LAST ALERT
  (the watermark). If headroom falls 5 further percentage points below that
  watermark, it alerts again and the watermark moves to the new value. So
  10% -> 5% -> 1% produces three alerts; 10% wobbling to 9% produces none.

  The watermark tracks the last alert, NOT the lowest reading seen. This was
  changed by user ruling on 2026-08-02 after review found the original wording
  ("worst headroom seen this episode") produced silence exactly when it mattered:
  on a smooth decline the watermark ratcheted down behind each reading, so every
  individual step was under 5 points and no alert ever fired. Traced on the real
  decline 22 -> 19 -> 15 -> 11 -> 9 -> 7 -> 4 -> 2, the old rule alerted twice
  and then went quiet from 9% all the way to 2%; the current rule alerts at 19,
  11, 9 and 4. Measuring from the last alert also makes alerting independent of
  where poll ticks happen to land.
- **Hysteresis:** recovery requires 30% while onset requires 20%, so a system
  hovering at the boundary does not re-alert repeatedly.
- On recovery: clear the watermark, close the bubble, re-arm for the next
  episode.

## Notification

Two kinds of send, both writing to the same notification ID:

| | Trigger | Sound | Purpose |
|---|---|---|---|
| Alert | Tier increase, or 5-point degradation step | yes | Get attention |
| Refresh | Every ~5 s while CRITICAL | suppressed | Keep numbers honest |

The refresh carries `--hint=string:suppress-sound:true` and does not touch the
alert state machine; it only rewrites the body. The bubble is therefore always
live but only speaks when things genuinely worsen - satisfying R1's two halves
(action and awareness) simultaneously.

"Every ~5 s" means *at least* 5 s since the last refresh, checked each tick.
Because the tick rate varies (1-10 s), the refresh is time-gated rather than
tick-counted; at a 10 s tick it simply happens every tick.

Suppressing the refresh *sound* is not suppression in the R4 sense. R4 forbids
withholding an alert because of focus mode, quiet hours or fullscreen; the
alert itself is never withheld. The refresh is a body rewrite, not an alert.

Only CRITICAL is refreshed. A WARNING bubble expires after 10 s and is not
kept current - deliberately, since WARNING means "worth knowing", not "act
now", and a persistent bubble at that level would be the ambient clutter this
redesign exists to remove. If pressure worsens, CRITICAL takes over and
becomes persistent.

### Verified server behaviour

Tested against noctalia 5.0.0 (spec 1.2) on 2026-08-02:

```
--expire-time=0 is REQUIRED    urgency=critical alone silently expires
--replace-id quiet-swaps       verified visually: no re-pop, no re-animation
```

The first is a genuine deviation from the freedesktop spec, which says
critical notifications should persist until dismissed. Without the explicit
flag the sticky bubble silently disappears.

### Content

WARNING - `urgency=normal`, expires after 10 s:

```
Memory getting tight
Usable: 2.8GB (18%)   stall: 6.1%
Biggest: java (PrismLauncher)  9.7GB
```

CRITICAL - `urgency=critical`, `--expire-time=0`:

```
Close something now

Usable memory:  1.2GB (7%)
Stalled:        18.4% of last 10s

java (PrismLauncher)              9.7GB
vesktop                           0.5GB
zen                               0.4GB
```

### Naming generic runtimes

`ps` reports `java`, which is not actionable. The script inspects the command
line for a recognisable path component (`.../PrismLauncher/java/...` ->
`PrismLauncher`) and falls back to the raw process name. A small mapping table
covers the usual runtimes: java, electron, python3, node.

## Error handling

| Failure | Behaviour |
|---|---|
| No notification daemon yet at login | `notify-send` fails -> **do not consume the tier transition**; retry next tick |
| `/proc/pressure/memory` unreadable (absent, unmounted, permission change, PSI disabled) | `parse_psi_full_avg10` returns a `-1` sentinel; `classify_tier` and the recovery gate in `decide` treat a negative psi as "no PSI gate available" and classify on headroom alone. The loop tracks availability per tick and logs `[WARN]` only on a transition (available -> unavailable, or back), not once at startup and not every tick |
| `free` / `/proc` parse failure | Skip the tick; do not crash, do not change state |
| `notify-send` returns empty ID | Treat as failure, retry next tick |
| Script crashes | `Restart=always` with a start limit so a broken script fails visibly |

The first row matters most: this service will usually start before noctalia is
ready, so the first notification of a session must survive a failed send.

## Testing

### Layer 1 - logic tests

Readings injected via environment override, asserting notification counts. No
risk, and the state machine is the entire risk surface.

```
OK sustained                    -> 0 notifications
OK -> WARNING                   -> 1
WARNING sustained x20 ticks     -> 0 more
WARNING -> CRITICAL             -> 1
CRITICAL sustained x50 ticks    -> 0 more
CRITICAL, headroom -5pts        -> 1   (degradation)
CRITICAL, headroom -4pts        -> 0   (below step)
recovery at 30%, then onset     -> 1   (re-armed)
hovering at 25%                 -> 0   (hysteresis holds)
PSI file missing                -> headroom-only, still works
notify-send fails then succeeds -> 1, not 0
```

Written before the implementation.

### Layer 2 - one controlled live test

```bash
systemd-run --user --scope -p MemoryMax=6G \
  stress-ng --vm 1 --vm-bytes 5G --timeout 60s
```

`MemoryMax` confines the balloon to its own cgroup so it cannot take the
desktop down. Run once, deliberately, with work saved.

This validates plumbing - that real readings drive real notifications - and
will likely only reach WARNING, since a capped 5 GB balloon will not push a
15.8 GB machine below 10% headroom. Reaching CRITICAL safely is not attempted:
the tier logic is covered exhaustively by Layer 1, which is why Layer 1 is
written first and carries the weight.

## Out of scope

Completed separately on 2026-08-02, before this spec:

- **PrismLauncher `oom_score_adj`.** `WrapperCommand=choom -n 1000 --` in
  `prismlauncher.cfg` makes Java the kernel's guaranteed first victim, so the
  bar and other applications survive. Previously every process in the session
  sat at 200, leaving the kernel to rank purely by footprint.
- **noctalia self-healing.** `noctalia.service` with `Restart=on-failure`,
  `BindsTo=niri.service`, `WantedBy=niri.service`, `Slice=session.slice`.
  Verified by SIGKILL. Niri-only by construction; never starts under Plasma.
  `spawn-at-startup "noctalia"` commented out in `conf.d/startup.kdl`.

Deferred:

- **Project B: noctalia bar system monitors.** Recreate the Plasma
  `systemmonitor.memory` / `.diskusage` widgets in the noctalia bar, and
  declutter `[bar.default] end` (currently 12 widgets on the right, with
  `start` and `center` both empty). Its own spec.
- **`earlyoom` backstop.** Would kill the hog before the kernel thrash-locks,
  helping when the user is away from the keyboard. Rejected for now under Q1
  (no automation), but worth revisiting.
- **Lowering `oom_score_adj` for niri and noctalia.** Requires root; the
  `choom` wrapper covers the realistic case.
- **Approach C** (bash + C `poll()` helper) as a later exploration.

## Notes

- `/proc/pressure/memory` is mode 0666 and `CONFIG_PSI=y` with
  `PSI_DEFAULT_DISABLED` unset, so unprivileged PSI trigger registration is
  available if approach C is ever revisited.
- `systemd-oomd` is active but did not catch any of the three events; the
  kernel OOM killer fired each time.
- PrismLauncher's `MaxMemAlloc=6144` (6 GB heap) does not bound the problem:
  the killed process showed 9.75 GB RSS, 5.3 GB of it shmem.
