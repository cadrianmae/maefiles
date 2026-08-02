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

function update()
  noctalia.setUpdateInterval(2000)

  local cpu = cpu_usage()
  local ram = ram_percent()
  local psi_cpu, psi_mem, psi_io = psi_triplet()

  local cpu_color = th.color(th.level("cpu_usage", cpu))
  local ram_color = th.color(th.level("ram_pct", ram))

  -- Only psi_mem_full has calibrated thresholds (they mirror memory-notify
  -- and must not be extended casually to cpu/io pressure -- that would be a
  -- design decision, not a bug fix). But the three PSI numbers share one
  -- glyph+label, so if ANY of them is unreadable, dim the whole thing:
  -- otherwise the shared colour could read "ok" while one of the three
  -- values on screen is "--", which is a text/colour disagreement. A high
  -- but readable cpu/io figure not colouring the element is acceptable --
  -- the number is right there.
  local psi_level
  if psi_cpu == nil or psi_mem == nil or psi_io == nil then
    psi_level = "unknown"
  else
    psi_level = th.level("psi_mem_full", psi_mem)
  end
  local psi_color = th.color(psi_level)

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
