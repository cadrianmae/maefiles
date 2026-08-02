# noctalia System Monitor Widget Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One noctalia bar widget showing CPU, RAM and PSI at a glance, with a click-panel carrying the full picture including both GPUs, swap and disk - replacing the five KDE Plasma monitor applets the niri session lost.

**Architecture:** A Luau plugin with two entries. The bar widget reads `/proc` every 2 s and renders three icon+number pairs. The panel, opened on click, reads the rest and starts two GPU streams (`nvidia-smi dmon` and KDE's setcap'd `ksystemstats_intel_helper`) only while it is open. Parsing lives in plain-Lua-compatible functions that take strings, so they are unit-testable with `/usr/bin/lua` outside noctalia.

**Tech Stack:** Luau (noctalia plugin runtime), `manifest.toml`, noctalia `ui.*` declarative UI, `/usr/bin/lua` for parser tests.

Spec: `~/docs/specs/2026-08-02-noctalia-sysmon-widget-design.md`

## Deliberate deviation from the spec

The spec describes both GPU streams as persistent for the plugin's lifetime,
mirroring KDE. This plan scopes them to **while the panel is open** instead.

Reason: the panel is the only consumer of GPU data - the bar shows CPU, RAM
and PSI only. KDE keeps its stream alive because its widgets display GPU
continuously; ours does not. Panel-scoped streams mean nothing runs in the
background, which is strictly better on a laptop.

This supersedes the spec's error-handling row "stream dies -> attempt one
restart per minute". With panel-scoped streams there is no background stream
to restart: each open starts fresh. A stream dying while the panel is open
leaves that row showing its last value until the panel is reopened, which is
acceptable for a panel that is open for seconds at a time. Update the spec to
match once implemented.

## CORRECTIONS FROM TASK 1 — these override the task text below

Task 1 discovered the upstream docs do not match noctalia 5.0.0. Where the
task text below disagrees with this block, THIS BLOCK WINS:

- Plugin manifest is `plugin.toml`, NOT `manifest.toml`.
- Bar widgets are declared `[[widget]]`, NOT `[[bar_widget]]`. The wrong key
  is accepted silently and yields zero entries - it does not error.
- `plugin_api` must be in the range 3-16, not `1`. Use `16`.
- A local plugin needs a REGISTERED SOURCE, not just a directory:
  `noctalia msg plugins source add local path <dir>`, a `catalog.toml` index
  at the source root, and a subdirectory named by the id's suffix only
  (`sysmon/`, not `mae/sysmon/`).
- Confirmed plugin directory:
  `~/.local/state/noctalia/plugins/sources/local/sysmon/`
- Entry id in settings.toml is `mae/sysmon:sysmon`.
- `noctalia msg plugins list` shows load state; the journal shows
  `loaded plugin 'mae/sysmon' (N entries)`. If N is 0 the manifest key is wrong.
- The `[[panel]]` key used in Task 5 is UNVERIFIED and may be wrong in the
  same way `[[bar_widget]]` was. Task 5 must confirm the real key from
  `strings -a /usr/bin/noctalia` and the entry count in the journal before
  assuming it works.

## Global Constraints

- Plugin API functions available: `noctalia.readFile(path)`, `noctalia.runStream(cmd, onLine)`, `noctalia.runAsync(cmd, cb)`, `noctalia.setUpdateInterval(ms)`, `noctalia.commandExists(name)`, `noctalia.fileExists(path)`, `noctalia.getConfig(key)`, `noctalia.togglePanel(id)`, `noctalia.notify(title, body)`.
- Entry scripts define GLOBAL functions: `update()`, `onClick()`, `onExit(signal, reason)`, `onOpen()`, and named handlers referenced by string from `onClick = "handlerName"`.
- `manifest.toml` REQUIRES `name` and `plugin_api`. A manifest missing either is rejected.
- Entry id namespace is `<author>/<plugin>:<entry-id>`, e.g. `mae/sysmon:panel`.
- Bar widget tree must stay ONE control tall - the capsule clips. Use `ui.row` on a horizontal bar.
- Colours use palette role tokens (`primary`, `on_surface`, `error`), never hex, so the widget tracks the Lumae theme.
- ASCII only in all source and docs. No emoji, no arrows.
- Comments explain WHY, not WHAT.
- Poll interval 2000 ms, matching `nvidia-smi dmon -d 2`.
- PSI memory thresholds are EXACTLY 5.00 activity / 10.00 critical - the same values `memory-notify`'s `classify_tier` uses. They must not drift.
- Never hardcode a hwmon index. `coretemp` was `hwmon8` on 2026-08-02 but numbering is probe-order and changes across boots. Discover by reading each `name` file.
- A failed metric degrades ONE row. Never blank the whole widget.
- PSI that cannot be read shows `--`, never `0.0`. Showing `0.0` reads as "healthy" and is the same fail-closed trap found in `memory-notify` review.
- Commits use Conventional Commits (`feat(sysmon): ...`). The yadm pre-commit hook warns on any other format.

## File Structure

Plugin source lives where noctalia loads it, and is explicitly yadm-tracked (nothing else under `.local/state` is):

