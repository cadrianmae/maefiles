-- Bar widget: CPU, RAM and pressure figures. noctalia's Luau runtime has no
-- require/load (proven Task 2), so parse.luau and thresholds.luau are
-- inlined below rather than imported. lib/*.luau stay the source of truth;
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

local prev_total, prev_idle = 0, 0

-- This bar instance's own output (e.g. "eDP-1" / "HDMI-A-1"). The plugin
-- loads once PER MONITOR (confirmed by reading the host source:
-- shell/bar/widget_factory.cpp constructs one PluginWidget -- and therefore
-- one Luau ScriptRuntime, since PluginWidget owns m_runtime -- per bar per
-- output; this machine runs 2 bars, so this script's module-level code runs
-- twice, independently, with no shared memory between the two runs). Used
-- below as this instance's identity in the cross-monitor stream-ownership
-- claim -- readable in logs/state, unlike a random id, and stable across
-- reloads of the same monitor's widget.
local my_output = barWidget.outputName() or "unknown"

-- BEGIN GPU stream ownership + state (moved here from panel.luau; the panel
-- now only reads noctalia.state, it owns no streams of its own -- see the
-- long comment on update_ownership below for why this widget must arbitrate
-- rather than simply "always start streams").
local OWNER_KEY = "sysmon_gpu_owner"
local NVIDIA_KEY = "sysmon_gpu_nvidia"
local INTEL_KEY = "sysmon_gpu_intel"
local AVAILABLE_KEY = "sysmon_gpu_available"

local is_owner = false
local owner_confirm_ticks = 0

-- Local cache of the GPU figures, always sourced from noctalia.state (never
-- written directly from this instance's own stream callbacks -- see
-- start_streams below). This makes every widget instance, owner or not,
-- read GPU data the same way: the owner's own state.set() calls loop back
-- through its own watch callback exactly like a non-owner's do, so there is
-- only one code path that updates these, not two that could drift apart.
local gpu_nvidia = nil -- { temp, usage, mem_usage } or nil
local gpu_intel = nil -- number (percent) or nil
local gpu_available = { nvidia = false, intel = false }

local intel_prev = { render = nil, ts = nil }
local streams = { nvidia = nil, intel = nil }
local stream_pids = { nvidia = nil, intel = nil }

local HELPER = "/usr/libexec/ksystemstats_intel_helper"
-- Wrapped in `sh -c 'echo NOCTALIA_PID:$$; exec <cmd>'` so stop_streams can
-- recover an exact, killable PID with no pattern matching -- see the long
-- comment this carries over from panel.luau's original start_streams/
-- stop_streams, reproduced in full below on stop_streams.
local NVIDIA_CMD = "sh -c 'echo NOCTALIA_PID:$$; exec nvidia-smi dmon -d 2 -s pucm'"
local HELPER_CMD = "sh -c 'echo NOCTALIA_PID:$$; exec " .. HELPER .. "'"

-- Rolling history for the bar graph. Sized to the graph's own pixel width
-- (40) so each history slot is roughly one pixel column -- more samples than
-- that would just be invisible sub-pixel data, fewer would leave columns
-- blank. At the 2s widget tick used below, 40 samples is ~80s of visible
-- trend, enough to read a spike-and-recover shape at a glance without the
-- bar element dominating the row (matches the glyph-sized RAM/PSI elements
-- it sits beside).
local HISTORY_LEN = 40
local GRAPH_WIDTH, GRAPH_HEIGHT = 40, 16
local cpu_history = {}
local gpu_history = {}

local function push_history(t, v)
  table.insert(t, v)
  if #t > HISTORY_LEN then table.remove(t, 1) end
end

-- ui.graph wants 0-1; a momentarily bogus sensor read (or simple rounding at
-- the 100% boundary) above 100 or below 0 must not corrupt the graph's
-- vertical scale, so clamp defensively rather than trust the caller already
-- did.
local function clamp01(v)
  if v < 0 then return 0 end
  if v > 1 then return 1 end
  return v
end

-- Seed from whatever is already in state (e.g. this monitor's widget loaded
-- after the other one is already the confirmed owner and has been
-- publishing for a while), then watch for further updates. noctalia.state
-- watchers do NOT replay the current value on registration -- only future
-- set() calls -- so without this seed step a late-loading non-owner instance
-- would show "--" until the next GPU stream line arrives, even though a
-- perfectly good reading already exists in state.
gpu_nvidia = noctalia.state.get(NVIDIA_KEY)
gpu_intel = noctalia.state.get(INTEL_KEY)
gpu_available = noctalia.state.get(AVAILABLE_KEY) or { nvidia = false, intel = false }

noctalia.state.watch(NVIDIA_KEY, function(v)
  gpu_nvidia = v
  render()
end)
noctalia.state.watch(INTEL_KEY, function(v)
  gpu_intel = v
  render()
end)
noctalia.state.watch(AVAILABLE_KEY, function(v)
  gpu_available = v or { nvidia = false, intel = false }
  render()
end)

-- The higher of the two GPUs' usage. ui.graph only accepts two series from
-- Lua (values/values2 -- the C++ Graph class does have setValues3/setColor3,
-- but the prop whitelist in ui_tree_reconciler.cpp omits values3/color3, so
-- a third series is not reachable from a plugin at all). With CPU already
-- taking one series, both GPUs must share the other; the panel keeps
-- showing them as separate labelled rows, since it has room and the bar
-- does not.
local function higher_gpu_pct()
  local n = gpu_nvidia and gpu_nvidia.usage or nil
  local i = gpu_intel
  if n and i then return math.max(n, i) end
  return n or i
end

-- Cross-monitor stream ownership.
--
-- The widget owns both GPU helper streams for the session (moved here from
-- the panel, which used to start/stop them on open/close -- the bar needs
-- GPU data continuously, not just while a panel happens to be open). But the
-- plugin loads once per monitor (see my_output above), so a naive "just
-- start streams on load" would spawn two nvidia-smi dmon and two
-- ksystemstats_intel_helper processes on this two-monitor machine.
--
-- noctalia.state has no compare-and-swap -- get() and set() are each
-- individually atomic (mutex-protected in the host's PluginStateStore), but
-- the pair is not atomic across two independent widget instances. A plain
-- "if get() == nil then set(self)" can let both instances see nil and both
-- claim, each then seeing ITSELF on an immediate reread purely because of
-- how the two instances' get/set calls happened to interleave -- reread
-- alone cannot fully close this, since a widget's own reread only proves
-- what was true at that instant, not that a rival's write won't land right
-- after.
--
-- Rather than accept that (or invent a fake CAS this host doesn't provide),
-- ownership here is a claim that must be OBSERVED TO HOLD across two
-- consecutive ticks before streams actually start. This function runs once
-- per 2s widget tick (see update() below). Any tick where the recorded
-- owner is a different output demotes immediately, stopping this instance's
-- streams if it had any running. Because every instance re-derives its
-- belief from a fresh state.get() every single tick, whichever output's
-- write is temporally LAST once no one else is writing is the only one that
-- can observe itself as owner on two ticks running -- a loser's own next
-- get() will see the winner's name, not its own, and demote.
--
-- This bounds the worst case rather than eliminating it: if both monitors'
-- widgets load in the very same tick, both MAY start streams for up to one
-- extra tick (~2s) before the loser demotes -- documented, not hidden.
-- Verified empirically after a full noctalia restart that steady state (a
-- few ticks in) always settles to exactly one nvidia-smi dmon and one
-- ksystemstats_intel_helper -- see the task report for the pgrep output.
local start_streams, stop_streams, probe_gpu_availability

local function update_ownership()
  local current = noctalia.state.get(OWNER_KEY)
  if current == nil then
    noctalia.state.set(OWNER_KEY, my_output)
    owner_confirm_ticks = 0
    return
  end
  if current == my_output then
    owner_confirm_ticks = owner_confirm_ticks + 1
    if owner_confirm_ticks >= 2 and not is_owner then
      is_owner = true
      start_streams()
    end
  else
    owner_confirm_ticks = 0
    if is_owner then
      is_owner = false
      stop_streams()
    end
  end
end

probe_gpu_availability = function()
  gpu_available = {
    nvidia = noctalia.commandExists("nvidia-smi"),
    intel = noctalia.fileExists(HELPER),
  }
  noctalia.state.set(AVAILABLE_KEY, gpu_available)
end

-- Neither GPU exposes utilisation in sysfs; this copies KDE's approach
-- exactly (NvidiaSmiProcess.cpp and the ksystemstats Intel helper upstream)
-- rather than polling anything ourselves -- same approach panel.luau used to
-- take when it owned these streams. Every line is published to
-- noctalia.state rather than kept as widget-local state, so the panel (and
-- any other monitor's non-owner widget) can read it.
start_streams = function()
  probe_gpu_availability()

  if gpu_available.nvidia and not streams.nvidia then
    streams.nvidia = noctalia.runStream(NVIDIA_CMD, function(line)
      local pid = string.match(line, "^NOCTALIA_PID:(%d+)$")
      if pid then stream_pids.nvidia = pid; return end
      local n = parse.nvidia_dmon(line)
      if n then noctalia.state.set(NVIDIA_KEY, n) end
    end)
  end

  -- Ships with ksystemstats and already carries cap_perfmon, so no
  -- system-wide perf_event_paranoid change is needed. Absent if KDE's
  -- ksystemstats package is uninstalled, in which case gpu_available.intel
  -- stays false and the panel's INTEL row (sourced from AVAILABLE_KEY) is
  -- omitted entirely, same as before this task.
  if gpu_available.intel and not streams.intel then
    streams.intel = noctalia.runStream(HELPER_CMD, function(line)
      local pid = string.match(line, "^NOCTALIA_PID:(%d+)$")
      if pid then stream_pids.intel = pid; return end
      local i = parse.intel_helper(line)
      if not i then return end
      -- First line has no prior sample to diff against -- seed the
      -- baseline and skip publishing rather than a bogus 0%.
      if intel_prev.ts then
        local pct = parse.intel_percent(intel_prev.render, intel_prev.ts, i.render, i.timestamp)
        noctalia.state.set(INTEL_KEY, pct)
      end
      intel_prev.render, intel_prev.ts = i.render, i.timestamp
    end)
  end
end

-- Carried over verbatim from panel.luau's original stop_streams (same PID
-- sentinel recovery, same SIGTERM-then-SIGKILL escalation, same pkill -x -f
-- last resort for a stream whose sentinel never arrived) -- this is the
-- "careful teardown" the panel used to be solely responsible for, now owned
-- by the widget instead of duplicated in both places.
--
-- Deliberately does NOT clear gpu_nvidia/gpu_intel/gpu_available: those are
-- read from noctalia.state, which the new owner (if any) will overwrite
-- with fresh readings within a couple of ticks. Wiping them here would just
-- mean every reader (this instance's own graph, the other monitor's widget,
-- the panel) shows "no data" for that gap instead of a briefly-stale last
-- reading -- an honest tradeoff, not obviously better either way, so this
-- keeps the simpler behaviour (do nothing) rather than adding code to chase
-- a marginal improvement.
stop_streams = function()
  if stream_pids.nvidia then
    noctalia.runAsync("sh -c 'kill " .. stream_pids.nvidia ..
      " 2>/dev/null; sleep 2; kill -9 " .. stream_pids.nvidia .. " 2>/dev/null' &")
  elseif streams.nvidia then
    noctalia.runAsync("pkill -x -f 'nvidia-smi dmon -d 2 -s pucm'")
  end
  stream_pids.nvidia = nil

  if stream_pids.intel then
    noctalia.runAsync("sh -c 'kill " .. stream_pids.intel ..
      " 2>/dev/null; sleep 2; kill -9 " .. stream_pids.intel .. " 2>/dev/null' &")
  elseif streams.intel then
    noctalia.runAsync("pkill -x -f '" .. HELPER .. "'")
  end
  stream_pids.intel = nil

  streams.nvidia, streams.intel = nil, nil
  intel_prev.render, intel_prev.ts = nil, nil
end
-- END GPU stream ownership + state

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

  -- A readable but malformed /proc/stat yields (0,0). Rendering that as a
  -- delta produces a confident "0%" -- the same plausible lie the
  -- zero-baseline guard exists to prevent -- and writing it back would
  -- re-arm that guard, costing a second spurious "--" tick afterwards.
  -- Leave the previous baseline intact and report unreadable.
  if total == 0 and idle == 0 then
    return nil
  end

  -- The first tick after a restart has no previous sample, so a delta
  -- against zero would report the whole-uptime average and read as a real
  -- current figure. Seed the counters and report unreadable for one tick
  -- rather than render a plausible lie.
  if prev_total == 0 then
    prev_total, prev_idle = total, idle
    return nil
  end

  local pct = parse.cpu_percent(prev_total, prev_idle, total, idle)
  prev_total, prev_idle = total, idle
  return pct
end

local function ram_percent()
  local text = noctalia.readFile("/proc/meminfo")
  if not text then return nil end
  local m = parse.meminfo(text)
  if not m then return nil end
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

-- Last computed RAM/PSI figures, cached so render() can be called from a
-- GPU state.watch callback (which fires between ticks, with no cpu/ram/psi
-- reading of its own to hand render()) as well as from update() itself.
-- CPU has no such cache -- the graph reads cpu_history directly, and the bar
-- no longer shows a standalone CPU percent (replaced by the graph), so
-- there is nothing scalar left to remember between ticks.
local last_ram = nil
local last_psi_cpu, last_psi_mem, last_psi_io = nil, nil, nil

function render()
  local ram_color = th.color(th.level("ram_pct", last_ram))

  -- Only psi_mem_full has calibrated thresholds (they mirror memory-notify
  -- and must not be extended casually to cpu/io pressure -- that would be a
  -- design decision, not a bug fix). But the three PSI numbers share one
  -- glyph+label, so if ANY of them is unreadable, dim the whole thing:
  -- otherwise the shared colour could read "ok" while one of the three
  -- values on screen is "--", which is a text/colour disagreement. A high
  -- but readable cpu/io figure not colouring the element is acceptable --
  -- the number is right there.
  local psi_level
  if last_psi_cpu == nil or last_psi_mem == nil or last_psi_io == nil then
    psi_level = "unknown"
  else
    psi_level = th.level("psi_mem_full", last_psi_mem)
  end
  local psi_color = th.color(psi_level)

  barWidget.render(ui.row({ gap = 8, align = "center", onClick = "onClick" }, {
    -- CPU icon+percentage replaced by a two-series graph: series 1 is CPU
    -- usage, series 2 is the higher of the two GPUs (see higher_gpu_pct).
    -- "primary"/"tertiary" are plain distinct palette roles, not health
    -- colours from thresholds.color -- a graph trend line has no single
    -- "level" to colour by the way a scalar percent does, and borrowing
    -- thresholds.color's roles here would falsely imply the GPU series is
    -- always "critical" (thresholds.color's "error"/red role) rather than
    -- just being a different series. RAM and PSI keep using thresholds.color
    -- exactly as before -- they are unchanged by this task.
    ui.graph({
      width = GRAPH_WIDTH,
      height = GRAPH_HEIGHT,
      values = cpu_history,
      values2 = gpu_history,
      color = "primary",
      color2 = "tertiary",
      lineWidth = 1,
      fillOpacity = 0.15,
    }),
    ui.glyph({ name = "device-sd-card", size = 14, color = ram_color }),
    ui.label({ text = fmt_pct(last_ram), color = ram_color, fontWeight = "bold" }),
    ui.glyph({ name = "activity", size = 14, color = psi_color }),
    ui.label({
      text = fmt_psi(last_psi_cpu) .. "/" .. fmt_psi(last_psi_mem) .. "/" .. fmt_psi(last_psi_io),
      color = psi_color,
      fontWeight = "bold",
    }),
  }))
end

function update()
  noctalia.setUpdateInterval(2000)

  update_ownership()

  local cpu = cpu_usage()
  last_ram = ram_percent()
  last_psi_cpu, last_psi_mem, last_psi_io = psi_triplet()

  -- History is sampled once per tick, in lockstep with cpu/ram/psi, so both
  -- graph series share one cadence regardless of how often GPU stream lines
  -- actually arrive (nvidia-smi dmon ticks on its own -d 2 schedule, the
  -- Intel helper on its own). A tick with no valid reading is skipped
  -- entirely, not padded with a fabricated 0 -- see clamp01/higher_gpu_pct
  -- above and the "no misleading flat line" requirement this satisfies.
  if cpu then
    push_history(cpu_history, clamp01(cpu / 100))
  end
  local gpu_pct = higher_gpu_pct()
  if gpu_pct then
    push_history(gpu_history, clamp01(gpu_pct / 100))
  end

  render()
end

function onClick()
  noctalia.togglePanel("mae/sysmon:panel")
end

-- The widget now owns the GPU streams for the whole session (moved from the
-- panel, which used to stop them on every close) and must apply the same
-- careful teardown the panel used to: on any exit (script reload, plugin
-- entry removed, noctalia shutting down), stop this instance's own streams,
-- and if this instance was the confirmed owner, release the ownership claim
-- so the other monitor's widget (if any) can pick it up on its very next
-- tick instead of waiting forever for a claim held by a process that no
-- longer exists.
function onExit(signal, reason)
  stop_streams()
  if is_owner then
    noctalia.state.set(OWNER_KEY, nil)
  end
end
