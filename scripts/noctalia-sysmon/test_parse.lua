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

-- Pins the reasoning behind widget.luau's and panel.luau's first-tick
-- guard: a zero baseline is indistinguishable from a real "no previous
-- sample" state to this function, so it happily returns the whole-uptime
-- average as if it were a normal delta. Both callers (cpu_usage() in
-- widget.luau, update() in panel.luau) must special-case prev_total == 0
-- and skip this call for one tick rather than trust it.
check("cpu_percent from a zero baseline is the uptime average, not current",
      parse.cpu_percent(0, 0, 1000, 900) == 10)

-- Pins the reasoning behind widget.luau's and panel.luau's
-- (total==0 and idle==0) guard: a malformed-but-readable /proc/stat gives
-- cpu_jiffies (0,0), and a negative delta against a real prior baseline is
-- silently clamped to 0 here -- a confident "0%" that is just as much a
-- lie as the zero-baseline case. Both callers must reject a (0,0) current
-- sample outright and keep the previous baseline intact, not overwrite it
-- with the malformed read.
check("cpu_percent with a zeroed current sample is not a real 0",
      parse.cpu_percent(1000, 900, 0, 0) == 0)

local p = parse.pressure(read("pressure_memory.txt"))
check("pressure returns a table", type(p) == "table")
check("full_avg10 is a number", type(p.full_avg10) == "number")
check("full_avg60 is a number", type(p.full_avg60) == "number")

local pc = parse.pressure(read("pressure_cpu.txt"))
check("cpu pressure parses (no full line on some kernels)",
      type(pc) == "table" and type(pc.some_avg10) == "number")

check("garbage returns nil", parse.pressure("not pressure data") == nil)
check("empty returns nil", parse.pressure("") == nil)

local graph_history = require("graph_history")