| Path | Responsibility |
|---|---|
| `~/.local/state/noctalia/plugins/sources/local/sysmon/plugin.toml` | Plugin metadata, declares the bar widget and panel entries |
| `.../sysmon/lib/parse.luau` | Pure string-to-value parsers. No I/O. Plain-Lua-compatible so `/usr/bin/lua` can test it. |
| `.../sysmon/lib/thresholds.luau` | Threshold table and `level(metric, value)` returning `ok`/`activity`/`critical` |
| `.../sysmon/widget.luau` | Bar entry: reads `/proc`, renders three pairs, click opens panel |
| `.../sysmon/panel.luau` | Panel entry: full table, owns the two GPU streams and the disk poll |
| `~/scripts/noctalia-sysmon/test_parse.lua` | Parser tests, run with `/usr/bin/lua` |
| `~/scripts/noctalia-sysmon/fixtures/` | Captured `/proc` and stream output |

The split exists so parsing is testable without noctalia running. `parse.luau` takes strings and returns numbers; the entries do the I/O.

**Task 1 must empirically determine the load path.** `plugins/sources/` currently contains `community/` and `official/`. Whether a local plugin belongs in a third directory, or under one of those, is NOT documented - Task 1 finds out by trying and verifying, and every later task uses whatever Task 1 establishes.

---

### Task 1: Scaffold and prove the plugin loads

**Files:**
- Create: `~/.local/state/noctalia/plugins/sources/local/sysmon/manifest.toml`
- Create: `~/.local/state/noctalia/plugins/sources/local/sysmon/widget.luau`

**Interfaces:**
- Consumes: nothing.
- Produces: `PLUGIN_DIR` (the confirmed load path) and the entry id `mae/sysmon:sysmon`, both used by every later task.

- [ ] **Step 1: Determine the load path**

`~/.local/state/noctalia/plugins/sources/` holds `community/` and `official/`. Try, in order, until one loads:

1. `~/.local/state/noctalia/plugins/sources/local/mae/sysmon/`
2. `~/.local/state/noctalia/plugins/sources/mae/sysmon/`
3. `~/.local/state/noctalia/plugins/sources/community/mae/sysmon/`

Record which worked. If none load, check `journalctl --user -u noctalia -n 50` for a path or rejection message and report NEEDS_CONTEXT rather than guessing further.

- [ ] **Step 2: Write the manifest**

```toml
name = "sysmon"
plugin_api = 1
version = "0.1.0"
author = "mae"
license = "MIT"
description = "Unified system monitor: CPU, RAM, pressure, GPU, swap, disk"

[[bar_widget]]
id    = "sysmon"
entry = "widget.luau"
```

- [ ] **Step 3: Write a minimal widget that proves loading**

```lua
-- Scaffold only: proves the plugin loads and renders before any real
-- metric work is attempted.
function update()
  noctalia.setUpdateInterval(2000)
  barWidget.render(ui.row({ gap = 6, align = "center" }, {
    ui.glyph({ name = "cpu", size = 14 }),
    ui.label({ text = "sysmon ok", fontWeight = "bold" }),
  }))
end
```

- [ ] **Step 4: Enable it and verify**

Restart noctalia: `systemctl --user restart noctalia.service`
Add `"mae/sysmon:sysmon"` to `[bar.default] start` in `~/.local/state/noctalia/settings.toml`, after `"workspaces"`.

Expected: the text `sysmon ok` appears in the bar, right of workspaces.
If it does not, check `journalctl --user -u noctalia -n 50`.

- [ ] **Step 5: Track it**

```bash
cd ~ && yadm add ~/.local/state/noctalia/plugins/sources/local/sysmon/manifest.toml ~/.local/state/noctalia/plugins/sources/local/sysmon/widget.luau .local/state/noctalia/settings.toml
yadm commit -m "feat(sysmon): scaffold noctalia system monitor plugin"
```

---

### Task 2: /proc parsers with tests

**Files:**
- Create: `~/.local/state/noctalia/plugins/sources/local/sysmon/lib/parse.luau`
- Create: `~/scripts/noctalia-sysmon/test_parse.lua`
- Create: `~/scripts/noctalia-sysmon/fixtures/{meminfo,stat_a,stat_b,pressure_memory,pressure_cpu}.txt`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `parse.meminfo(text)` returns table `{ mem_total, mem_avail, swap_total, swap_free }` in kB
  - `parse.cpu_jiffies(text)` returns `total, idle` from a `/proc/stat` cpu line
  - `parse.cpu_percent(prev_total, prev_idle, total, idle)` returns integer 0-100
  - `parse.pressure(text)` returns table `{ some_avg10, some_avg60, full_avg10, full_avg60 }` as numbers, or `nil` if unparseable

- [ ] **Step 1: Capture the fixtures**

```bash
mkdir -p ~/scripts/noctalia-sysmon/fixtures
cp /proc/meminfo ~/scripts/noctalia-sysmon/fixtures/meminfo.txt
cp /proc/pressure/memory ~/scripts/noctalia-sysmon/fixtures/pressure_memory.txt
cp /proc/pressure/cpu ~/scripts/noctalia-sysmon/fixtures/pressure_cpu.txt
grep '^cpu ' /proc/stat > ~/scripts/noctalia-sysmon/fixtures/stat_a.txt
sleep 1
grep '^cpu ' /proc/stat > ~/scripts/noctalia-sysmon/fixtures/stat_b.txt
```

- [ ] **Step 2: Write the failing tests**

`~/scripts/noctalia-sysmon/test_parse.lua`:

