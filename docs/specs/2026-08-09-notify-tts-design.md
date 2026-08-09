# notify-tts: speaking desktop notifications

Date: 2026-08-09
Status: design, not yet implemented
Depends on: a working speech-dispatcher setup. Developed against speechd-neural
(`~/git/github.com/cadrianmae/speechd-neural`), but coupled to neither it nor any
particular engine.

## Context

Desktop notifications are visual. Anything that arrives while you are looking at
a different workspace, reading, or away from the screen is missed unless you go
back and check. Notification daemons solve persistence, not attention.

This reads notifications aloud, on demand: a global toggle turns speech on when
it is wanted and off when it is not, without touching per-application settings
anywhere else.

It is a consumer of speech-dispatcher, not a synthesiser. Every decision about
voices, engines, fallback and failure handling belongs to whichever output
module speech-dispatcher is configured with, and this project inherits it for
free.

## Prior measurements that shape the design

Taken against the live system on 2026-08-09 while building speechd-neural. They
are the reason several decisions below go the way they do.

SSIP priority semantics, measured with a burst of three messages:

| Priority | Behaviour | Effect |
| --- | --- | --- |
| `text` | first two cancelled at 0.18s | latest wins |
| `message` | queued: 0.98 / 1.73 / 2.70s | all spoken, in order |
| `important` | queued, never discarded | all spoken, outranks other speech |
| `notification` | first two dropped | latest wins, no backlog |

Also measured: a 392-character passage took 18.66s to speak, and speech-dispatcher
serialises requests, so one long utterance blocks everything behind it.

Two conclusions follow directly. Speech is slow relative to how fast
notifications can arrive, so length must be capped rather than trusted. And the
priority chosen determines whether a burst is fully spoken or partly discarded —
it is a design decision, not a detail.

## Decisions

| Decision | Choice | Reasoning |
| --- | --- | --- |
| Scope | Every desktop notification, filtered by denylist | Opt-out beats opt-in: an allowlist is silent until curated, and the failure mode of forgetting to add an app is missing the thing you cared about. |
| Trigger | One global toggle | No per-notification decision to make. Matches the actual use case, which is "read things to me for the next while". |
| Priority | `message` | All notifications are spoken, in order. Losing a notification silently is the failure this project exists to prevent, so coalescing is the wrong trade. The length cap and rate limit prevent the backlog this risks. |
| Spoken text | `"<app>: <summary>"` | The app name is what tells you whether to care and costs about a second. Bodies are omitted by default: they are frequently redundant with the summary, and a long one blocks the queue for tens of seconds. |
| Interface | CLI only | `notify-tts on\|off\|toggle\|status`. A keybinding is one line of window-manager config if wanted later. |
| Language | Python with PyGObject | Already present. `Gio.DBusConnection` gives the monitoring interface directly, with no new dependency. |

## Architecture

```
session bus
     |  BecomeMonitor, filtered to Notify calls
     v
[ monitor ]     private DBus connection, message filter
     |  Notification(app, summary, body, hints, replaces_id)
     v
[ filter ]      toggle, denylist, hint rules, dedup, rate limit
     |  accepted notifications only
     v
[ queue ]       bounded, single worker
     |
     v
[ speaker ]     spd-say -P message
```

Four parts, each testable alone:

- **monitor** owns the DBus mechanics and nothing else. It converts bus traffic
  into a plain `Notification` record and hands it on. It knows nothing about
  speech.
- **filter** is pure: a `Notification` plus configuration in, a decision out.
  This is where every rule lives, and it is where nearly all the tests are,
  because it needs no bus, no audio and no clock beyond an injected one.
- **queue** is bounded with a single worker. Bounded because speech is slower
  than notification arrival and unbounded growth is how the predecessor piper
  setup became unusable; single worker because speech-dispatcher serialises
  anyway, so concurrency buys nothing.
- **speaker** shells out to `spd-say`. Isolated so tests can substitute a
  recorder and assert on what would have been spoken.

### Monitoring

`Gio.DBusConnection.new_for_address_sync` opens a **private** connection, then
`BecomeMonitor` on `org.freedesktop.DBus.Monitoring` with the match rule:

```
type='method_call',interface='org.freedesktop.Notifications',member='Notify'
```

A private connection matters: `BecomeMonitor` puts the connection into a
monitor-only state, so sharing the process's normal bus connection would break
every other use of it.

The `Notify` signature is `(susssasa{sv}i)`, giving app name, replaces id, icon,
summary, body, actions, hints and expiry timeout.

