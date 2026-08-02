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
  local path = os.getenv("HOME") .. "/scripts/noctalia-sysmon/fixtures/" .. f
  local h, err = io.open(path)
  if not h then
    error("fixture missing: " .. path .. " (" .. tostring(err) .. ")")
  end
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

-- mem_total == 0 is not a real machine state (unlike swap == 0, which is
-- legitimate with no swap configured) -- unparseable input must be nil, not
-- a zero-filled table that would silently render as a healthy 0kB.
check("meminfo empty returns nil", parse.meminfo("") == nil)
check("meminfo garbage returns nil", parse.meminfo("not meminfo at all") == nil)
check("meminfo without MemTotal returns nil", parse.meminfo("MemFree: 100 kB\n") == nil)
check("meminfo with no swap still returns a table",
      type(parse.meminfo("MemTotal: 100 kB\nMemAvailable: 40 kB\n")) == "table")

local ta, ia = parse.cpu_jiffies(read("stat_a.txt"))
local tb, ib = parse.cpu_jiffies(read("stat_b.txt"))
check("jiffies total increases", tb > ta)
check("jiffies idle does not decrease", ib >= ia)

check("cpu_jiffies garbage returns 0,0", (function()
        local t, i = parse.cpu_jiffies("no cpu line here")
        return t == 0 and i == 0
      end)())

-- stat_full.txt is a real, unfiltered /proc/stat capture with cpu0/cpu1/...
-- per-core lines below the aggregate. Parsing it must land on the same
-- values as parsing just its own "cpu " aggregate line in isolation --
-- proving the pattern picks the aggregate and not a per-core line.
local full = read("stat_full.txt")
local aggregate_line = string.match(full, "^([^\n]+)")
local tf, ifj = parse.cpu_jiffies(full)
local tl, il = parse.cpu_jiffies(aggregate_line)
check("cpu_jiffies on full /proc/stat matches its own aggregate-only line",
      tf == tl and ifj == il)

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
