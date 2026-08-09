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

-- One line per GPU per tick from ~/bin/sysmon-gpu, which reframes nvtop's
-- multi-line JSON into something a line-based runStream can consume:
--
--   AVAIL|intel,nvidia     once, at stream start
--   INTEL|30               utilisation percent
--   NVIDIA|43|9|18         temp C | utilisation % | VRAM used %
--
-- Replaces the two previous sources, parse.nvidia_dmon (nvidia-smi dmon) and
-- parse.intel_helper (KDE's ksystemstats_intel_helper), with one. The Intel
-- helper had to go -- ksystemstats pulls the Plasma stack this machine was
-- reinstalled to shed -- and once nvtop was the Intel source, running
-- nvidia-smi alongside it meant two streams for data one process already had.
--
-- AVAIL is what the widget's availability probe used to derive from
-- commandExists/fileExists. nvtop enumerating the devices is better evidence
-- of what exists than which binaries happen to be installed.
--
-- No percent arithmetic here anymore: nvtop reports utilisation directly, so
-- the old intel_percent() busy-nanoseconds-over-elapsed-nanoseconds delta
-- (and the prior-sample baseline it needed) is gone with it.
function parse.gpu_line(line)
  if not line then return nil end

  local avail = string.match(line, "^AVAIL|(.*)$")
  if avail then
    local out = { kind = "avail", intel = false, nvidia = false }
    for name in string.gmatch(avail, "[^,]+") do
      if name == "intel" then out.intel = true end
      if name == "nvidia" then out.nvidia = true end
    end
    return out
  end

  local intel = string.match(line, "^INTEL|(%d+)$")
  if intel then
    return { kind = "intel", pct = tonumber(intel) }
  end

  local temp, usage, mem = string.match(line, "^NVIDIA|(%d+)|(%d+)|(%d+)$")
  if temp then
    return {
      kind = "nvidia",
      temp = tonumber(temp),
      usage = tonumber(usage),
      mem_usage = tonumber(mem),
    }
  end

  return nil
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