```lua
-- Run: lua ~/scripts/noctalia-sysmon/test_parse.lua
-- parse.luau is written in the plain-Lua-compatible subset precisely so it
-- can be exercised here, outside noctalia's Luau runtime.
package.path = os.getenv("HOME") ..
  "/.local/state/noctalia/plugins/sources/local/sysmon/lib/?.luau;" .. package.path
local parse = require("parse")

local pass, fail = 0, 0
local function check(name, cond)
  if cond then pass = pass + 1
  else fail = fail + 1; print("FAIL: " .. name) end
end
local function read(f)
  local h = io.open(os.getenv("HOME") .. "/scripts/noctalia-sysmon/fixtures/" .. f)
  local t = h:read("*a"); h:close(); return t
end

local m = parse.meminfo(read("meminfo.txt"))
check("meminfo returns a table", type(m) == "table")
check("mem_total positive", m.mem_total > 0)
check("mem_avail positive", m.mem_avail > 0)
check("mem_avail <= mem_total", m.mem_avail <= m.mem_total)
check("swap_free <= swap_total", m.swap_free <= m.swap_total)

local m2 = parse.meminfo("MemTotal: 100 kB\nMemAvailable: 40 kB\n")
check("missing swap lines default to 0", m2.swap_total == 0 and m2.swap_free == 0)
check("mem_total exact", m2.mem_total == 100)

local ta, ia = parse.cpu_jiffies(read("stat_a.txt"))
local tb, ib = parse.cpu_jiffies(read("stat_b.txt"))
check("jiffies total increases", tb > ta)
check("jiffies idle does not decrease", ib >= ia)

local pct = parse.cpu_percent(ta, ia, tb, ib)
check("cpu percent in range", pct >= 0 and pct <= 100)
check("identical samples give 0", parse.cpu_percent(100, 50, 100, 50) == 0)
check("all-busy delta gives 100", parse.cpu_percent(0, 0, 100, 0) == 100)
check("half-busy delta gives 50", parse.cpu_percent(0, 0, 100, 50) == 50)

local p = parse.pressure(read("pressure_memory.txt"))
check("pressure returns a table", type(p) == "table")
check("full_avg10 is a number", type(p.full_avg10) == "number")
check("full_avg60 is a number", type(p.full_avg60) == "number")

local pc = parse.pressure(read("pressure_cpu.txt"))
check("cpu pressure parses (no full line on some kernels)",
      type(pc) == "table" and type(pc.some_avg10) == "number")

check("garbage returns nil", parse.pressure("not pressure data") == nil)
check("empty returns nil", parse.pressure("") == nil)

print(string.format("%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
```

- [ ] **Step 3: Run to verify failure**

Run: `lua ~/scripts/noctalia-sysmon/test_parse.lua`
Expected: FAIL, `module 'parse' not found`

- [ ] **Step 4: Write the parser**

`~/.local/state/noctalia/plugins/sources/local/sysmon/lib/parse.luau`:

```lua
-- Pure parsers: string in, numbers out. No I/O, no globals.
-- Kept in the plain-Lua-compatible subset so test_parse.lua can run it under
-- /usr/bin/lua without noctalia.
local parse = {}

function parse.meminfo(text)
  local out = { mem_total = 0, mem_avail = 0, swap_total = 0, swap_free = 0 }
  for key, value in string.gmatch(text, "(%w+):%s+(%d+)") do
    if     key == "MemTotal"     then out.mem_total  = tonumber(value)
    elseif key == "MemAvailable" then out.mem_avail  = tonumber(value)
    elseif key == "SwapTotal"    then out.swap_total = tonumber(value)
    elseif key == "SwapFree"     then out.swap_free  = tonumber(value)
    end
  end
  return out
end

function parse.cpu_jiffies(text)
  local line = string.match(text, "cpu%s+([%d%s]+)")
  if not line then return 0, 0 end
  local total, idle, field = 0, 0, 0
  for n in string.gmatch(line, "%d+") do
    field = field + 1
    total = total + tonumber(n)
    -- fields are user nice system idle iowait...; idle is 4th, iowait 5th and
    -- also counts as not-working time
    if field == 4 or field == 5 then idle = idle + tonumber(n) end
  end
  return total, idle
end

function parse.cpu_percent(prev_total, prev_idle, total, idle)
  local dt = total - prev_total
  local di = idle - prev_idle
  -- First tick has no previous sample, and a wrapped/reset counter would give
  -- a negative delta; report 0 rather than a nonsense spike.
  if dt <= 0 then return 0 end
  local pct = math.floor(((dt - di) * 100) / dt + 0.5)
  if pct < 0 then return 0 end
  if pct > 100 then return 100 end
  return pct
end

function parse.pressure(text)
  local out = {}
  local found = false
  for kind, rest in string.gmatch(text, "(%a+)%s+([^\n]+)") do
    local a10 = string.match(rest, "avg10=([%d%.]+)")
    local a60 = string.match(rest, "avg60=([%d%.]+)")
    if a10 and a60 then
      found = true
      out[kind .. "_avg10"] = tonumber(a10)
      out[kind .. "_avg60"] = tonumber(a60)
    end
  end
  -- nil, not a zero-filled table: a caller must be able to tell "unreadable"
  -- from "no pressure", or it will render 0.0 and read as healthy.
  if not found then return nil end
  return out
end

return parse
```

- [ ] **Step 5: Run to verify pass**

Run: `lua ~/scripts/noctalia-sysmon/test_parse.lua`
Expected: `18 passed, 0 failed`, exit 0

- [ ] **Step 6: Commit**

```bash
cd ~ && yadm add ~/.local/state/noctalia/plugins/sources/local/sysmon/lib/parse.luau scripts/noctalia-sysmon/
yadm commit -m "feat(sysmon): add /proc parsers with tests"
```

---

### Task 3: Threshold table

**Files:**
- Create: `~/.local/state/noctalia/plugins/sources/local/sysmon/lib/thresholds.luau`
- Modify: `~/scripts/noctalia-sysmon/test_parse.lua` (append a thresholds section)