This observes the user's own session bus only. It reads notification content, so
it is worth stating plainly that anything a notification contains — a message
preview, a one-time code — can be spoken aloud if its app is not on the
denylist. That is the point of the tool, and it is also why the denylist ships
non-empty.

## Filtering rules

Applied in order; the first that matches wins.

1. **Toggle off** — the state file is absent. Nothing is spoken. Checked per
   notification rather than cached, so the toggle takes effect immediately
   without a restart.
2. **Own notifications** — anything from `notify-tts` itself, and from
   `speechd-neural`. Speaking the TTS system's own degradation notice through
   the TTS system is a feedback loop at best and, when the reason for the notice
   is that speech is broken, silence at worst.
3. **Transient and OSD** — any notification carrying
   `x-canonical-private-synchronous` or an equivalent hint. These are volume and
   brightness overlays that fire continuously while a key is held.
4. **An update to an existing notification** — non-zero `replaces_id`. Progress
   notifications repeat many times per second; speaking each is unusable.
5. **Denylist** — configured application names, matched case-insensitively.
   Ships with the obvious offenders: media players, which emit a notification
   per track change.
6. **Empty summary** — nothing useful to say.
7. **Duplicate** — the same app and summary within a short window. Applications
   re-notify on focus changes and retries.
8. **Rate limit** — a maximum number spoken per minute, after which further
   notifications are dropped with a count logged. Prevents a misbehaving
   application from monopolising speech.

Everything surviving is spoken as `"<app>: <summary>"`, truncated to a
configurable maximum, defaulting to 200 characters — roughly ten seconds, chosen
against the measured 392 characters in 18.66s.

## Configuration

`~/.config/notify-tts/config.toml`, optional with working defaults, matching the
convention established in speechd-neural.

```toml
[speech]
priority     = "message"      # message | important | notification | text
max_chars    = 200
include_body = false
voice        = ""             # empty means the speechd default

[filter]
denylist       = ["spotify", "vesktop"]
dedup_seconds  = 10
max_per_minute = 12
skip_replaces  = true
```

State lives at `~/.local/state/notify-tts/enabled`, its presence meaning on.
A file rather than a config key, so toggling is atomic, needs no parser, and
cannot corrupt configuration.

## Failure handling

The governing rule differs from speechd-neural's. There, silence was the enemy.
Here, the daemon must **never break the desktop**: it is a passive observer, and
a notification that fails to be spoken must never prevent it being displayed.

- The monitor cannot block or modify notification delivery. It observes; it does
  not sit in the path.
- `spd-say` is invoked with a timeout. A hung speech system drops the utterance
  and logs, rather than stalling the queue.
- If the queue is full, the oldest pending notification is dropped and counted.
  Dropping the oldest rather than the newest keeps the most recent, which is the
  one most likely to still matter.
- Any unexpected exception in the worker is logged and the worker continues. A
  malformed notification must not kill the daemon.
- Logs go to stderr for the journal.
- `notify-tts status` reports: toggle state, notifications seen, spoken, and
  dropped with the reason, plus whether the monitor is connected. The counters
  are what make "why did it not read that one?" answerable.

## Deployment

- `~/.local/libexec/notify-tts/` for the daemon
- `~/.local/bin/notify-tts` for the CLI
- `~/.config/systemd/user/notify-tts.service`, `PartOf=graphical-session.target`
  with `Restart=always`, following the pattern already used for memory-notify
- installed by an `install.sh` mirroring speechd-neural's, with an uninstaller
  from the outset rather than deferred

## Testing

The bus, the clock and the audio device are all injected, so the great majority
of the suite runs with none of them.

| Layer | Test | Needs a bus? |
| --- | --- | --- |
| filter | every rule above, table-driven, including order-of-precedence between two matching rules | no |
| dedup and rate limit | injected clock, asserting the window boundaries rather than sleeping | no |
| formatting | app plus summary, truncation at the boundary, unicode | no |
| queue | bounded behaviour: fills, drops oldest, counts | no |
| speaker | recorder substituted for `spd-say`, asserting argv including the priority flag | no |
| monitor | a synthetic `Notify` message decoded into a `Notification`, without a real bus | no |
| end to end | a real notification via `notify-send`, spoken | yes, by hand |

The rule that must not regress, and so gets its own explicit test: **an app on
the denylist is never spoken, and `speechd-neural`'s own notifications are never
spoken**, because that one is a feedback loop rather than merely noise.

## Out of scope

- Reading notification bodies by default. The configuration allows it; the
  default does not.
- Any per-application allowlist UI, or integration with a status bar.
- Speaking notification actions, or acting on them.
- Any synthesis concern whatsoever. If speech sounds wrong, that is the output
  module's business.
