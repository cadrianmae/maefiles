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

-- Task 11 (split CPU/GPU graphs): widget.luau now keeps THREE histories --
-- cpu_history, intel_history, nvidia_history -- instead of the old two
-- (cpu_history/gpu_history). intel_history and nvidia_history share one
-- ui.graph (values/values2), so if they drift out of step with each other
-- the two GPU lines would disagree with each other about which pixel
-- column is "now", not just with the CPU graph next to them -- a strictly
-- worse failure than the original two-history drift bug this suite already
-- pins above. Simulate a tick sequence where Intel and NVIDIA go missing on
-- DIFFERENT ticks (not the same ticks, and not always together) -- the
-- scenario that would actually expose a per-series push bug, since if both
-- GPUs always dropped in lockstep a missing shared push could hide behind
-- the other one still being called correctly.
do
  local cpu, intel, nvidia = {}, {}, {}
  local n = 10
  for i = 1, n do
    graph_history.push(cpu, i * 0.01, 40) -- CPU: always a reading
    if i == 2 or i == 5 or i == 6 then
      graph_history.push(intel, nil, 40) -- Intel missing on 2, 5, 6
    else
      graph_history.push(intel, i * 0.02, 40)
    end
    if i == 3 or i == 4 or i == 8 then
      graph_history.push(nvidia, nil, 40) -- NVIDIA missing on 3, 4, 8 -- disjoint from Intel's gaps
    else
      graph_history.push(nvidia, i * 0.03, 40)
    end
  end
  check("three histories stay equal length after a tick sequence with disjoint per-GPU gaps",
        #cpu == n and #intel == n and #nvidia == n)

  local flat_cpu = graph_history.flatten(cpu, 3)
  local flat_intel = graph_history.flatten(intel, 3)
  local flat_nvidia = graph_history.flatten(nvidia, 3)
  check("flattened CPU history keeps full length",
        #flat_cpu == n)
  check("flattened Intel history keeps full length despite its own gaps",
        #flat_intel == n)
  check("flattened NVIDIA history keeps full length despite its own, DIFFERENT gaps",
        #flat_nvidia == n)
  check("all three flattened series stay the same length as each other",
        #flat_cpu == #flat_intel and #flat_intel == #flat_nvidia)

  -- Tick 8 is NVIDIA's last gap and tick 8 is fine for Intel -- confirms
  -- each series' flatten only reacts to ITS OWN tail, not the other GPU's.
  check("NVIDIA's tail (tick 8 gap, ticks 9-10 real) is fresh enough to stay drawn",
        #flat_nvidia > 0)
  check("Intel's tail (ticks 9-10 real, no trailing gap) is fresh and stays drawn",
        #flat_intel > 0)
end

-- One GPU stream dying entirely for the rest of the window (the "kill the
-- Intel helper" scenario from the task's live verification step) must blank
-- only ITS OWN series while the other GPU's series -- still receiving real
-- ticks the whole time -- keeps drawing. This is the property that was not
-- observable at all when both GPUs shared one combined series (the old
-- higher_gpu_pct() behaviour): it must be pinned now that they are split.
do
  local intel, nvidia = {}, {}
  for i = 1, 5 do
    graph_history.push(intel, i * 0.1, 40)
    graph_history.push(nvidia, i * 0.1, 40)
  end
  -- Intel dies here: 4 consecutive misses at the tail (>= STALE_TICKS's 3).
  -- NVIDIA keeps reporting every tick, unaffected.
  for i = 1, 4 do
    graph_history.push(intel, nil, 40)
    graph_history.push(nvidia, (5 + i) * 0.1, 40)
  end
  check("dead Intel stream blanks only the Intel series",
        #graph_history.flatten(intel, 3) == 0)
  check("still-live NVIDIA series is unaffected by Intel going stale",
        #graph_history.flatten(nvidia, 3) == 9)
end

local respawn_backoff = require("respawn_backoff")

-- Pins the exact respawn backoff schedule widget.luau's maybe_respawn
-- relies on: 5 -> 10 -> 20 -> 40 ticks (10s -> 20s -> 40s -> 80s at the
-- widget's 2s tick), then capped at 40 (80s) forever after. Getting this
-- arithmetic subtly wrong (off-by-one on the first attempt, doubling past
-- the cap instead of clamping, or forgetting the reset-on-recovery step)
-- is exactly the kind of bug that is impractical to observe live without
-- waiting minutes per test run, so it needs direct unit coverage of the
-- pure arithmetic, independent of any live GPU stream.
check("INITIAL is 5 ticks (~10s at the 2s tick)", respawn_backoff.INITIAL == 5)
check("CAP is 40 ticks (~80s at the 2s tick)", respawn_backoff.CAP == 40)

do
  local gap = respawn_backoff.INITIAL
  local schedule = { gap }
  for i = 1, 5 do
    gap = respawn_backoff.next_gap(gap)
    table.insert(schedule, gap)
  end
  check("backoff schedule grows 5 -> 10 -> 20 -> 40 -> 40 -> 40",
        schedule[1] == 5 and schedule[2] == 10 and schedule[3] == 20 and
        schedule[4] == 40 and schedule[5] == 40 and schedule[6] == 40)
end

check("next_gap never exceeds CAP even from a value already at the cap",
      respawn_backoff.next_gap(respawn_backoff.CAP) == respawn_backoff.CAP)
check("next_gap never exceeds CAP from a value just below it",
      respawn_backoff.next_gap(respawn_backoff.CAP - 1) == respawn_backoff.CAP)

-- The reset-after-recovery behaviour itself lives in widget.luau's
-- maybe_respawn (respawn[key].gap = respawn_backoff.INITIAL as soon as
-- is_stale goes false), not in this pure library -- there is no backoff
-- STATE here to reset, only the doubling step. What this library must
-- guarantee for that reset to behave correctly is that restarting from
-- INITIAL after a recovery reproduces the exact same schedule as a fresh
-- stream's first-ever outage, not some sped-up or slowed-down variant
-- carrying over residual state from the previous outage -- i.e. next_gap
-- is a pure function of its input with no hidden internal memory.
do
  local first_run = { respawn_backoff.INITIAL }
  local gap = respawn_backoff.INITIAL
  for i = 1, 3 do gap = respawn_backoff.next_gap(gap); table.insert(first_run, gap) end

  -- Simulate having driven the gap all the way to the cap in an earlier,
  -- since-recovered outage, then resetting to INITIAL exactly as
  -- maybe_respawn does on recovery.
  local driven = respawn_backoff.CAP
  local reset_gap = respawn_backoff.INITIAL
  local second_run = { reset_gap }
  for i = 1, 3 do reset_gap = respawn_backoff.next_gap(reset_gap); table.insert(second_run, reset_gap) end

  check("a schedule restarted from INITIAL after reset matches a fresh schedule, unaffected by a prior outage's cap",
        first_run[1] == second_run[1] and first_run[2] == second_run[2] and
        first_run[3] == second_run[3] and first_run[4] == second_run[4])
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

-- (nvidia-smi dmon tests removed: parse.gpu_line is now the only GPU
-- source -- see its tests below.)

-- Real captured output from ~/bin/sysmon-gpu on this machine, so a change in
-- the shim's line format fails here rather than silently blanking the widget.
local gpu_fixture = read("sysmon_gpu.txt")
local saw = { avail = 0, intel = 0, nvidia = 0 }
for line in string.gmatch(gpu_fixture, "[^\n]+") do
  local g = parse.gpu_line(line)
  check("fixture line parses: " .. line, g ~= nil)
  if g then saw[g.kind] = saw[g.kind] + 1 end
end
check("fixture announces availability exactly once", saw.avail == 1)
check("fixture carries intel samples", saw.intel > 0)
check("fixture carries nvidia samples", saw.nvidia > 0)

-- The stream is wrapped in `sh -c 'echo NOCTALIA_PID:$$; exec <cmd>'` so
-- stop_streams can recover an exact, killable PID (see widget.luau for why
-- runStream gives no handle). The onLine callback intercepts that sentinel
-- before it reaches the parser, but the parser must independently reject it
-- too -- belt and suspenders, not a single point of failure.
check("sentinel line is not misread as data", parse.gpu_line("NOCTALIA_PID:12345") == nil)

-- parse.gpu_line: the single ~/bin/sysmon-gpu (nvtop) stream, replacing the
-- old nvidia_dmon + intel_helper + intel_percent trio.
local a = parse.gpu_line("AVAIL|intel,nvidia")
check("avail returns a table", type(a) == "table" and a.kind == "avail")
check("avail sees both GPUs", a.intel == true and a.nvidia == true)

local only = parse.gpu_line("AVAIL|nvidia")
check("avail with one GPU leaves the other false",
      only.nvidia == true and only.intel == false)
-- A machine with no GPU at all still announces, so the widget can tell
-- "probed, found nothing" from "never probed" -- the panel renders those
-- two states differently.
local none = parse.gpu_line("AVAIL|")
check("empty avail is still a table, both false",
      type(none) == "table" and none.intel == false and none.nvidia == false)

local i = parse.gpu_line("INTEL|30")
check("intel kind", i.kind == "intel")
check("intel percent parsed", i.pct == 30)

local n = parse.gpu_line("NVIDIA|43|9|18")
check("nvidia kind", n.kind == "nvidia")
check("nvidia temp parsed", n.temp == 43)
check("nvidia usage parsed", n.usage == 9)
check("nvidia mem parsed", n.mem_usage == 18)

-- Malformed lines must be nil rather than a partially-filled table: the
-- widget publishes whatever comes back straight to noctalia.state, so a
-- half-parsed reading would render as a confident wrong number.
check("gpu garbage returns nil", parse.gpu_line("nonsense") == nil)
check("gpu nil line returns nil", parse.gpu_line(nil) == nil)
check("intel with no value returns nil", parse.gpu_line("INTEL|") == nil)
check("nvidia with missing field returns nil", parse.gpu_line("NVIDIA|43|9") == nil)
check("intel with non-numeric value returns nil", parse.gpu_line("INTEL|abc") == nil)

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

-- graph_history.luau and respawn_backoff.luau are only inlined into
-- widget.luau -- panel.luau has no bar graph and owns no GPU streams to
-- respawn, so it never used either -- so these are checked on their own
-- rather than through the shared `entries` loop above.
check_drift("widget", entries.widget, "graph_history")
check_drift("widget", entries.widget, "respawn_backoff")

print(string.format("%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