**Interfaces:**
- Consumes: nothing.
- Produces: `thresholds.level(metric, value)` returning the string `"ok"`, `"activity"` or `"critical"`; and `thresholds.color(level)` returning a palette token string.

- [ ] **Step 1: Write the failing tests**

Append to `test_parse.lua`, before the final `print`:

```lua
local th = require("thresholds")

check("cpu below activity is ok",        th.level("cpu_usage", 69) == "ok")
check("cpu at activity is activity",     th.level("cpu_usage", 70) == "activity")
check("cpu just below critical",         th.level("cpu_usage", 89) == "activity")
check("cpu at critical",                 th.level("cpu_usage", 90) == "critical")
check("ram at activity",                 th.level("ram_pct", 75) == "activity")
check("ram at critical",                 th.level("ram_pct", 88) == "critical")
check("swap activity is 50",             th.level("swap_pct", 50) == "activity")
check("swap critical is 80",             th.level("swap_pct", 80) == "critical")
check("disk critical is 92",             th.level("disk_pct", 92) == "critical")
check("cpu temp critical is 90",         th.level("cpu_temp", 90) == "critical")
check("gpu temp critical is 87",         th.level("gpu_temp", 87) == "critical")

-- These two MUST match memory-notify's classify_tier or the bar and the
-- notifier will disagree about when things are bad.
check("psi mem activity is exactly 5",   th.level("psi_mem_full", 5.00) == "activity")
check("psi mem below 5 is ok",           th.level("psi_mem_full", 4.99) == "ok")
check("psi mem critical is exactly 10",  th.level("psi_mem_full", 10.00) == "critical")
check("psi mem below 10 is activity",    th.level("psi_mem_full", 9.99) == "activity")

check("unknown metric is ok",            th.level("nonsense", 999) == "ok")
check("ok maps to on_surface",           th.color("ok") == "on_surface")
check("activity maps to primary",        th.color("activity") == "primary")
check("critical maps to error",          th.color("critical") == "error")
```

- [ ] **Step 2: Run to verify failure**

Run: `lua ~/scripts/noctalia-sysmon/test_parse.lua`
Expected: FAIL, `module 'thresholds' not found`

- [ ] **Step 3: Write the thresholds module**

`~/.local/state/noctalia/plugins/sources/local/sysmon/lib/thresholds.luau`:

```lua
-- Threshold table. The psi_mem_full pair is NOT free to change: it mirrors
-- MEMNOTIFY_TIER_WARN_PSI / MEMNOTIFY_TIER_CRIT_PSI in
-- ~/bin/lib/memory-notify/core.sh so the ambient bar and the notifier agree
-- about when memory pressure matters. Everything else is tunable.
local thresholds = {}

local TABLE = {
  cpu_usage    = { activity = 70,   critical = 90   },
  cpu_temp     = { activity = 75,   critical = 90   },
  ram_pct      = { activity = 75,   critical = 88   },
  swap_pct     = { activity = 50,   critical = 80   },
  disk_pct     = { activity = 80,   critical = 92   },
  gpu_temp     = { activity = 75,   critical = 87   },
  psi_mem_full = { activity = 5.00, critical = 10.00 },
}

function thresholds.level(metric, value)
  local t = TABLE[metric]
  -- An unknown metric must not be styled as alarming. Silent "ok" beats a
  -- red bar caused by a typo in a metric name.
  if not t or type(value) ~= "number" then return "ok" end
  if value >= t.critical then return "critical" end
  if value >= t.activity then return "activity" end
  return "ok"
end

function thresholds.color(level)
  if level == "critical" then return "error" end
  if level == "activity" then return "primary" end
  return "on_surface"
end

return thresholds
```

- [ ] **Step 4: Run to verify pass**

Run: `lua ~/scripts/noctalia-sysmon/test_parse.lua`
Expected: `37 passed, 0 failed`

- [ ] **Step 5: Verify the PSI pair genuinely matches the notifier**

```bash
grep -E "MEMNOTIFY_TIER_(WARN|CRIT)_PSI" ~/bin/lib/memory-notify/core.sh
```

Expected: `500` and `1000` (centi-percent), i.e. 5.00 and 10.00. If they differ, STOP and report - the spec requires these stay in lockstep.

- [ ] **Step 6: Commit**

```bash
cd ~ && yadm add ~/.local/state/noctalia/plugins/sources/local/sysmon/lib/thresholds.luau scripts/noctalia-sysmon/test_parse.lua
yadm commit -m "feat(sysmon): add threshold table matching memory-notify"
```

---

### Task 4: Bar widget

**Files:**
- Modify: `~/.local/state/noctalia/plugins/sources/local/sysmon/widget.luau` (replace the Task 1 scaffold entirely)

**Interfaces:**
- Consumes: `parse.meminfo`, `parse.cpu_jiffies`, `parse.cpu_percent`, `parse.pressure` from Task 2; `thresholds.level`, `thresholds.color` from Task 3.
- Produces: the rendered bar entry; `onClick` opening `mae/sysmon:panel` (declared in Task 5).

- [ ] **Step 1: Write the widget**

