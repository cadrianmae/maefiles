# noctalia: unified system monitor widget

Date: 2026-08-02
Status: Approved, not yet implemented
Related: `2026-08-02-memory-notify-prefreeze-design.md` (shares the PSI thresholds)

## Problem

The KDE Plasma session carried five separate system monitor applets. The niri
+ noctalia session has none, so the machine's state is invisible until
something goes wrong. This matters more than usual here: three whole-system
OOM freezes in the week to 2026-08-02, one of which killed the desktop bar.

The five KDE applets and their sensors, as configured in
`.config/plasma-org.kde.plasma.desktop-appletsrc`:

| Applet | Face | Sensors |
|---|---|---|
| Memory Usage | piechart | `memory/physical/used`, `usedPercent` |
| Memory Usage | piechart | `memory/swap/usedPercent`, `used`, `total` |
| Disk Usage | piechart | `disk/<uuid>/usedPercent`, `used`, `free` |
| Pressure | barchart | `pressure/{cpu,memory,io}/{some,full}60Sec` |
| CPU & GPU | linechart | `cpu/all/usage`, `gpu0/usage`, `gpu1/usage`, temps, `usedVram` |

Goal: one widget carrying the same information, better looking, in the niri
bar.

## Requirements

Gathered 2026-08-02.

| # | Requirement |
|---|---|
| R1 | One widget, not several - "lump them into one" |
| R2 | Same metrics as the KDE set, including PSI and temperatures |
| R2a | NVMe drive temperatures are an ADDITION, not KDE parity - the KDE disk applet showed no temperature. Included because "also include temps" was asked for and hwmon makes them free to read. |
| R3 | Icons rather than text labels |
| R4 | Bar shows CPU, RAM and PSI; everything else behind an interaction |
| R5 | All three PSI values (cpu/mem/io) visible in the bar, compact |
| R6 | Placed in `start`, immediately right of `workspaces` |
| R7 | Custom plugin for all metrics, for visual cohesion - not built-in sysmon plus a plugin |

## Approach

**A single custom Luau plugin.** Reads `/proc` and `/sys` directly for
everything it can; one persistent `nvidia-smi` stream for GPU.

### Why not the built-in `sysmon` widget

noctalia ships `sysmon` and `resources` widgets exposing `cpu_usage`,
`cpu_temp`, `gpu_usage`, `gpu_temp`, `gpu_vram`, `ram_pct`, `swap_pct`,
`disk_free`, `disk_free_pct`, each with `_activity_threshold` and
`_critical_threshold` keys.

They cover eight of the nine metrics but have **no PSI and no io support**.
PSI is not an optional extra here: it is the signal `memory-notify` alerts on,
and the KDE bar carried a dedicated Pressure widget, so it is actively
watched. Mixing a built-in widget with a custom one for the missing metric
was rejected (R7, R1) - two widgets that look different defeats the purpose.

### Why GPU needs a subprocess

Verified on this hardware:

```
/sys/class/drm/card0/device   driver=nvidia   no gpu_busy_percent, no utilization
/sys/class/drm/card1/device   driver=i915     only gt_act_freq_mhz (frequency, not usage)
/sys/class/hwmon/*            no nvidia node  -> no GPU temp
```

GPU usage, temperature and VRAM are not readable from `/proc` or sysfs on this
machine. KDE solves this the same way, confirmed by reading
`ksystemstats/plugins/gpu/NvidiaSmiProcess.cpp` upstream:

```
nvidia-smi dmon -d 2 -s pucm
```

`dmon` monitoring mode, 2-second interval, power/utilisation/clocks/memory.
The QProcess is started once via `ref()` and kept alive, with
`readyReadStandardOutput` parsing line by line - one long-lived process, not a
fork per sample. This design mirrors it exactly.

`noctalia.runStream(cmd, onLine)` provides the same shape: a long-lived shell
command with a per-line callback, terminated automatically on reload, entry
removal or plugin stop.