-- graph_history pins the index-alignment property widget.luau's bar graph
-- depends on: two series fed to a single ui.graph must stay the same
-- length at all times, because the host stretches each series
-- independently across the same pixel width (confirmed by reading
-- Graph::sync/GraphNode in the host source) -- a shorter series renders at
-- a different time-per-pixel than a longer one, so "index i" in one no
-- longer means the same tick as "index i" in the other. This was the
-- concrete bug: the previous version of update() only called push() on a
-- valid reading, so cpu_history and gpu_history silently drifted apart in
-- length whenever the GPU had no reading for a tick (which is common right
-- after a fresh election, or after any transient stream hiccup) and never
-- resynced.
do
  local cpu, gpu = {}, {}
  local n = 6
  for i = 1, n do
    graph_history.push(cpu, i * 0.1, 40) -- CPU: always a reading
    if i == 2 or i == 4 then
      graph_history.push(gpu, nil, 40) -- GPU: absent on ticks 2 and 4
    else
      graph_history.push(gpu, i * 0.05, 40)
    end
  end
  check("push keeps both histories the same length even when one has gaps",
        #cpu == n and #gpu == n)

  local flat_cpu = graph_history.flatten(cpu, 3)
  local flat_gpu = graph_history.flatten(gpu, 3)
  check("flatten preserves length on the series with no gaps",
        #flat_cpu == n)
  check("flatten preserves length on the series WITH gaps -- this is the alignment property",
        #flat_gpu == n)
  check("flattened series stay the same length as each other",
        #flat_cpu == #flat_gpu)

  -- Tick 2's gap (interior, tail is fresh) is carried forward from tick 1's
  -- real value, not fabricated as 0 and not left as a length-breaking hole.
  check("interior gap is carried forward from the last real value, not zeroed",
        flat_gpu[2] == flat_gpu[1] and flat_gpu[2] > 0)
end

-- Nothing valid anywhere in the window -> empty series, not a zero-filled
-- one -- a flat line at zero would read as "idle", which is a specific
-- claim this history never actually observed.
do
  local h = {}
  for i = 1, 5 do graph_history.push(h, nil, 40) end
  check("all-invalid history flattens to an empty series",
        #graph_history.flatten(h, 3) == 0)
end

-- Tail gone stale (3+ consecutive misses counted back from "now") blanks
-- the WHOLE series, even though older entries in the window were valid --
-- this is the rule that stops a dead stream's last real reading from
-- sitting frozen at the graph's right ("now") edge forever, indistinguishable
-- from a live current value.
do
  local h = {}
  graph_history.push(h, 0.5, 40)
  graph_history.push(h, 0.6, 40)
  for i = 1, 3 do graph_history.push(h, nil, 40) end -- 3 consecutive misses at the tail
  check("a tail stale for >= stale_ticks blanks the whole series, not just the tail",
        #graph_history.flatten(h, 3) == 0)
end

-- One or two dropped samples must NOT blank the series -- only genuine,
-- sustained staleness should stop the line, not an isolated missed line
-- (e.g. one unparseable dmon line).
do
  local h = {}
  graph_history.push(h, 0.5, 40)
  graph_history.push(h, nil, 40)
  graph_history.push(h, nil, 40)
  local flat = graph_history.flatten(h, 3)
  check("a short gap below the stale threshold keeps the series alive",
        #flat == 3)
  check("a short trailing gap carries the last real value forward, not zero",
        flat[3] == 0.5)
end

-- Leading gap (no valid sample yet at the very start of the window, e.g.
-- the first tick or two right after a fresh GPU stream election) is
-- back-filled with the first real value once one arrives, rather than left
-- as a hole that would break the equal-length guarantee.
do
  local h = {}
  graph_history.push(h, nil, 40)
  graph_history.push(h, nil, 40)
  graph_history.push(h, 0.3, 40)
  local flat = graph_history.flatten(h, 3)
  check("leading gap before any real value is back-filled with the first real value",
        flat[1] == 0.3 and flat[2] == 0.3 and flat[3] == 0.3)
end

-- max_len cap still holds with push()'s new { v, ok } shape -- a
-- regression here would let the graph history grow unbounded.
do
  local h = {}
  for i = 1, 50 do graph_history.push(h, i * 0.01, 10) end
  check("push still caps history length at max_len", #h == 10)
end

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

-- Activity boundary tests for metrics that were missing them
check("disk just below activity",        th.level("disk_pct", 79) == "ok")
check("disk at activity",                th.level("disk_pct", 80) == "activity")
check("disk just below critical",        th.level("disk_pct", 91) == "activity")
check("cpu temp just below activity",    th.level("cpu_temp", 74) == "ok")
check("cpu temp at activity",            th.level("cpu_temp", 75) == "activity")
check("cpu temp just below critical",    th.level("cpu_temp", 89) == "activity")
check("gpu temp just below activity",    th.level("gpu_temp", 74) == "ok")
check("gpu temp at activity",            th.level("gpu_temp", 75) == "activity")
check("gpu temp just below critical",    th.level("gpu_temp", 86) == "activity")

-- Unreadable sensor distinction from unknown metric name
check("nil value is unknown, not ok",    th.level("cpu_usage", nil) == "unknown")
check("non-number value is unknown",     th.level("cpu_usage", "abc") == "unknown")
check("unknown metric name stays ok",    th.level("nonsense", 999) == "ok")
check("unknown maps to a dimmed token",  th.color("unknown") == "on_surface/0.4")
check("unknown is not the same as ok",   th.color("unknown") ~= th.color("ok"))

-- nvidia-smi dmon: two header lines start with '#'; data lines are
-- whitespace-separated numbers. Real column order, captured on this machine
-- into fixtures/nvidia_dmon.txt via `nvidia-smi dmon -d 2 -s pucm`, is:
-- gpu pwr gtemp mtemp sm mem enc dec jpg ofa mclk pclk fb bar1 ccpm -- this
-- matches the brief's assumed order exactly.
check("dmon header returns nil", parse.nvidia_dmon("# gpu   pwr gtemp") == nil)
check("dmon second header returns nil", parse.nvidia_dmon("# Idx      W      C") == nil)

local n = parse.nvidia_dmon("    0    12    41     -    45     8     0     0")
check("dmon data returns a table", type(n) == "table")
check("dmon gives a numeric usage", type(n.usage) == "number")
check("dmon gives a numeric temp", type(n.temp) == "number")

-- mtemp is "-" (no dedicated memory-temp sensor) in real captures. A naive
-- table.insert(fields, tonumber(tok)) silently skips that nil and shifts
-- every later column left by one -- sm (usage) would read as 8 (mem) and
-- mem_usage would read as 0 (enc). Pin literal values, not just their type,
-- so that regression cannot creep back in.
check("dmon temp is gtemp not shifted", n.temp == 41)
check("dmon usage is sm not shifted", n.usage == 45)
check("dmon mem_usage is mem not shifted", n.mem_usage == 8)

local dmon_fixture = read("nvidia_dmon.txt")
local dmon_data_line = string.match(dmon_fixture, "\n[^\n]*\n[^\n]*\n([^\n]+)")
local n2 = parse.nvidia_dmon(dmon_data_line)
check("dmon real fixture line parses", type(n2) == "table")
check("dmon real fixture gives numeric temp", type(n2) == "table" and type(n2.temp) == "number")

check("dmon garbage returns nil", parse.nvidia_dmon("not dmon data at all") == nil)
check("dmon nil line returns nil", parse.nvidia_dmon(nil) == nil)

-- panel.luau's NVIDIA_CMD/HELPER_CMD wrap each stream in
-- `sh -c 'echo NOCTALIA_PID:$$; exec <cmd>'` so stop_streams can recover an
-- exact, killable PID (see panel.luau for why runStream gives no handle).
-- The panel's onLine callback intercepts that sentinel line before it ever
-- reaches these parsers, but both must independently reject it as
-- unparseable too -- belt and suspenders, not a single point of failure.
check("dmon sentinel line is not misread as data", parse.nvidia_dmon("NOCTALIA_PID:12345") == nil)

local i = parse.intel_helper("1000176177|Frequency|191|Interrupts|872|Render|457711853|Copy|0|Video|0|Enhance|0")
check("intel returns a table", type(i) == "table")
check("intel timestamp parsed", i.timestamp == 1000176177)
check("intel render counter parsed", i.render == 457711853)
check("intel garbage returns nil", parse.intel_helper("nonsense") == nil)
check("intel nil line returns nil", parse.intel_helper(nil) == nil)
check("intel sentinel line is not misread as data", parse.intel_helper("NOCTALIA_PID:12345") == nil)

local intel_fixture = read("intel_helper.txt")
local intel_first_line = string.match(intel_fixture, "^([^\n]+)")
local i2 = parse.intel_helper(intel_first_line)
check("intel real fixture line parses", type(i2) == "table" and type(i2.render) == "number")

-- Counter deltas, not absolute values: the helper reports cumulative
-- nanoseconds busy, exactly as KDE's LinuxIntelGpu computes it.
check("intel percent from deltas",
      parse.intel_percent(0, 0, 500000000, 1000000000) == 50)
check("intel percent clamps at 100",
      parse.intel_percent(0, 0, 2000000000, 1000000000) == 100)
check("intel percent zero timedelta is 0",
      parse.intel_percent(0, 0, 100, 0) == 0)

-- df --output=avail,size -B1 / | tail -1 prints a header then one data line
-- of bytes; the test fixes literal figures so a used_pct rounding regression
-- can't creep back in silently.
local d = parse.df("Avail        Size\n412000000000 900000000000\n")
check("df returns a table", type(d) == "table")
check("df avail parsed", d.avail == 412000000000)
check("df size parsed", d.size == 900000000000)
check("df used percent", d.used_pct == 54)
check("df garbage returns nil", parse.df("no numbers here") == nil)

-- Drift test: widget.luau inlines parse.luau and thresholds.luau verbatim
-- (noctalia's Luau runtime has no require/load, see lib/parse.luau header).
-- Without this check the inlined copy and the library file can diverge
-- silently -- the library keeps passing its own tests while the widget
-- ships stale logic.
local function read_whole(path)
  local h, err = io.open(path)
  if not h then error("missing file: " .. path .. " (" .. tostring(err) .. ")") end
  local t = h:read("*a"); h:close(); return t
end

local function extract_between(text, begin_marker, end_marker)
  local pattern = "%-%- BEGIN INLINED " .. begin_marker ..
    "%.luau\n(.-)%-%- END INLINED " .. end_marker .. "%.luau"
  local body = string.match(text, pattern)
  if not body then error("markers not found for " .. begin_marker) end
  return body
end

local function strip_trailing_return(text, name)
  -- The inlined copy keeps "local X = {}" but drops the library's trailing
  -- "return X" -- strip that line here so the comparison lines up.
  local out = string.gsub(text, "\nreturn " .. name .. "%s*\n?$", "\n")
  return out
end

local function trim_trailing_ws(text)
  -- Trailing whitespace on lines and at EOF is cosmetic; strip per-line and
  -- overall so formatting nits don't cause false drift failures.
  local lines = {}
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    table.insert(lines, (line:gsub("%s+$", "")))
  end
  while #lines > 0 and lines[#lines] == "" do
    table.remove(lines)
  end
  return table.concat(lines, "\n")
end

local sysmon_dir = os.getenv("HOME") ..
  "/.local/state/noctalia/plugins/sources/local/sysmon/"
local lib_dir = sysmon_dir .. "lib/"

-- Both entries inline parse.luau and thresholds.luau independently (no
-- require/load in noctalia's Luau runtime, see lib/parse.luau header), so
-- each one can drift from the library on its own -- checking only
-- widget.luau would leave panel.luau free to go stale silently.
local entries = {
  widget = read_whole(sysmon_dir .. "widget.luau"),
  panel  = read_whole(sysmon_dir .. "panel.luau"),
}

local function strip_leading_comment(text, name)
  -- The library file opens with an explanatory header comment that isn't
  -- part of "the body" per the inlining spec (which keeps "local X = {}"
  -- as the first line of the inlined copy) -- drop everything before it.
  local from = string.find(text, "local " .. name .. " = {}", 1, true)
  if not from then error("could not find 'local " .. name .. " = {}' in source") end
  return string.sub(text, from)
end

local function check_drift(entry_name, entry_text, module_name)
  local inlined = extract_between(entry_text, module_name, module_name)
  local source = read_whole(lib_dir .. module_name .. ".luau")
  source = strip_leading_comment(source, module_name)
  source = strip_trailing_return(source, module_name)
  check(entry_name .. " inlined " .. module_name .. " matches lib/" .. module_name .. ".luau",
        trim_trailing_ws(inlined) == trim_trailing_ws(source))
end

for entry_name, entry_text in pairs(entries) do
  check_drift(entry_name, entry_text, "parse")
  check_drift(entry_name, entry_text, "thresholds")
end

-- graph_history.luau is only inlined into widget.luau -- panel.luau has no
-- bar graph and never used it -- so this one is checked on its own rather
-- than through the shared `entries` loop above.
check_drift("widget", entries.widget, "graph_history")

print(string.format("%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