```lua
local parse = require("parse")
local th = require("thresholds")

local prev_total, prev_idle = 0, 0

local function pct_of(used, total)
  if total == 0 then return 0 end
  return math.floor((used * 100) / total + 0.5)
end

-- Returns integer percent, or nil when /proc/stat cannot be read. nil is
-- rendered as "--" rather than 0, so an unreadable sensor never looks idle.
local function cpu_usage()
  local text = noctalia.readFile("/proc/stat")
  if not text then return nil end
  local total, idle = parse.cpu_jiffies(text)
  local pct = parse.cpu_percent(prev_total, prev_idle, total, idle)
  prev_total, prev_idle = total, idle
  return pct
end

local function ram_percent()
  local text = noctalia.readFile("/proc/meminfo")
  if not text then return nil end
  local m = parse.meminfo(text)
  return pct_of(m.mem_total - m.mem_avail, m.mem_total)
end

-- Returns the three PSI figures for the bar. Any that cannot be read come
-- back nil so they render "--"; showing 0.0 for an unreadable pressure file
-- would read as "healthy" and hide a real problem.
local function psi_triplet()
  local function one(path, field)
    local text = noctalia.readFile(path)
    if not text then return nil end
    local p = parse.pressure(text)
    if not p then return nil end
    return p[field]
  end
  return one("/proc/pressure/cpu", "some_avg60"),
         one("/proc/pressure/memory", "full_avg60"),
         one("/proc/pressure/io", "some_avg60")
end

local function fmt_pct(v)
  if v == nil then return "--" end
  return tostring(v) .. "%"
end

local function fmt_psi(v)
  if v == nil then return "--" end
  return string.format("%.1f", v)
end

function update()
  noctalia.setUpdateInterval(2000)

  local cpu = cpu_usage()
  local ram = ram_percent()
  local psi_cpu, psi_mem, psi_io = psi_triplet()

  local cpu_color = th.color(th.level("cpu_usage", cpu))
  local ram_color = th.color(th.level("ram_pct", ram))
  local psi_color = th.color(th.level("psi_mem_full", psi_mem))

  barWidget.render(ui.row({ gap = 8, align = "center", onClick = "onClick" }, {
    ui.glyph({ name = "cpu", size = 14, color = cpu_color }),
    ui.label({ text = fmt_pct(cpu), color = cpu_color, fontWeight = "bold" }),
    ui.glyph({ name = "device-sd-card", size = 14, color = ram_color }),
    ui.label({ text = fmt_pct(ram), color = ram_color, fontWeight = "bold" }),
    ui.glyph({ name = "activity", size = 14, color = psi_color }),
    ui.label({
      text = fmt_psi(psi_cpu) .. "/" .. fmt_psi(psi_mem) .. "/" .. fmt_psi(psi_io),
      color = psi_color,
      fontWeight = "bold",
    }),
  }))
end

function onClick()
  noctalia.togglePanel("mae/sysmon:panel")
end
```

- [ ] **Step 2: Reload and verify against reality**

```bash
systemctl --user restart noctalia.service
sleep 3
grep MemAvailable /proc/meminfo
cat /proc/pressure/memory
```

Expected: the bar's RAM percent matches `(MemTotal-MemAvailable)/MemTotal` within 1 point, and the middle PSI figure matches `full avg60`.

- [ ] **Step 3: Verify degradation shows `--`, not 0**

Temporarily point the widget at a nonexistent pressure path by editing the
`/proc/pressure/io` string to `/proc/pressure/nope`, reload, and confirm the
third PSI figure renders `--`. Then revert the edit and reload again.

Expected: `0.1/0.3/--`, never `0.1/0.3/0.0`.

- [ ] **Step 4: Commit**

```bash
cd ~ && yadm add ~/.local/state/noctalia/plugins/sources/local/sysmon/widget.luau
yadm commit -m "feat(sysmon): render CPU, RAM and pressure in the bar"
```

---

### Task 5: Panel scaffold

**Files:**
- Modify: `~/.local/state/noctalia/plugins/sources/local/sysmon/manifest.toml` (add the panel entry)
- Create: `~/.local/state/noctalia/plugins/sources/local/sysmon/panel.luau`

**Interfaces:**
- Consumes: `parse`, `thresholds`; `onClick` from Task 4 which calls `togglePanel("mae/sysmon:panel")`.
- Produces: the panel entry, plus `render_rows(rows)` shape that Tasks 6 and 7 extend.

- [ ] **Step 1: Add the panel to the manifest**

Append:

```toml
[[panel]]
id        = "panel"
entry     = "panel.luau"
width     = 380
height    = 420
placement = "floating"
position  = "center"
```

- [ ] **Step 2: Write the panel with the /proc rows only**

GPU and disk arrive in Tasks 6 and 7.