The Nitro 5's dGPU cannot power off under Linux (no `_PR3` in firmware), so
holding `nvidia-smi dmon` open costs no extra wakeups. On an Optimus laptop
where the dGPU *can* sleep, this trade would need revisiting.

### Known gap: the Intel iGPU

This machine has two GPUs and the KDE applet showed both (`gpu0/usage` and
`gpu1/usage`). `nvidia-smi` covers only the NVIDIA card. The Intel iGPU
(`card1`, i915) exposes no usage percentage in sysfs - only
`gt_act_freq_mhz`, a clock frequency. Real i915 utilisation requires the perf
interface via `intel_gpu_top`, which needs elevated `perf_event_paranoid` or
`CAP_PERFMON`.

So this design covers ONE of the two GPUs, and does not fully meet R2. Three
ways to close it, none free:

1. **Accept it.** Show the NVIDIA GPU only. The dGPU is the one that matters
   for load and heat; the iGPU drives the display and rarely saturates.
2. **Frequency as a proxy.** Show `gt_act_freq_mhz` scaled between
   `gt_min_freq_mhz` and `gt_max_freq_mhz`. No permissions needed, but it is
   not utilisation and will not match what KDE showed.
3. **`intel_gpu_top -l -s 2000` as a second stream.** True utilisation,
   matching KDE, but requires relaxing `perf_event_paranoid` system-wide -
   a real security trade for a bar widget.

Option 1 is the default unless overridden. This is called out rather than
silently dropped, since R2 asked for KDE parity.

## Data sources

| Metric | Source | Cost per tick |
|---|---|---|
| CPU usage | `/proc/stat` jiffy delta | file read |
| CPU temp | hwmon where `name=coretemp` -> `temp1_input` | file read |
| RAM % + used/total | `/proc/meminfo` | file read |
| Swap % + used/total | `/proc/meminfo` | file read |
| PSI cpu / mem / io | `/proc/pressure/{cpu,memory,io}` | file read |
| NVMe temps | hwmon where `name=nvme` (two present) | file read |
| GPU usage / temp / VRAM | `nvidia-smi dmon -d 2 -s pucm` via `runStream` | none - one process, lifetime |
| Disk free | `df` via `runAsync`, every 60 s | one fork per minute |

Poll interval 2000 ms via `noctalia.setUpdateInterval`, matching `dmon -d 2`
so the bar and GPU figures advance together rather than drifting.

Disk free is the one metric with no `/proc` source - it needs `statvfs`, which
the Luau API does not expose. It changes slowly, so a 60-second `runAsync` is
proportionate.

**hwmon numbering is not stable across boots.** It is assigned in probe order;
`coretemp` was `hwmon8` on 2026-08-02 but may differ tomorrow. The plugin
discovers sensors by reading each `name` file at startup, and re-discovers if
a cached path stops resolving. Never hardcode a hwmon index.

## Layout

Placement: `[bar.default] start`, appended after `workspaces`, giving
`[launcher, active_window, wallpaper, workspaces, <widget>]`. The `end` list
(13 widgets) is untouched.

```
BAR
+----------------------------------------------------+
| launcher  window  wallpaper  workspaces  [WIDGET]   |
+----------------------------------------------------+

  [WIDGET] = (cpu) 12%   (ram) 58%   (act) 0.1/0.3/0.0
                                            cpu/mem/io
```

Icons come from the bundled Tabler set via `ui.glyph`: `cpu`,
`device-sd-card` (RAM), `activity` (PSI), `database` (disk),
`temperature`.

### Interaction

Bar widgets cannot show a rich hover popup. The API offers `ui.button`'s
`tooltip` (a plain string) and `noctalia.togglePanel()` for a separately
declared panel. So:

- **Hover** - one-line tooltip summary.
- **Click** - panel with the full table.

Panel contents:

