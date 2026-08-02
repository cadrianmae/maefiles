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

-- GPU state lives only while the panel is open (see start_streams/
-- stop_streams below) -- the panel is the only consumer of GPU data, so
-- nothing runs in the background when it is shut. gpu.nvidia/gpu.intel stay
-- nil until the first line arrives from each stream, and are wiped again on
-- close so a reopened panel never shows a stale reading from before.
local gpu = { nvidia = nil, intel = nil }
local intel_prev = { render = nil, ts = nil }
local streams = { nvidia = nil, intel = nil }

local HELPER = "/usr/libexec/ksystemstats_intel_helper"
local NVIDIA_CMD = "nvidia-smi dmon -d 2 -s pucm"

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
    cpu_temp and (cpu_temp .. " C") or "--",
    "",
    th.level("cpu_temp", cpu_temp)))

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

local function render()
  panel.render(ui.column({ gap = 8, padding = 16 }, {
    ui.row({ justify = "space_between", align = "center" }, {
      ui.label({ text = "System", fontSize = 16, fontWeight = "bold" }),
      ui.button({ glyph = "close", onClick = "onClose" }),
    }),
    ui.column({ gap = 6 }, build_rows()),
  }))
end

-- Streams live only while the panel is open. Neither GPU exposes utilisation
-- in sysfs; this copies KDE's approach exactly (see NvidiaSmiProcess.cpp and
-- the ksystemstats Intel helper upstream) rather than polling anything
-- ourselves. The panel is the only consumer, so nothing runs when it is
-- shut -- no timers, no background processes.
--
-- DEVIATION FROM THE ORIGINAL BRIEF, found empirically (live probe: a
-- boolean, not a table, came back from runStream; logged via noctalia.log)
-- and confirmed against docs.noctalia.dev/v5/plugins/development/runtime-api/:
-- `noctalia.runStream(cmd, onLine)` returns a plain bool, not a handle --
-- unlike httpStream(), it has no stop(). The docs state streams are only
-- reaped "when the script reloads, the entry is removed, or Noctalia stops
-- the plugin" -- none of which happen on a panel close. Calling the
-- documented-nonexistent handle.stop() is exactly what threw
-- "attempt to index boolean with 'stop'" the first time this ran live.
-- The only way to actually stop these two specific processes from Lua is to
-- kill them by their exact command line via a one-shot runAsync (pkill
-- excludes its own invocation by default, so this cannot self-kill
-- noctalia). Track "did we start it" as a bool, not a fictional handle.
local function start_streams()
  if noctalia.commandExists("nvidia-smi") and not streams.nvidia then
    streams.nvidia = noctalia.runStream(NVIDIA_CMD, function(line)
      local n = parse.nvidia_dmon(line)
      if n then gpu.nvidia = n; render() end
    end)
  end

  -- Ships with ksystemstats and already carries cap_perfmon, so no
  -- system-wide perf_event_paranoid change is needed. Absent if KDE's
  -- ksystemstats package is uninstalled, in which case the Intel row is
  -- simply omitted (build_rows only adds it when gpu.intel is set).
  if noctalia.fileExists(HELPER) and not streams.intel then
    streams.intel = noctalia.runStream(HELPER, function(line)
      local i = parse.intel_helper(line)
      if not i then return end
      -- First line has no prior sample to diff against -- seed the
      -- baseline and skip rendering rather than showing a bogus 0%.
      if intel_prev.ts then
        gpu.intel = parse.intel_percent(intel_prev.render, intel_prev.ts, i.render, i.timestamp)
        render()
      end
      intel_prev.render, intel_prev.ts = i.render, i.timestamp
    end)
  end
end

local function stop_streams()
  if streams.nvidia then
    noctalia.runAsync("pkill -f '" .. NVIDIA_CMD .. "'")
    streams.nvidia = nil
  end
  if streams.intel then
    noctalia.runAsync("pkill -f '" .. HELPER .. "'")
    streams.intel = nil
  end
  intel_prev.render, intel_prev.ts = nil, nil
  -- Wipe readings too, not just the handles: a reopened panel must show
  -- "no data yet" rather than a stale figure from the stream that just
  -- stopped, until fresh lines arrive.
  gpu.nvidia, gpu.intel = nil, nil
end

function onOpen() start_streams(); render() end
function onClose() stop_streams(); panel.close() end
function onExit(signal, reason) stop_streams() end
