-- Detail panel: CPU temp, RAM, SWAP and PRESSURE rows. GPU and disk rows
-- arrive in Tasks 6 and 7. noctalia's Luau runtime has no require/load
-- (proven Task 2), so parse.luau and thresholds.luau are inlined below
-- rather than imported. lib/*.luau stay the source of truth;
-- ~/scripts/noctalia-sysmon/test_parse.lua asserts these copies match them
-- byte-for-byte, so any edit belongs in the library file, not here.

-- BEGIN INLINED parse.luau
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
  -- mem_total == 0 only happens if MemTotal was never found (empty,
  -- truncated, or not meminfo at all) -- a real machine cannot report a
  -- zero MemTotal, so treat this as "unreadable" and return nil.
  --
  -- swap_total/swap_free == 0 do NOT gate this: a machine can legitimately
  -- have no swap configured, and that is a real, healthy 0, not a parse
  -- failure. Do not fold swap into this guard.
  if out.mem_total == 0 then return nil end
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

-- nvidia-smi dmon emits two header lines starting with '#', then data lines
-- of whitespace-separated numbers. Real column order, captured on this
-- machine into ~/scripts/noctalia-sysmon/fixtures/nvidia_dmon.txt via
-- `nvidia-smi dmon -d 2 -s pucm`: gpu pwr gtemp mtemp sm mem enc dec jpg ofa
-- mclk pclk fb bar1 ccpm.
--
-- mtemp is "-" on this machine (no dedicated memory-temp sensor), so
-- tonumber("-") is nil for that column. table.insert(fields, tonumber(tok))
-- would silently skip that nil and shift every later column left by one --
-- sm (usage) would be read from mem's slot instead. Assign by explicit
-- position (fields[count] = ...) so a hole stays a hole and later columns
-- keep their real index.
function parse.nvidia_dmon(line)
  if not line or string.match(line, "^%s*#") then return nil end
  local fields = {}
  local count = 0
  for tok in string.gmatch(line, "%S+") do
    count = count + 1
    fields[count] = tonumber(tok)
  end
  if count < 6 or not fields[3] or not fields[5] or not fields[6] then return nil end
  return { temp = fields[3], usage = fields[5], mem_usage = fields[6] }
end

-- Pipe-delimited key/value pairs after a leading nanosecond timestamp, as
-- emitted by /usr/libexec/ksystemstats_intel_helper (ships with ksystemstats,
-- already carries cap_perfmon, needs no perf_event_paranoid change).
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
-- LinuxIntelGpu: (value - lastUsage) * 100.0 / timediff.
function parse.intel_percent(prev_render, prev_ts, render, ts)
  local dt = ts - prev_ts
  if dt <= 0 then return 0 end
  local pct = math.floor(((render - prev_render) * 100) / dt + 0.5)
  if pct < 0 then return 0 end
  if pct > 100 then return 100 end
  return pct
end

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
-- END INLINED parse.luau

-- BEGIN INLINED thresholds.luau
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
  -- Distinguish sensor read failures from metric name typos: an unreadable
  -- sensor (nil, non-number value) must render visually distinct from "healthy"
  -- to avoid silent failures like the sibling tool's pressure-file bug. An
  -- unknown metric name IS a code bug but not a sensor failure -- don't alarm
  -- the user for a typo in the dashboard config.
  if type(value) ~= "number" then return "unknown" end
  local t = TABLE[metric]
  if not t then return "ok" end
  if value >= t.critical then return "critical" end
  if value >= t.activity then return "activity" end
  return "ok"
end

function thresholds.color(level)
  if level == "critical" then return "error" end
  if level == "activity" then return "primary" end
  if level == "unknown" then return "on_surface/0.4" end
  return "on_surface"
end
-- END INLINED thresholds.luau

local th = thresholds

-- GPU state used to live only while this panel was open, with the panel
-- owning both streams directly (start_streams/stop_streams, PID sentinel
-- capture, SIGTERM/SIGKILL escalation, pkill -x -f fallback). That has moved
-- to widget.luau: the bar needs GPU data continuously (for its graph), not
-- just while this panel happens to be open, and the plugin loads once per
-- monitor, so only one widget instance may own the streams at a time (see
-- widget.luau's update_ownership for the cross-monitor arbitration). This
-- panel now owns no streams at all -- it only reads noctalia.state, exactly
-- like a non-owner widget instance does.
--
-- gpu_available is tracked separately from gpu: available means "the owning
-- widget instance has the tool/binary and started (or tried to start) its
-- stream", data (gpu.nvidia/gpu.intel) means "a line has actually arrived".
--
-- gpu_available is a THREE-state value, not a boolean pair with a false
-- default:
--   nil    -- not yet known. Nothing has published AVAILABLE_KEY at all,
--             which happens for a real ~4-6s window after every noctalia
--             restart (the owning widget's 2-tick election plus its first
--             probe) -- most visibly if this panel is opened during that
--             window. build_rows below renders BOTH possible GPU rows
--             dimmed "--" in this state, not omitted -- omitting them read
--             as "this machine has no such hardware", which is not yet
--             known one way or the other.
--   table, field false -- known absent (no nvidia-smi / no helper binary on
--             this machine). The row for that GPU is omitted entirely --
--             there is no such GPU to report on, this is not a data gap.
--   table, field true  -- known present. Row is shown, live or dimmed
--             depending on gpu.X (no data yet) / gpu_stale.X (stream gone
--             quiet -- see below).
local gpu = { nvidia = nil, intel = nil }
local gpu_available = nil
-- Per-GPU freshness, owner-computed and published alongside gpu.nvidia/
-- gpu.intel (see widget.luau's nvidia_stale_ticks/intel_stale_ticks and
-- STALE_KEY) -- true means the most recent published value is old enough
-- that showing it as a live current reading would be a lie. Defaults to
-- not-stale for the same reason as widget.luau's copy of this default: it
-- is only ever consulted alongside a gpu.X nil check in build_rows, so
-- before STALE_KEY has ever been published it is moot.
local gpu_stale = { nvidia = false, intel = false }

-- Keys shared with widget.luau's copy of this same constant set -- kept in
-- sync by hand, same as the inlined parse/thresholds libraries above, since
-- isolated Luau VMs cannot require() a shared constants file either.
local NVIDIA_KEY = "sysmon_gpu_nvidia"
local INTEL_KEY = "sysmon_gpu_intel"
local AVAILABLE_KEY = "sysmon_gpu_available"
local STALE_KEY = "sysmon_gpu_stale"

-- Seed from whatever the owning widget instance has already published (it
-- may have been running long before this panel was ever opened), then watch
-- for further updates -- noctalia.state watchers do not replay the current
-- value on registration, only future set() calls. Registered once here at
-- panel load time, not per onOpen/onClose: there is no unwatch exposed to
-- Luau (watchers for a runtime are only cleaned up wholesale on that
-- runtime's own reload/stop), so re-registering on every onOpen would stack
-- duplicate callbacks instead of replacing one.
gpu.nvidia = noctalia.state.get(NVIDIA_KEY)
gpu.intel = noctalia.state.get(INTEL_KEY)
-- No `or {...}` fallback: nil here IS the "not yet known" state build_rows
-- distinguishes from "known absent" -- see the long comment above.
gpu_available = noctalia.state.get(AVAILABLE_KEY)
gpu_stale = noctalia.state.get(STALE_KEY) or { nvidia = false, intel = false }

-- The watch callbacks below fire whether the panel is open or not (there is
-- no way to unwatch), so each one guards its render() with is_open --
-- calling panel.render() while genuinely closed would rebuild a tree no one
-- can see, for no benefit.
local is_open = false

-- Forward-declared: render() is defined further down (it needs build_rows,
-- metric_row, etc., which are not written yet at this point in the file),
-- but the watch callbacks registered immediately below capture it as an
-- upvalue. Without this forward `local`, those closures would resolve the
-- bare name `render` as a global at the point they are WRITTEN (Lua scoping
-- is lexical, not "whatever exists by the time this code eventually runs")
-- -- and no global `render` exists, so every watch-driven update while the
-- panel was open would error "attempt to call a nil value" instead of
-- refreshing. Declaring the local here, then assigning `render = function()
-- ... end` later (not `local function render()`, which would create a
-- SECOND, separate local and leave this upvalue nil forever) is what makes
-- the later definition visible to these earlier closures.
local render

noctalia.state.watch(NVIDIA_KEY, function(v)
  gpu.nvidia = v
  if is_open then render() end
end)
noctalia.state.watch(INTEL_KEY, function(v)
  gpu.intel = v
  if is_open then render() end
end)
noctalia.state.watch(AVAILABLE_KEY, function(v)
  -- No `or {...}` fallback here either -- see the long comment above.
  gpu_available = v
  if is_open then render() end
end)
noctalia.state.watch(STALE_KEY, function(v)
  gpu_stale = v or { nvidia = false, intel = false }
  if is_open then render() end
end)

-- CPU usage is a delta and needs two /proc/stat samples separated in time;
-- a single read gives cumulative-since-boot numbers, which render as a
-- plausible but meaningless "uptime average" -- this is the exact bug
-- widget.luau's cpu_usage() guards against (see its cpu_prev_total == 0
-- check), and the same guard is replicated here.
--
-- Panels are event-driven (onOpen/render) by default, not ticked like the
-- bar widget -- but a panel CAN opt into a fixed 1s tick timer by calling
-- panel.setWantsSecondTicks(true) (see onOpen below), which then calls the
-- panel's global update() once a second while it stays open. Confirmed two
-- ways: (1) the shipped official/notes panel.luau calls exactly that and
-- drives its idle-autosave timer from update(); (2) reading the host's own
-- C++ source (plugin_panel.cpp: kTickIntervalMs = 1000, gated on
-- m_wantsSecondTicks; plugin_bindings.cpp: panel.setWantsSecondTicks ->
-- patch.wantsSecondTicks) -- cloned read-only from the noctalia-dev/noctalia
-- GitHub repo for this task, since a live probe first showed update() firing
-- exactly once (the runtime's one-time post-load bootstrap call, not a
-- tick) with no repeat, which sent us to the source instead of guessing.
-- noctalia.setUpdateInterval (what the bar widget calls) is the WRONG API
-- for panels -- it only feeds patch.updateIntervalMs, which PluginPanel
-- never reads at all; calling it here is silently a no-op.
--
-- update() is used rather than piggybacking on the GPU stream callbacks,
-- which would make CPU usage silently depend on a GPU stream existing (no
-- stream = row never populates on a machine with neither nvidia-smi nor
-- the Intel helper).
local cpu_prev_total, cpu_prev_idle = 0, 0
local cpu_pct = nil -- nil until a valid delta exists; renders "--" dimmed

-- Disk free has no /proc source; it needs statvfs, which the Luau API does
-- not expose. See refresh_disk below (defined after render(), which its
-- callback captures as a local upvalue).
local disk = nil

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
    cpu_pct and (cpu_pct .. "%") or "--",
    cpu_temp and (cpu_temp .. " C") or "",
    th.level("cpu_usage", cpu_pct)))

  -- Three states (see the long comment on `local gpu_available` near the
  -- top of this file): not yet known -> both possible rows dimmed rather
  -- than omitted (omitting them would read as "no such hardware", which is
  -- not yet established either way); known absent -> row omitted entirely;
  -- known present -> a live row, OR a dimmed "--" if no data has arrived
  -- yet, OR a dimmed "--" if the most recent value has gone stale
  -- (gpu_stale.X -- a stream that died mid-session must not keep showing
  -- its last reading as if it were current).
  if gpu_available == nil then
    table.insert(rows, metric_row("device-desktop", "NVIDIA", "--", "", "unknown"))
    table.insert(rows, metric_row("device-desktop", "INTEL", "--", "", "unknown"))
  else
    if gpu_available.nvidia then
      if gpu.nvidia and not gpu_stale.nvidia then
        table.insert(rows, metric_row("device-desktop", "NVIDIA",
          gpu.nvidia.usage .. "%",
          gpu.nvidia.temp .. " C",
          th.level("gpu_temp", gpu.nvidia.temp)))
      else
        table.insert(rows, metric_row("device-desktop", "NVIDIA", "--", "", "unknown"))
      end
    end
    if gpu_available.intel then
      if gpu.intel and not gpu_stale.intel then
        table.insert(rows, metric_row("device-desktop", "INTEL",
          gpu.intel .. "%", "", "ok"))
      else
        table.insert(rows, metric_row("device-desktop", "INTEL", "--", "", "unknown"))
      end
    end
  end

  local meminfo = noctalia.readFile("/proc/meminfo")
  if meminfo then
    local m = parse.meminfo(meminfo)
    if m then
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
    else
      table.insert(rows, metric_row("device-sd-card", "RAM", "--", "", "unknown"))
    end
  else
    table.insert(rows, metric_row("device-sd-card", "RAM", "--", "", "unknown"))
  end

  if disk then
    table.insert(rows, metric_row("database", "DISK",
      disk.used_pct .. "%",
      string.format("%.0f GB free", disk.avail / 1073741824),
      th.level("disk_pct", disk.used_pct)))
  else
    -- Every running system has a root filesystem, so unlike the GPU rows a
    -- missing DISK reading always means something failed -- df absent, the
    -- subprocess blocked, or the result not yet returned. Show it dimmed
    -- rather than dropping the row, so the gap is visible instead of silent.
    table.insert(rows, metric_row("database", "DISK", "--", "", "unknown"))
  end

  table.insert(rows, ui.label({ text = "PRESSURE", color = "on_surface", fontWeight = "bold" }))
  for _, kind in ipairs({ "cpu", "memory", "io" }) do
    local text = noctalia.readFile("/proc/pressure/" .. kind)
    local p = text and parse.pressure(text) or nil
    -- A non-nil p only proves at least one PSI line parsed; a specific
    -- field can still be missing from a partially-parsed file. Guard the
    -- field itself, not just the table, or a missing some_avg60 falls
    -- through the "or 0" default and renders a confident, healthy "0.0".
    local some = (p and p.some_avg60) and string.format("%.1f", p.some_avg60) or "--"
    local full = (p and p.full_avg60) and string.format("%.1f", p.full_avg60) or "--"

    -- cpu/io pressure are shown for information only -- they mirror no
    -- calibrated threshold (only psi_mem_full does, matching memory-notify)
    -- so they are never coloured as alarming. But an unreadable row MUST
    -- still dim: a healthy colour beside "--" tells the user two
    -- contradictory things at once.
    local level
    if not p then
      level = "unknown"
    elseif kind == "memory" then
      level = th.level("psi_mem_full", p.full_avg60)
    else
      level = "ok"
    end
    table.insert(rows, metric_row("activity", "  " .. kind,
      "some " .. some, "full " .. full, level))
  end

  return rows
end

-- Assigns the forward-declared local from above -- deliberately NOT
-- `local function render()`, which would shadow it with a second, separate
-- local and leave the watch callbacks' captured upvalue nil forever.
render = function()
  panel.render(ui.column({ gap = 8, padding = 16 }, {
    ui.row({ justify = "space_between", align = "center" }, {
      ui.label({ text = "System", fontSize = 16, fontWeight = "bold" }),
      ui.button({ glyph = "close", onClick = "onClose" }),
    }),
    ui.column({ gap = 6 }, build_rows()),
  }))
end

-- Disk free changes slowly and has no /proc source (needs statvfs, which the
-- Luau API does not expose), so it refreshes once on panel open rather than
-- joining the per-tick poll loop.
local function refresh_disk()
  noctalia.runAsync("df --output=avail,size -B1 / | tail -1", function(result)
    if result and result.stdout then
      disk = parse.df(result.stdout)
      render()
    end
  end)
end

-- Ticked once a second while the panel is open, but ONLY once opted in via
-- panel.setWantsSecondTicks(true) in onOpen below. noctalia.setUpdateInterval
-- is the wrong API here -- that only wires up widgets/desktop-widgets/
-- services (confirmed by reading the actual dispatch in plugin_panel.cpp:
-- the panel tick timer is fixed at 1000ms and reacts only to
-- patch.wantsSecondTicks, never to patch.updateIntervalMs). The runtime also
-- calls update() once, unconditionally, right after the script's initial
-- load -- that single bootstrap call is not a tick and must not be treated
-- as one; it runs before setWantsSecondTicks(true) has even been requested.
-- The official notes panel (panel.luau:359) does exactly this same
-- setWantsSecondTicks(true) call for its own idle-autosave ticks -- that is
-- what "shipped code" actually showed, not a self-declared interval inside
-- update() the way the bar widget does it (widgets and panels are ticked by
-- two different, unrelated mechanisms in the host).
function update()
  local text = noctalia.readFile("/proc/stat")
  if not text then return end
  local total, idle = parse.cpu_jiffies(text)

  -- A readable but malformed /proc/stat yields (0,0). Rendering that as a
  -- delta produces a confident "0%" -- reject it and leave the previous
  -- baseline intact, exactly as widget.luau's cpu_usage() does.
  if total == 0 and idle == 0 then return end

  -- First tick (including the first tick after a reopen, since onClose
  -- wipes the baseline below) has no previous sample -- seed it and wait
  -- for the next tick rather than reporting a whole-uptime average.
  if cpu_prev_total == 0 then
    cpu_prev_total, cpu_prev_idle = total, idle
    return
  end

  cpu_pct = parse.cpu_percent(cpu_prev_total, cpu_prev_idle, total, idle)
  cpu_prev_total, cpu_prev_idle = total, idle
  render()
end

function onOpen()
  is_open = true
  -- No start_streams() call here any more -- the widget owns the GPU
  -- streams for the whole session now (see the long comment on `gpu` near
  -- the top of this file), so opening this panel neither starts nor
  -- restarts anything; gpu.nvidia/gpu.intel/gpu_available were already
  -- seeded at script load and kept current by the watch callbacks the
  -- whole time this panel was closed, exactly like a non-owner widget
  -- instance on the other monitor.
  refresh_disk()
  -- Opts this panel into the host's 1s tick timer so update() above keeps
  -- firing while the panel stays open -- without this call update() runs
  -- exactly once, at script load, and cpu_pct would never advance past its
  -- seeded first-tick "--" state. See the long comment on update() for how
  -- this was confirmed against the host's C++ source, not guessed.
  panel.setWantsSecondTicks(true)
  render()
end
function onClose()
  is_open = false
  -- No stop_streams() call here any more -- see onOpen. Closing this panel
  -- must not stop the GPU streams: they belong to the widget's bar-graph
  -- for the whole session, not to this panel's lifetime, and the widget on
  -- this monitor may or may not even be the current stream owner. gpu.*/
  -- gpu_available are also deliberately left as-is (not wiped) -- a
  -- reopened panel should show the last-known reading immediately, sourced
  -- from state, rather than a manufactured "no data yet" it would have to
  -- wait out again.
  --
  -- Wipe the CPU baseline, not just stop ticking: a reopened panel must
  -- seed a fresh sample rather than diff against a total from before the
  -- panel was closed, which could span minutes and read as a stale average
  -- rather than current load.
  cpu_prev_total, cpu_prev_idle = 0, 0
  cpu_pct = nil
  -- Belt and braces, not load-bearing: PluginPanel::onClose in the host
  -- (src/shell/panel/plugin_panel.cpp:228-230) calls m_tickTimer.stop()
  -- unconditionally, before it even looks at m_wantsSecondTicks, so the 1s
  -- tick already stops on close regardless of this call. Set it false here
  -- anyway so the request is explicitly released rather than left dangling
  -- until the next onOpen re-arms it -- symmetry with the true-on-open
  -- above, and it costs nothing if the host's internals ever change.
  panel.setWantsSecondTicks(false)
  panel.close()
end
-- No onExit() any more: this panel owns no streams (or anything else) that
-- needs teardown on reload/stop -- see widget.luau's onExit for where that
-- responsibility now lives.
