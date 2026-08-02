# Session report — 2026-08-02

Two projects shipped. Everything is committed; nothing is pushed.

---

## 1. memory-notify — pre-freeze warning (LIVE)

Replaced a RAM-percent timer that fired ~387 times a day and had been disabled
for being unbearable.

**Why it existed:** three whole-system OOM freezes in seven days, all
PrismLauncher's Java. The 02:49 event killed the desktop bar too.

**What changed**

| | Before | Now |
|---|---|---|
| Signal | RAM % (permanently ~90% here) | Headroom + PSI stall time |
| Alerting | every 60s while high | once per escalation, then silent |
| Poll rate | 60s fixed | 10s calm, 2s watching, 1s ramping |
| Names the hog | no | yes (`java` resolves to PrismLauncher) |
| If it dies | nothing restarts it | back in 5s |

- Service: `memory-notify.service`, active, `NRestarts=0`
- Code: `~/bin/memory-notify`, `~/bin/lib/memory-notify/{core,notify}.sh`
- Tests: 68 (36 core + 27 notify + 5 loop)
- Idle cost: 1.2s CPU per 15 min, 3.3 MB
- Spec: `~/docs/specs/2026-08-02-memory-notify-prefreeze-design.md`

**Also fixed**

- PrismLauncher gets `oom_score_adj=1000` via `WrapperCommand=choom -n 1000 --`,
  so Java is the kernel's first victim and the bar survives.
- noctalia now runs as a systemd unit with `Restart=on-failure`, so it heals
  after an OOM kill the way plasmashell does.

---

## 2. noctalia sysmon widget (LIVE)

Replaces the five KDE Plasma monitor applets the niri session lost.

- Bar: CPU, RAM, and all three PSI values, right of workspaces
- Panel (click): CPU temp, NVIDIA, INTEL, RAM, SWAP, DISK, three PRESSURE rows
- Both GPUs covered — NVIDIA via `nvidia-smi dmon`, Intel via KDE's own
  setcap'd `ksystemstats_intel_helper`, so no system-wide permission change
- GPU streams run only while the panel is open, stopped by exact PID
- Tests: 92, including a drift test
- Spec: `~/docs/specs/2026-08-02-noctalia-sysmon-widget-design.md`
- Plan: `~/docs/plans/2026-08-02-noctalia-sysmon-widget-plan.md`

PSI memory thresholds are deliberately identical to memory-notify's (5.00 /
10.00), so the bar turns amber at exactly the moment the notifier starts
considering a warning.

---

## THINGS THAT NEED YOU

### Decisions I made on your behalf

1. **Thresholds level "unknown".** The plan had an unreadable sensor render the
   same colour as a healthy one. I overrode it: unreadable now renders dimmed
   (`on_surface/0.4`) and distinct. An unknown *metric name* still returns
   "ok", since that is a programming error, not a sensor failure. Say if you
   want it as originally briefed.

2. **GPU streams are panel-scoped, not persistent.** The spec described them as
   living for the plugin's lifetime, mirroring KDE. The panel is their only
   consumer, so nothing now runs in the background. Spec updated to match.

### Genuinely blocked / impossible

3. **The hover tooltip cannot be built.** `ui.row` silently ignores a `tooltip`
   prop; `ui.button` accepts one but cannot hold children, so wrapping the bar
   contents empties it. Both tested live, both reverted. The panel is
   click-only. If you want hover, it needs an upstream feature request.

### Your call, no urgency

4. **20 unpushed commits.** `yadm push` when ready.

5. **`settings.toml` has your uncommitted change** — `hide_when_no_media = true`
   under `[widget.media]`. That is yours, not mine, so I left it alone.

6. **Two SHOULD-FIX-SOON items**, both pre-existing and low probability:
   - `parse.cpu_jiffies` returns `(0,0)` for garbage input at the library
     level. The widget guards it, but a future direct caller would inherit a
     plausible-lie bug. One-line fix: return nil.
   - `catalog.toml` duplicates `plugin.toml`'s id/name/version/plugin_api. A
     version bump must update both or they silently desync.

7. **`memory-notify` has two parked findings** from this morning: its
   idempotency guard is keyed on a tunable constant, and a malformed `avg10`
   returns 0 rather than the -1 "unavailable" sentinel. Neither is reachable
   today.

8. **Project B leftovers**: NVMe temperatures were dropped as out of scope (the
   sensors are recorded in the spec if you want them back), and the 12-widget
   right side of your bar was never decluttered — the new widget went on the
   left instead.

---

## Notes for anyone writing another noctalia plugin

The upstream docs were wrong five times. All five cost real time:

1. The manifest is `plugin.toml`, not `manifest.toml`.
2. Bar widgets use `[[widget]]`, not `[[bar_widget]]`. **A wrong key fails
   silently with zero entries** — no error at all.
3. `plugin_api` must be 3-16, not 1.
4. Entries are isolated VMs. There is **no `require` and no `load`**, so shared
   code must be inlined. A drift test keeps the copies honest.
5. `runStream` returns a plain bool, not a handle with `.stop()`. To stop a
   stream you must recover its PID out-of-band —
   `sh -c 'echo NOCTALIA_PID:$$; exec <cmd>'` works because `exec` makes `$$`
   the real process.

Also: `pkill -f` is unsafe for this. It substring-matches every process's argv
system-wide, so it would kill a command you ran yourself and could not tell one
monitor's panel from the other's.

---

## What the reviews caught

Across both projects, **17 defects** were found by review rather than by
debugging in production. Fourteen were mine, in the plans rather than the code.

The most valuable, in rough order:

- The watermark ratcheted down behind each reading, so a smooth decline from 9%
  to 2% produced **zero alerts** — silence through exactly the slide the tool
  exists to warn about.
- `pkill -f` would have killed the other monitor's GPU stream, and any
  `nvidia-smi` you ran yourself.
- A failed notification send outlived its episode, so recovery fired a "close
  something now" popup on a healthy machine.
- PSI becoming unreadable made the notifier fail **closed** — silent through
  any freeze — while the spec claimed the opposite.
- `nvidia-smi dmon`'s `mtemp` column reads `-` on this GPU; `tonumber` returned
  nil and `table.insert` silently dropped it, shifting every later column left.

The recurring theme, in nearly every case: **a plausible-but-false number where
"unreadable" should have been shown.** Both tools now fail closed to a visible
`--` instead.