```lua
local parse = require("parse")
local th = require("thresholds")

local function pct_of(used, total)
  if total == 0 then return 0 end
  return math.floor((used * 100) / total + 0.5)
end

local function gb(kb)
  return string.format("%.1f", kb / 1048576)
end

-- One row: icon, label, value, detail. Value is coloured by its threshold
-- level so the panel reads at a glance, not just the bar.
local function metric_row(glyph, name, value_text, detail_text, level)
  return ui.row({ gap = 10, align = "center" }, {
    ui.glyph({ name = glyph, size = 14, color = th.color(level) }),
    ui.label({ text = name, color = "on_surface", maxWidth = 70 }),
    ui.label({ text = value_text, color = th.color(level), fontWeight = "bold" }),
    ui.label({ text = detail_text or "", color = "on_surface/0.6" }),
  })
end

-- Discovers a hwmon node by its name file. hwmon indices are assigned in
-- probe order and change across boots, so caching an index would silently
-- report the wrong sensor after a reboot.
local function hwmon_temp(want_name)
  for i = 0, 20 do
    local base = "/sys/class/hwmon/hwmon" .. i
    local name = noctalia.readFile(base .. "/name")
    if name and string.match(name, "^%s*" .. want_name) then
      local raw = noctalia.readFile(base .. "/temp1_input")
      if raw then return math.floor(tonumber(raw) / 1000) end
    end
  end
  return nil
end

local function build_rows()
  local rows = {}

  local cpu_temp = hwmon_temp("coretemp")
  table.insert(rows, metric_row("cpu", "CPU",
    "--",
    cpu_temp and (cpu_temp .. " C") or "",
    th.level("cpu_temp", cpu_temp)))

  local meminfo = noctalia.readFile("/proc/meminfo")
  if meminfo then
    local m = parse.meminfo(meminfo)
    local ram = pct_of(m.mem_total - m.mem_avail, m.mem_total)
    table.insert(rows, metric_row("device-sd-card", "RAM",
      ram .. "%",
      gb(m.mem_total - m.mem_avail) .. " / " .. gb(m.mem_total) .. " GB",
      th.level("ram_pct", ram)))

    if m.swap_total > 0 then
      local swap = pct_of(m.swap_total - m.swap_free, m.swap_total)
      table.insert(rows, metric_row("database", "SWAP",
        swap .. "%",
        gb(m.swap_total - m.swap_free) .. " / " .. gb(m.swap_total) .. " GB",
        th.level("swap_pct", swap)))
    end
  end

  table.insert(rows, ui.label({ text = "PRESSURE", color = "on_surface", fontWeight = "bold" }))
  for _, kind in ipairs({ "cpu", "memory", "io" }) do
    local text = noctalia.readFile("/proc/pressure/" .. kind)
    local p = text and parse.pressure(text) or nil
    local some = p and string.format("%.1f", p.some_avg60 or 0) or "--"
    local full = p and p.full_avg60 and string.format("%.1f", p.full_avg60) or "--"
    local level = (kind == "memory") and th.level("psi_mem_full", p and p.full_avg60) or "ok"
    table.insert(rows, metric_row("activity", "  " .. kind,
      "some " .. some, "full " .. full, level))
  end

  return rows
end

local function render()
  panel.render(ui.column({ gap = 8, padding = 16 }, {
    ui.row({ justify = "space_between", align = "center" }, {
      ui.label({ text = "System", fontSize = 16, fontWeight = "bold" }),
      ui.button({ glyph = "close", onClick = "onClose" }),
    }),
    ui.column({ gap = 6 }, build_rows()),
  }))
end

function onOpen() render() end
function onClose() panel.close() end
```

- [ ] **Step 3: Reload and verify**

```bash
systemctl --user restart noctalia.service
```

Click the bar widget. Expected: a panel showing CPU (temp only for now), RAM, SWAP and three PRESSURE rows, with values matching `free -m` and `cat /proc/pressure/*`.

- [ ] **Step 4: Commit**

```bash
cd ~ && yadm add ~/.local/state/noctalia/plugins/sources/local/sysmon/manifest.toml ~/.local/state/noctalia/plugins/sources/local/sysmon/panel.luau
yadm commit -m "feat(sysmon): add detail panel with memory and pressure rows"
```

---

### Task 6: GPU streams

**Files:**
- Modify: `~/.local/state/noctalia/plugins/sources/local/sysmon/panel.luau`
- Create: `~/scripts/noctalia-sysmon/fixtures/{nvidia_dmon,intel_helper}.txt`

**Interfaces:**
- Consumes: `build_rows` and `metric_row` from Task 5.
- Produces: `parse.nvidia_dmon(line)` and `parse.intel_helper(line)` added to `lib/parse.luau`.

Streams start on panel open and stop on close - the panel is the only consumer, so nothing runs while it is shut.

- [ ] **Step 1: Capture fixtures**

```bash
timeout 5 nvidia-smi dmon -d 2 -s pucm > ~/scripts/noctalia-sysmon/fixtures/nvidia_dmon.txt 2>&1
timeout 4 /usr/libexec/ksystemstats_intel_helper > ~/scripts/noctalia-sysmon/fixtures/intel_helper.txt 2>&1
head -5 ~/scripts/noctalia-sysmon/fixtures/nvidia_dmon.txt
head -3 ~/scripts/noctalia-sysmon/fixtures/intel_helper.txt
```

Inspect the real `dmon` header before writing the parser - column order must be read from the captured file, not assumed.

- [ ] **Step 2: Write the failing tests**

Append to `test_parse.lua`:

```lua
-- dmon emits two header lines beginning with '#'; only data lines parse.
check("dmon header returns nil", parse.nvidia_dmon("# gpu   pwr gtemp") == nil)
local n = parse.nvidia_dmon("    0    12    41     -    45     8     0     0")
check("dmon data returns a table", type(n) == "table")
check("dmon gives a numeric usage", type(n.usage) == "number")
check("dmon gives a numeric temp", type(n.temp) == "number")

local i = parse.intel_helper("1000176177|Frequency|191|Interrupts|872|Render|457711853|Copy|0|Video|0|Enhance|0")
check("intel returns a table", type(i) == "table")
check("intel timestamp parsed", i.timestamp == 1000176177)
check("intel render counter parsed", i.render == 457711853)
check("intel garbage returns nil", parse.intel_helper("nonsense") == nil)

-- Counter deltas, not absolute values: the helper reports cumulative
-- nanoseconds busy, exactly as KDE's LinuxIntelGpu computes it.
check("intel percent from deltas",
      parse.intel_percent(0, 0, 500000000, 1000000000) == 50)
check("intel percent clamps at 100",
      parse.intel_percent(0, 0, 2000000000, 1000000000) == 100)
check("intel percent zero timedelta is 0",
      parse.intel_percent(0, 0, 100, 0) == 0)
```

