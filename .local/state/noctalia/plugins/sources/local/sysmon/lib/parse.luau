-- Pure parsers: string in, numbers out. No I/O, no globals.
-- Kept in the plain-Lua-compatible subset so test_parse.lua can run it under
-- /usr/bin/lua without noctalia.
--
-- NOTE (Task 2): noctalia's Luau runtime confirmed to have no `require` and
-- no `load` (a live pcall probe against a running noctalia instance hit
-- "attempt to call a nil value" on `load`). This file therefore cannot be
-- required or loaded-by-string at runtime by any entry script; it stays the
-- canonical, /usr/bin/lua-tested source of truth, and its body is inlined
-- (byte-for-byte, guarded by a drift test) into each entry that needs it.
-- See task-2-report.md for the investigation.
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

return parse