```
+-----------------------------------------+
|  (cpu)  CPU      12%        46 C        |
|  (gpu)  GPU       3%        41 C        |
|  (vrm)  VRAM      8%    0.6 / 8.0 GB    |
|                                         |
|  (ram)  RAM      58%    9.2 / 15.8 GB   |
|  (swp)  SWAP     21%    3.5 / 16.0 GB   |
|                                         |
|  (dsk)  DISK     67%     412 GB free    |
|  (tmp)  NVMe    30 C / 33 C             |
|                                         |
|  (act)  PRESSURE                        |
|          cpu   some 0.1   full 0.0      |
|          mem   some 0.4   full 0.3      |
|          io    some 0.0   full 0.0      |
+-----------------------------------------+
```

Built with `ui.column` / `ui.row` containers.

## Thresholds and colour

Colours use palette role tokens (`primary`, `on_surface`, `error`), not hex,
so the widget tracks the Lumae theme rather than fighting it.

| Metric | Activity | Critical |
|---|---|---|
| CPU usage | 70% | 90% |
| CPU temp | 75 C | 90 C |
| RAM | 75% | 88% |
| Swap | 50% | 80% |
| Disk | 80% | 92% |
| PSI mem full | 5.00 | 10.00 |
| GPU temp | 75 C | 87 C |

The PSI memory thresholds are deliberately the same 5.00 / 10.00 that
`classify_tier` uses in `memory-notify`. The bar turns amber at exactly the
point the notifier begins considering a warning, so the ambient readout and
the alarm never contradict each other.

`gpu1` idles at 0% permanently (dGPU cannot power off), so an idle GPU is
never flagged as anomalous.

Every threshold except the PSI pair is an estimate and expected to need
tuning in use. The PSI pair is anchored to measurements from the 2026-08-02
freeze.

## Error handling

| Failure | Behaviour |
|---|---|
| `nvidia-smi` absent | `commandExists` check at startup; GPU rows omitted from the panel, everything else works |
| `nvidia-smi` stream dies | Show last known values greyed; attempt one restart per minute |
| hwmon path stale after boot | Re-run discovery; if no `coretemp`, omit CPU temp rather than showing a wrong number |
| `/proc/pressure/*` unreadable | Show `--` for PSI rather than `0.0`, which would read as "healthy" |
| `df` fails | Keep last known disk figure, mark it stale |
| A single metric fails | Never blank the whole widget; degrade that row only |

The PSI row deserves emphasis: displaying `0.0` when the file cannot be read
is the same fail-closed trap found in `memory-notify` review, where a missing
PSI file silently meant "no pressure" and suppressed every alert. Show `--`.

## Testing

No bats equivalent exists for Luau plugins, so testing is split:

1. **Parser fixtures.** The `/proc` parsing functions take a string, not a
   path, so they can be exercised against captured fixture text: a real
   `/proc/stat` pair for delta calculation, `/proc/meminfo`, all three
   pressure files, and a captured `nvidia-smi dmon` line. Run via the Luau
   interpreter outside noctalia.
2. **Threshold table.** Each metric checked at just-below, exactly-at and
   just-above both thresholds.
3. **Degradation.** Fixtures for: missing pressure file, missing coretemp,
   `nvidia-smi` absent. Assert `--` rather than `0.0`, and that other rows
   still render.
4. **Live check.** Load in noctalia, confirm the bar figures match
   `htop` / `free -m` / `cat /proc/pressure/memory` at the same moment.

## Out of scope

- Decluttering the 13-widget `end` list. The widget goes in `start`, so the
  right side is untouched.
- Network and battery metrics - already covered by existing bar widgets.
- Per-core CPU breakdown. KDE showed `cpu/all/usage` only.
- Publishing to the noctalia community plugin registry.
- Replacing `memory-notify`. This is the ambient half; the notifier remains
  the alarm. They share thresholds deliberately but stay independent.
