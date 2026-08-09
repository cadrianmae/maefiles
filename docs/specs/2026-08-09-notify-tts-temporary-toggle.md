# notify-tts: temporary toggle

Date: 2026-08-09
Status: design, not yet implemented
Extends: `~/git/github.com/cadrianmae/notify-tts/docs/design.md`

## Context

The toggle is currently permanent in both directions: speech is on until turned
off, or off until turned on. In practice both states are frequently wanted for a
bounded period — read things aloud while cooking, or stay quiet for the length of
a meeting — and a permanent toggle makes the user responsible for remembering to
undo it. Forgetting in one direction means missing notifications; forgetting in
the other means a machine that talks over a call.

This adds a duration to both `on` and `off`.

## Decisions

| Decision | Choice | Reasoning |
| --- | --- | --- |
| Directions | Both | `on 30m` for a bounded listening window, `off 1h` as a snooze. |
| Expiry behaviour | Revert to the opposite | `on 30m` becomes off; `off 1h` becomes on. Predictable without reading documentation, and the state file carries no history. |
| Duration syntax | Bare number means minutes; suffixes also accepted | `on 30` for the common case, `on 1h30m` when precision is wanted. |
| Status | Shows the remaining time | `status` exists to answer "is this thing on?"; a window it could not see would undermine that. |

## The state file, reconsidered

Today the state file's *presence* means on and its absence means off. That
cannot express "off until a time", because absence has no room for a payload.

The file therefore gains content. It holds a single line:

```
on
off until 1786412400
on until 1786412400
```

- absent, or unreadable, or unrecognised: **off**, the safe default
- `on`: on indefinitely
- `on until <unix timestamp>`: on now, off from that instant
- `off until <unix timestamp>`: off now, on from that instant

An `off` line is never written — absence already means that, and having two
representations of one state invites them to disagree.

Unix timestamps rather than durations, because a duration would need a start
time to be meaningful and would silently extend across a suspend or a reboot. An
absolute instant behaves correctly across both: a window set before suspending
has genuinely elapsed on wake.

**Expiry is evaluated lazily, never by a timer.** `is_enabled()` already runs on
every notification, so it compares the stored instant against the clock at that
moment. No timer, no scheduled job, no daemon involvement, and nothing to drift
or leak. A window that expires while no notifications arrive simply has no
observable effect, which is correct.

Malformed content is treated as off rather than raising. A state file is not a
configuration file: the user does not hand-edit it, so a parse failure means
something is wrong and silence is the safer failure.

## Interface

```
notify-tts on              # on indefinitely, unchanged
notify-tts off             # off indefinitely, unchanged
notify-tts on 30           # on for 30 minutes, then off
notify-tts on 1h30m        # on for 90 minutes, then off
notify-tts off 45m         # off for 45 minutes, then on
notify-tts toggle          # flips the current effective state, clearing any window
```

`toggle` deliberately takes no duration. It means "whatever it is now, make it
the other thing", and combining that with a window makes the resulting state
hard to predict.

Setting any state clears whatever window was previously in force. `on` after
`off 1h` means on indefinitely, not on until the old expiry.

Duration parsing accepts a bare integer as minutes, or a sequence of
number-and-unit pairs using `s`, `m`, `h` and `d`. It rejects, with a clear
message and a non-zero exit, anything else: negative values, zero, a bare unit,
an empty string, or unit ordering that suggests a typo. Zero is rejected rather
than treated as "expire immediately", because `on 0` is far more likely to be a
mistake than an intention.

## Status output

The existing aligned block gains the window on the toggle line and an explicit
expiry line, shown only when a window is in force:

```
toggle:    on (temporary, 12m remaining)
until:     15:47 today
daemon:    running
state:     ~/.local/state/notify-tts/enabled
...
```

Remaining time is rendered for a human — `12m remaining`, `1h 4m remaining`,
`under a minute remaining` — rather than as a raw count of seconds. When no
window is in force the toggle line reads exactly as it does today, so the common
case is unchanged.

## Failure handling

The governing rule is unchanged: this must never break the desktop, and a
temporary window must never become a way for speech to get stuck on.

- A clock that jumps backwards, for instance from an NTP correction, could
  extend a window. That is acceptable and self-correcting; the alternative,
  tracking monotonic time across process restarts, is not worth the complexity
  for a convenience feature.
- A clock that jumps forwards expires the window early, which is the safe
  direction.
- If the state file cannot be written, the command reports the failure and exits
  non-zero rather than claiming success. A user who is told speech is off, and
  is not, would be worse off than one who sees an error.

## Testing

All of it is testable with an injected clock and a temporary directory, exactly
as the existing state and filter tests are. No new hardware, bus or audio
dependency is introduced.

| Layer | Test |
| --- | --- |
| duration parsing | bare minutes, each unit, combinations, and every rejection case |
| state round trip | each of the three line forms is written and read back |
| expiry | before, exactly at, and after the instant, for both directions |
| clearing | setting any state discards a prior window |
| corruption | absent, empty, malformed, and a non-numeric timestamp all read as off |
| status rendering | the human-readable remaining time at several magnitudes, and its absence when no window is in force |

The boundary case deserves naming: a window whose instant equals the current
clock reading is **expired**. Choosing `<` rather than `<=` there is arbitrary
in isolation, but it must be pinned by a test so it cannot flip silently.

## Out of scope

- Any scheduler, timer unit or `at` job. Lazy evaluation makes them unnecessary.
- A window on `toggle`.
- Recurring or calendar-based schedules, for example "quiet every weekday
  morning". That is a different feature with a different shape, and if it is
  ever wanted it belongs in configuration rather than in a command.
- Notifying the user when a window expires. Speaking "notifications are now
  silent" as the last act before going silent is a contradiction, and a desktop
  notification about notifications is noise.