- [ ] **Step 3: Run to verify failure**

Run: `lua ~/scripts/noctalia-sysmon/test_parse.lua`
Expected: FAIL on `parse.nvidia_dmon` being nil

- [ ] **Step 4: Add the parsers**

Append to `lib/parse.luau`, before `return parse`:

```lua
-- nvidia-smi dmon data lines are whitespace-separated numbers; header lines
-- start with '#'. Column positions are taken from the captured fixture:
-- gpu, pwr, gtemp, mtemp, sm, mem, enc, dec
function parse.nvidia_dmon(line)
  if not line or string.match(line, "^%s*#") then return nil end
  local fields = {}
  for tok in string.gmatch(line, "%S+") do
    table.insert(fields, tonumber(tok))
  end
  if #fields < 6 then return nil end
  return { temp = fields[3], usage = fields[5], mem_usage = fields[6] }
end

-- Pipe-delimited key/value pairs after a leading nanosecond timestamp.
function parse.intel_helper(line)
  if not line then return nil end
  local ts = string.match(line, "^(%d+)|")
  if not ts then return nil end
  local out = { timestamp = tonumber(ts) }
  for key, value in string.gmatch(line, "|(%a+)|(%d+)") do
    out[string.lower(key)] = tonumber(value)
  end
  if out.render == nil then return nil end
  return out
end

-- Busy-nanoseconds delta over elapsed-nanoseconds delta, matching upstream
-- LinuxIntelGpu: (value - lastUsage) * 100.0 / timediff
function parse.intel_percent(prev_render, prev_ts, render, ts)
  local dt = ts - prev_ts
  if dt <= 0 then return 0 end
  local pct = math.floor(((render - prev_render) * 100) / dt + 0.5)
  if pct < 0 then return 0 end
  if pct > 100 then return 100 end
  return pct
end
```

- [ ] **Step 5: Run to verify pass**

Run: `lua ~/scripts/noctalia-sysmon/test_parse.lua`
Expected: all pass, 0 failed

- [ ] **Step 6: Wire the streams into the panel**

Add near the top of `panel.luau`:

```lua
local gpu = { nvidia = nil, intel = nil }
local intel_prev = { render = nil, ts = nil }
local streams = { nvidia = nil, intel = nil }

local HELPER = "/usr/libexec/ksystemstats_intel_helper"

-- Streams live only while the panel is open. The panel is the only consumer
-- of GPU data, so nothing runs in the background when it is shut.
local function start_streams()
  if noctalia.commandExists("nvidia-smi") and not streams.nvidia then
    streams.nvidia = noctalia.runStream("nvidia-smi dmon -d 2 -s pucm", function(line)
      local n = parse.nvidia_dmon(line)
      if n then gpu.nvidia = n; render() end
    end)
  end

  -- Ships with ksystemstats and already carries cap_perfmon, so no
  -- system-wide perf_event_paranoid change is needed. Absent if KDE is
  -- uninstalled, in which case the Intel row is simply omitted.
  if noctalia.fileExists(HELPER) and not streams.intel then
    streams.intel = noctalia.runStream(HELPER, function(line)
      local i = parse.intel_helper(line)
      if not i then return end
      if intel_prev.ts then
        gpu.intel = parse.intel_percent(intel_prev.render, intel_prev.ts, i.render, i.timestamp)
      end
      intel_prev.render, intel_prev.ts = i.render, i.timestamp
      render()
    end)
  end
end

local function stop_streams()
  for key, handle in pairs(streams) do
    if handle then handle.stop() end
    streams[key] = nil
  end
  intel_prev.render, intel_prev.ts = nil, nil
end
```

Insert into `build_rows`, after the CPU row:

```lua
  if gpu.nvidia then
    table.insert(rows, metric_row("device-desktop", "NVIDIA",
      gpu.nvidia.usage .. "%",
      gpu.nvidia.temp .. " C",
      th.level("gpu_temp", gpu.nvidia.temp)))
  end
  if gpu.intel then
    table.insert(rows, metric_row("device-desktop", "INTEL",
      gpu.intel .. "%", "", "ok"))
  end
```

Replace the lifecycle functions:

```lua
function onOpen() start_streams(); render() end
function onClose() stop_streams(); panel.close() end
function onExit(signal, reason) stop_streams() end
```

- [ ] **Step 7: Verify against reality**

```bash
systemctl --user restart noctalia.service
```

Open the panel, then in a terminal:

```bash
nvidia-smi --query-gpu=utilization.gpu,temperature.gpu --format=csv,noheader
```

Expected: the panel's NVIDIA row matches within a couple of points, and an INTEL row shows a plausible percentage. Close the panel and confirm the processes are gone:

```bash
pgrep -af "nvidia-smi dmon|ksystemstats_intel_helper" || echo "streams stopped"
```

Expected: `streams stopped`.

- [ ] **Step 8: Commit**

```bash
cd ~ && yadm add ~/.local/state/noctalia/plugins/sources/local/sysmon/panel.luau ~/.local/state/noctalia/plugins/sources/local/sysmon/lib/parse.luau scripts/noctalia-sysmon/
yadm commit -m "feat(sysmon): add both GPUs via streamed counters"
```

---

### Task 7: Disk row

**Files:**
- Modify: `~/.local/state/noctalia/plugins/sources/local/sysmon/panel.luau`

**Interfaces:**
- Consumes: `metric_row`, `build_rows`, `render` from Task 5.
- Produces: `parse.df(text)` added to `lib/parse.luau`.

- [ ] **Step 1: Write the failing test**

Append to `test_parse.lua`:

```lua
local d = parse.df("Avail        Size\n412000000000 900000000000\n")
check("df returns a table", type(d) == "table")
check("df avail parsed", d.avail == 412000000000)
check("df size parsed", d.size == 900000000000)
check("df used percent", d.used_pct == 54)
check("df garbage returns nil", parse.df("no numbers here") == nil)
```

- [ ] **Step 2: Run to verify failure**

Run: `lua ~/scripts/noctalia-sysmon/test_parse.lua`
Expected: FAIL on `parse.df`

- [ ] **Step 3: Add the parser**

Append to `lib/parse.luau`, before `return parse`:

```lua
-- df --output=avail,size -B1 prints a header then one data line of bytes.
function parse.df(text)
  local avail, size = string.match(text, "(%d+)%s+(%d+)")
  if not avail then return nil end
  avail, size = tonumber(avail), tonumber(size)
  if size == 0 then return nil end
  return {
    avail = avail,
    size = size,
    used_pct = math.floor(((size - avail) * 100) / size + 0.5),
  }
end
```

- [ ] **Step 4: Wire it in**

Add to `panel.luau` near the other state:

```lua
local disk = nil

-- Disk free is the one metric with no /proc source; it needs statvfs, which
-- the Luau API does not expose. It changes slowly, so refreshing on panel
-- open is enough - no background polling.
local function refresh_disk()
  noctalia.runAsync("df --output=avail,size -B1 / | tail -1", function(result)
    if result and result.stdout then
      disk = parse.df(result.stdout)
      render()
    end
  end)
end
```

Insert into `build_rows`, after the SWAP row:

```lua
  if disk then
    table.insert(rows, metric_row("database", "DISK",
      disk.used_pct .. "%",
      string.format("%.0f GB free", disk.avail / 1073741824),
      th.level("disk_pct", disk.used_pct)))
  end
```

Change `onOpen`:

```lua
function onOpen() start_streams(); refresh_disk(); render() end
```

- [ ] **Step 5: Verify**

```bash
systemctl --user restart noctalia.service
df -h /
```

Expected: the panel's DISK row matches `df -h /` output.

- [ ] **Step 6: Run the full test suite and commit**

```bash
lua ~/scripts/noctalia-sysmon/test_parse.lua
cd ~ && yadm add ~/.local/state/noctalia/plugins/sources/local/sysmon/panel.luau ~/.local/state/noctalia/plugins/sources/local/sysmon/lib/parse.luau scripts/noctalia-sysmon/test_parse.lua
yadm commit -m "feat(sysmon): add disk row"
```

---

### Task 8: Degradation and final verification

**Files:**
- Modify: `~/.local/state/noctalia/plugins/sources/local/sysmon/widget.luau` (tooltip)
- Modify: `~/docs/specs/2026-08-02-noctalia-sysmon-widget-design.md` (status line)

**Interfaces:**
- Consumes: everything from Tasks 1-7.
- Produces: the finished widget.

- [ ] **Step 1: Add the hover tooltip**

Bar widgets cannot show a rich hover popup, so the tooltip is a one-line
summary. Wrap the bar row's contents in a `ui.button` carrying `tooltip`, or
set `tooltip` on the row if supported; verify which works by reloading.

```lua
  local tip = string.format("CPU %s  RAM %s  PSI cpu %s / mem %s / io %s",
    fmt_pct(cpu), fmt_pct(ram), fmt_psi(psi_cpu), fmt_psi(psi_mem), fmt_psi(psi_io))
```

- [ ] **Step 2: Verify every degradation path**

Each of these must degrade ONE row and leave the rest working. Check the bar
never blanks entirely.

| Simulate | Expected |
|---|---|
| Rename the pressure path in `widget.luau` to `/proc/pressure/nope`, reload | that PSI figure shows `--`, others fine |
| Point `HELPER` at `/nonexistent`, reload, open panel | no INTEL row, NVIDIA row still present |
| Temporarily rename the `coretemp` match to `nosuchsensor`, reload | CPU row shows no temperature, no crash |

Revert each edit after checking, and reload to confirm the real behaviour returns.

- [ ] **Step 3: Confirm no leaked processes**

```bash
systemctl --user restart noctalia.service
pgrep -af "nvidia-smi dmon|ksystemstats_intel_helper" || echo "none running (panel closed)"
```

Open the panel, confirm both appear, close it, confirm both stop.

- [ ] **Step 4: Cross-check every number**

```bash
free -m; cat /proc/pressure/memory; df -h /
nvidia-smi --query-gpu=utilization.gpu,temperature.gpu --format=csv,noheader
```

Every panel figure must match its source at the same moment.

- [ ] **Step 5: Mark the spec implemented, record the deviation, and commit**

Change the spec's `Status:` line to `Implemented 2026-08-02`.

Also update the spec's GPU section to match what was actually built: streams
are panel-scoped, not persistent, and the "attempt one restart per minute"
error-handling row no longer applies. A spec that describes something other
than the shipped code is worse than no spec.

```bash
cd ~ && yadm add docs/specs/2026-08-02-noctalia-sysmon-widget-design.md ~/.local/state/noctalia/plugins/sources/local/sysmon/widget.luau
yadm commit -m "feat(sysmon): add tooltip and mark spec implemented"
```

---

## Deferred

Recorded in the spec's out-of-scope section:

- NVMe drive temperatures (`hwmon` `name=nvme`, two drives)
- Decluttering the 13-widget `end` list
- Per-core CPU breakdown
- Publishing to the noctalia community registry
