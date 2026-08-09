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

-- BEGIN INLINED graph_history.luau
local graph_history = {}

-- Appends one entry every call. Callers must call this exactly once per
-- tick for EVERY series they keep (never skip the call itself), passing
-- nil for `v` on a tick with no reading -- an explicit invalid entry, not a
-- missing one.
function graph_history.push(history, v, max_len)
  table.insert(history, { v = v, ok = v ~= nil })
  if #history > max_len then table.remove(history, 1) end
end

-- Turns a push()-built history into the flat 0-1 number array ui.graph
-- wants. Always exactly #history long when it returns anything at all, so
-- two series built from histories of equal length stay equal length after
-- flattening too.
--
--   1. Nothing valid anywhere in the window -> {} (empty). ui.graph draws
--      no line for an empty series (the native sysmon widget's own
--      clearGraph() calls setValues({}) for exactly this reason).
--   2. The most recent `stale_ticks` entries are ALL invalid -> also {},
--      even if older entries in the window were valid. This is the rule
--      that matters most: without it, a dead stream's last real reading
--      would sit frozen at the graph's right (= "now") edge forever,
--      indistinguishable from a live current value -- the graph would
--      keep vouching for a number nothing is updating anymore.
--   3. Otherwise: interior gaps are filled by carrying the last valid
--      value forward (bounded -- rule 2 already proves the tail is fresh
--      whenever this branch runs, so a carried value can never reach the
--      right edge and be mistaken for "now"). Any run before the
--      first-ever valid entry (only possible in the first few ticks of a
--      fresh series, e.g. right after this instance won the GPU stream
--      election) is back-filled with that first valid value, so the
--      returned array is always exactly #history long no matter where the
--      gaps fall.
function graph_history.flatten(history, stale_ticks)
  local first_valid_v, last_valid_at = nil, nil
  for i = 1, #history do
    if history[i].ok then
      if first_valid_v == nil then first_valid_v = history[i].v end
      last_valid_at = i
    end
  end
  if last_valid_at == nil then return {} end
  if (#history - last_valid_at) >= stale_ticks then return {} end

  local out = {}
  local carry = nil
  for i = 1, #history do
    local e = history[i]
    if e.ok then
      carry = e.v
      out[i] = e.v
    elseif carry ~= nil then
      out[i] = carry
    else
      out[i] = first_valid_v
    end
  end
  return out
end
-- END INLINED graph_history.luau

-- BEGIN INLINED respawn_backoff.luau
local respawn_backoff = {}

-- INITIAL: the widget ticks every 2s (noctalia.setUpdateInterval(2000) in
-- widget.luau), so 5 ticks is ~10s -- long enough that a single dropped or
-- unparseable stream line (already tolerated by STALE_TICKS = 3, ~6s, for
-- the graph-blanking decision) is never mistaken for a dead process, short
-- enough to land the first respawn attempt inside the ~10-15s live
-- verification window.
respawn_backoff.INITIAL = 5

-- CAP: doubling from INITIAL without a ceiling would eventually retry a
-- permanently broken helper once every several minutes, but still forever,
-- for the rest of the user's noctalia session -- worth bounding. 40 ticks
-- is ~80s, inside the "roughly a minute to two minutes" ceiling a broken
-- helper should be retried at once backoff has grown all the way out.
respawn_backoff.CAP = 40

-- Doubles the previous gap (ticks between respawn attempts), clamped so no
-- gap ever exceeds CAP. Called once after each respawn attempt that did
-- not bring the stream back before the next attempt was due. A caller
-- resets its own gap variable back to INITIAL as soon as the stream
-- produces fresh data again -- that reset is the caller's job (it is
-- ordinary state, not arithmetic), this function only ever grows a gap
-- forward.
function respawn_backoff.next_gap(gap)
  local n = gap * 2
  if n > respawn_backoff.CAP then n = respawn_backoff.CAP end
  return n
end
-- END INLINED respawn_backoff.luau

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
local HEARTBEAT_KEY = "sysmon_gpu_heartbeat"
local NVIDIA_KEY = "sysmon_gpu_nvidia"
local INTEL_KEY = "sysmon_gpu_intel"
local AVAILABLE_KEY = "sysmon_gpu_available"
local STALE_KEY = "sysmon_gpu_stale"

local is_owner = false
local owner_confirm_ticks = 0

-- Owner-liveness heartbeat (see update_ownership below): the confirmed
-- owner increments and republishes this every tick; every other instance
-- watches it to detect a dead owner and reclaim. heartbeat_counter is this
-- instance's own next value to publish (only meaningful while is_owner);
-- last_seen_heartbeat/heartbeat_stale_ticks track a RECORDED owner's
-- progress from this instance's point of view (only meaningful while NOT
-- is_owner).
local heartbeat_counter = 0
local last_seen_heartbeat = nil
local heartbeat_stale_ticks = 0
-- ~10s at the widget's 2s tick. A genuinely alive new owner needs at most
-- the 2-tick (~4s) confirm window below plus one more tick before its
-- first heartbeat publish lands, so 5 consecutive unchanged ticks is
-- already comfortably past that -- long enough that this cannot fire
-- against an owner that is merely still electing, short enough that a
-- truly dead owner (crashed, force-killed, or any other teardown path that
-- skips onExit -- see the long comment on update_ownership) does not leave
-- the graph and panel frozen for long.
local HEARTBEAT_STALE_LIMIT = 5

-- Local cache of the GPU figures, always sourced from noctalia.state (never
-- written directly from this instance's own stream callbacks -- see
-- start_streams below). This makes every widget instance, owner or not,
-- read GPU data the same way: the owner's own state.set() calls loop back
-- through its own watch callback exactly like a non-owner's do, so there is
-- only one code path that updates these, not two that could drift apart.
local gpu_nvidia = nil -- { temp, usage, mem_usage } or nil
local gpu_intel = nil -- number (percent) or nil
-- nil (not yet known, distinct from a real table with both fields false --
-- see build_rows in panel.luau, which renders these three states
-- differently: unknown -> dimmed placeholder rows for both possible GPUs,
-- known-and-present -> a live row, known-absent -> the row omitted
-- entirely) until the owner's first probe publishes a real table.
local gpu_available = nil
-- Per-GPU "is the most recent published value still fresh" flag, owner-
-- computed (see nvidia_stale_ticks/intel_stale_ticks below) and read by
-- every instance the same way as gpu_nvidia/gpu_intel/gpu_available.
-- Defaults to not-stale: this is only ever consulted alongside a non-nil
-- gpu_nvidia/gpu_intel check (see intel_gpu_pct/nvidia_gpu_pct below), so
-- before any reading has ever arrived it is moot -- gpu_nvidia/gpu_intel
-- being nil already makes those report "no data" regardless of this flag's
-- pre-publish default.
local gpu_stale = { nvidia = false, intel = false }

-- Ticks since the last successfully parsed stream line for each GPU,
-- counted only while this instance is the confirmed owner (only the owner
-- ever receives raw stream lines to reset these -- see the onLine
-- callbacks in start_streams). Feeds STALE_KEY, published once per owner
-- tick in update() below, so every consumer (this instance's own graph,
-- the other monitor's widget, and the panel -- which stops ticking while
-- closed, so it cannot reliably keep its own "ticks since" count across a
-- long close) can tell a frozen last-known reading from a live one without
-- needing its own continuously-running clock.
local nvidia_stale_ticks = 0
local intel_stale_ticks = 0
-- Ticks since ANY line was parsed from the shared helper. Distinct from the
-- two per-GPU counters above: those answer "is this card's reading current",
-- this answers "is the process still producing anything at all", which is the
-- only question the respawn schedule should act on. Using a per-GPU counter
-- for that would make a single-GPU machine -- where the absent card's counter
-- climbs forever -- look like a permanently dead stream.
local stream_stale_ticks = 0
-- Same cadence reasoning as HISTORY_LEN/graph_history.flatten below: both
-- streams' own polling interval and the widget's tick are ~2s, so 3
-- consecutive misses (~6s) is already 3x the expected inter-arrival gap --
-- enough margin that one dropped or unparseable line does not flag the
-- whole reading stale, tight enough that a genuinely dead stream stops
-- being shown as current within about 6 seconds. Reused, not duplicated,
-- for the graph's own tail-blank check (graph_history.flatten) below --
-- one definition of "how old is too old" for GPU data, not two that could
-- disagree.
local STALE_TICKS = 3

local streams = { gpu = nil }
local stream_pids = { gpu = nil }

-- One helper for BOTH cards. ~/bin/sysmon-gpu wraps nvtop, which reads DRM
-- fdinfo unprivileged and reports every GPU, and reframes its multi-line JSON
-- into one line per GPU per tick (see parse.gpu_line above).
--
-- This replaced two streams. The Intel one had to change regardless: it ran
-- KDE's /usr/libexec/ksystemstats_intel_helper, and ksystemstats pulls KIO,
-- NetworkManagerQt, Solid and libksysguard -- the Plasma stack this machine
-- was reinstalled to shed. Once nvtop was the Intel source it already had the
-- NVIDIA figures too, so keeping `nvidia-smi dmon` alongside it meant running
-- a second process for data the first one had already parsed.
--
-- Consequence worth knowing: dmon's `mem` column was memory BANDWIDTH
-- utilisation; nvtop's mem_util is VRAM OCCUPANCY. The NVIDIA row's memory
-- figure therefore means something different than it did before.
-- Absolute, not os.getenv("HOME") .. "/bin/...": noctalia's Luau sandbox has
-- no `os` library at all, and referencing it fails the whole chunk at load
-- time with "attempt to call a nil value" -- the same class of missing-stdlib
-- limitation as the absent `require`/`load` documented in parse.luau's header.
-- Not PATH-relative either: this runs under noctalia.service, whose PATH is
-- not the login shell's and need not contain ~/bin.
local HELPER = "/home/cadrianmae/bin/sysmon-gpu"
-- Wrapped in `sh -c 'echo NOCTALIA_PID:$$; exec <cmd>'` so stop_streams can
-- recover an exact, killable PID with no pattern matching -- see the long
-- comment this carries over from panel.luau's original start_streams/
-- stop_streams, reproduced in full below on stop_streams.
local GPU_CMD = "sh -c 'echo NOCTALIA_PID:$$; exec " .. HELPER .. "'"

-- Rolling history for the bar graphs. Sized to each graph's own pixel width
-- (40) so each history slot is roughly one pixel column -- more samples than
-- that would just be invisible sub-pixel data, fewer would leave columns
-- blank. At the 2s widget tick used below, 40 samples is ~80s of visible
-- trend, enough to read a spike-and-recover shape at a glance without the
-- bar element dominating the row (matches the glyph-sized RAM/PSI elements
-- it sits beside).
--
-- THREE histories now (CPU, Intel iGPU, NVIDIA dGPU), rendered as two
-- ui.graph controls below -- see render() for why the two GPUs cannot share
-- CPU's graph as a third series. ALL THREE are pushed exactly once per
-- tick, unconditionally, in lockstep, via graph_history.push -- see that
-- function's comment (in the INLINED graph_history.luau block above) for
-- why: skipping a push on an invalid tick lets the histories drift to
-- different lengths, which ui.graph then stretches across the same width
-- independently, breaking the index correspondence between "n ticks ago" in
-- one series and another. This applies just as much to the two series
-- sharing the GPU graph (intel_history/nvidia_history) as it did to the
-- old combined cpu_history/gpu_history pair -- three histories is not an
-- excuse to relax the "every tick, every history" rule for any of them.
local HISTORY_LEN = 40
local GRAPH_WIDTH, GRAPH_HEIGHT = 40, 16
-- Gap between the CPU graph and the GPU graph -- deliberately smaller than
-- the outer row's own gap (8, see render()) so the two graphs still read as
-- one "graphs" section at a glance, while the row gap keeps that section
-- visually separated from the RAM and PSI elements beside it.
local GRAPH_GAP = 4
local cpu_history = {}
local intel_history = {}
local nvidia_history = {}

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
-- No `or {...}` fallback here (unlike an earlier version of this file):
-- gpu_available staying nil until the owner's first real probe IS the
-- "not yet known" state panel.luau's build_rows now renders as dimmed
-- placeholder rows rather than omitting them outright -- see the long
-- comment on the `local gpu_available` declaration above for the three
-- states this distinguishes.
gpu_available = noctalia.state.get(AVAILABLE_KEY)
gpu_stale = noctalia.state.get(STALE_KEY) or { nvidia = false, intel = false }

noctalia.state.watch(NVIDIA_KEY, function(v)
  gpu_nvidia = v
  render()
end)
noctalia.state.watch(INTEL_KEY, function(v)
  gpu_intel = v
  render()
end)
noctalia.state.watch(AVAILABLE_KEY, function(v)
  gpu_available = v
  render()
end)
noctalia.state.watch(STALE_KEY, function(v)
  gpu_stale = v or { nvidia = false, intel = false }
  render()
end)

-- Each GPU's own usage, or nil if it has never reported or its most recent
-- report has gone stale (see gpu_stale/STALE_TICKS above). A stale reading
-- must not feed the graph as if it were current -- that is exactly the
-- "frozen number looks live" failure this task exists to close -- so it is
-- excluded here, upstream of graph_history.push in update() below, rather
-- than trying to special-case it later.
--
-- These used to be combined into one higher_gpu_pct() (math.max of the
-- two) because ui.graph only accepts two series from Lua (values/values2 --
-- the C++ Graph class does have setValues3/setColor3, but the prop
-- whitelist in ui_tree_reconciler.cpp omits values3/color3, so a third
-- series is not reachable from a plugin at all). That combining is exactly
-- what this task removes: with CPU alone taking the first graph's one
-- series, the two GPUs now get a SECOND graph to themselves (see render()),
-- so each keeps its own series and neither hides the other anymore.
local function intel_gpu_pct()
  return (not gpu_stale.intel) and gpu_intel or nil
end

local function nvidia_gpu_pct()
  return (gpu_nvidia and not gpu_stale.nvidia) and gpu_nvidia.usage or nil
end

-- Cross-monitor stream ownership.
--
-- The widget owns both GPU helper streams for the session (moved here from
-- the panel, which used to start/stop them on open/close -- the bar needs
-- GPU data continuously, not just while a panel happens to be open). But the
-- plugin loads once per monitor (see my_output above), so a naive "just
-- start streams on load" would spawn two copies of the GPU helper on this
-- two-monitor machine.
--
-- noctalia.state has no compare-and-swap -- get() and set() are each
-- individually atomic (mutex-protected in the host's PluginStateStore), but
-- the pair is not atomic across two independent widget instances. A plain
-- "if get() == nil then set(self)" can let both instances see nil and both
-- try to claim -- ownership here is instead a claim that must be OBSERVED TO
-- HOLD across two consecutive ticks (owner_confirm_ticks below) before
-- streams actually start. This function runs once per 2s widget tick (see
-- update() below).
--
-- CORRECTNESS NOTE (this took a live back-and-forth with review to pin
-- down precisely, so it is spelled out in full rather than summarised): an
-- earlier draft of this comment claimed a double-start was possible for
-- "up to one extra tick" if both monitors' widgets loaded in the same
-- tick. Re-reading the actual code below shows that claim was wrong --
-- OWNER_KEY is written from exactly two places: the `current == nil`
-- branch (a fresh claim) and the heartbeat-reclaim branch further down,
-- and NEITHER of those branches ever touches is_owner or calls
-- start_streams. is_owner only ever flips true inside the
-- `current == my_output` branch, and only after owner_confirm_ticks (reset
-- to 0 by every OTHER branch) reaches 2 on CONSECUTIVE calls to THIS
-- instance's own update_ownership. Since noctalia.state.get(OWNER_KEY)
-- always returns one consistent value at a time, at most one output name
-- can ever be "current" on any given tick -- so at most one instance can
-- ever be incrementing owner_confirm_ticks toward 2 at once; the other
-- necessarily observes a different name and resets to 0 instead. Two
-- instances calling start_streams() is therefore not reachable at all, not
-- merely rare -- confirmed by re-tracing every write site, not just
-- accepting review's correction on faith. The same argument applies to the
-- heartbeat-reclaim path below: a reclaim is just another `state.set` of
-- OWNER_KEY, gated by the identical 2-tick confirm before anything starts.
--
-- What IS real, and is what heartbeat/reclaim below actually fixes: once
-- OWNER_KEY is non-nil, nothing ever set it back to nil except the owner's
-- own onExit. If the owning runtime is torn down by a path onExit does not
-- cover (unverified whether the host guarantees onExit on every teardown --
-- a crash or an external kill -9 of the whole noctalia process are the
-- obvious candidates), OWNER_KEY stays pointing at a dead output forever,
-- and no instance could ever claim it again without the heartbeat check
-- below.
local start_streams, stop_streams
local start_gpu_stream
local kill_stream_pid

local function update_ownership()
  local current = noctalia.state.get(OWNER_KEY)

  if current == my_output then
    -- I am the recorded owner (freshly claimed, freshly reclaimed, or
    -- already confirmed) -- see the 2-tick confirm gate below for why
    -- start_streams() is not called on the very tick this branch is first
    -- reached.
    owner_confirm_ticks = owner_confirm_ticks + 1
    if owner_confirm_ticks >= 2 and not is_owner then
      is_owner = true
      start_streams()
    end
    -- Only the confirmed owner publishes a heartbeat -- see the constant's
    -- comment above for the ~10s reclaim threshold this feeds on every
    -- OTHER instance.
    if is_owner then
      heartbeat_counter = heartbeat_counter + 1
      noctalia.state.set(HEARTBEAT_KEY, heartbeat_counter)
    end
    -- I cannot be watching myself go stale.
    heartbeat_stale_ticks = 0
    last_seen_heartbeat = nil
    return
  end

  if current == nil then
    -- Nobody is recorded as owner -- either the very first tick anywhere,
    -- or the previous owner released the claim cleanly in its own onExit.
    -- Streams do not start on this same tick; see the 2-tick confirm above.
    noctalia.state.set(OWNER_KEY, my_output)
    owner_confirm_ticks = 0
    heartbeat_stale_ticks = 0
    last_seen_heartbeat = nil
    return
  end

  -- Someone else is recorded as owner. Demote if I previously held it.
  owner_confirm_ticks = 0
  if is_owner then
    is_owner = false
    stop_streams()
  end

  -- Heartbeat reclaim -- the gap described above, and ONLY that gap: onExit
  -- already releases OWNER_KEY cleanly on every exit path the host is
  -- confirmed to call it on (script reload, plugin entry removed, ordinary
  -- shutdown -- see this file's onExit). If the recorded owner's heartbeat
  -- has not advanced for HEARTBEAT_STALE_LIMIT consecutive ticks -- which
  -- also covers the case where it never published one at all, since `hb ==
  -- last_seen_heartbeat` is true when both are nil -- treat it as dead and
  -- reclaim by writing my own name over it. That reclaim then falls through
  -- the exact same `current == my_output` branch and 2-tick confirm as any
  -- fresh claim on the next tick, which is what keeps a reclaim from racing
  -- a merely-slow-to-publish (but actually still alive) owner into a double
  -- start -- see the CORRECTNESS NOTE above; the same argument applies here
  -- unchanged.
  local hb = noctalia.state.get(HEARTBEAT_KEY)
  if hb == last_seen_heartbeat then
    heartbeat_stale_ticks = heartbeat_stale_ticks + 1
  else
    heartbeat_stale_ticks = 0
  end
  last_seen_heartbeat = hb

  if heartbeat_stale_ticks >= HEARTBEAT_STALE_LIMIT then
    noctalia.state.set(OWNER_KEY, my_output)
    heartbeat_stale_ticks = 0
    last_seen_heartbeat = nil
  end
end

-- Availability is no longer probed by asking whether binaries exist
-- (commandExists("nvidia-smi") / fileExists(the KDE helper)). The helper's
-- first line is an AVAIL list of the GPUs nvtop actually enumerated, which is
-- better evidence of what this machine has than which packages are installed.
--
-- gpu_available therefore stays nil until that line arrives, which is exactly
-- the "not yet known" state the panel renders as dimmed placeholder rows --
-- see the long comment on the `local gpu_available` declaration above for the
-- three states this distinguishes.
start_gpu_stream = function()
  -- Unlike the old per-GPU starts there is no `gpu_available.X` guard here:
  -- this stream is what DISCOVERS availability, so gating it on availability
  -- would mean it could never start. The guard that remains is the one that
  -- matters -- never run two copies of it.
  if streams.gpu then return end

  -- nvidia_stale_ticks/intel_stale_ticks reset where their own line is
  -- published, not on any line, so one card going quiet while the other keeps
  -- reporting still blanks only the quiet one -- the same per-GPU staleness
  -- the two-stream version gave, preserved now that both share a process.
  streams.gpu = noctalia.runStream(GPU_CMD, function(line)
    local pid = string.match(line, "^NOCTALIA_PID:(%d+)$")
    if pid then stream_pids.gpu = pid; return end

    local g = parse.gpu_line(line)
    if not g then return end

    -- Any parsed line proves the stream itself is alive, which is what the
    -- respawn schedule below watches -- kept separate from the two per-GPU
    -- counters so a machine with only one GPU never looks like a dead stream.
    stream_stale_ticks = 0

    if g.kind == "avail" then
      gpu_available = { nvidia = g.nvidia, intel = g.intel }
      noctalia.state.set(AVAILABLE_KEY, gpu_available)
    elseif g.kind == "nvidia" then
      nvidia_stale_ticks = 0
      noctalia.state.set(NVIDIA_KEY, { temp = g.temp, usage = g.usage, mem_usage = g.mem_usage })
    elseif g.kind == "intel" then
      intel_stale_ticks = 0
      noctalia.state.set(INTEL_KEY, g.pct)
    end
  end)
end

start_streams = function()
  start_gpu_stream()
end

-- The SIGTERM-then-SIGKILL escalation (with the pkill -x -f fallback for a
-- stream whose sentinel never arrived), originally inline in stop_streams
-- and carried over verbatim from panel.luau's original version of the same
-- teardown. Extracted into its own function so both a full stop_streams()
-- teardown AND a single-stream respawn (see maybe_respawn below, which
-- needs to kill exactly one dead/hung stream without touching the other)
-- call the identical kill sequence -- one implementation, not two that
-- could drift apart.
kill_stream_pid = function(key, pkill_pattern)
  if stream_pids[key] then
    noctalia.runAsync("sh -c 'kill " .. stream_pids[key] ..
      " 2>/dev/null; sleep 2; kill -9 " .. stream_pids[key] .. " 2>/dev/null' &")
  elseif streams[key] then
    noctalia.runAsync("pkill -x -f '" .. pkill_pattern .. "'")
  end
  stream_pids[key] = nil
end

-- Deliberately does NOT clear gpu_nvidia/gpu_intel/gpu_available: those are
-- read from noctalia.state, which the new owner (if any) will overwrite
-- with fresh readings within a couple of ticks. Wiping them here would just
-- mean every reader (this instance's own graph, the other monitor's widget,
-- the panel) shows "no data" for that gap instead of a briefly-stale last
-- reading -- an honest tradeoff, not obviously better either way, so this
-- keeps the simpler behaviour (do nothing) rather than adding code to chase
-- a marginal improvement.
stop_streams = function()
  kill_stream_pid("gpu", HELPER)

  streams.gpu = nil
end

-- Per-stream state for the owner-only single-stream respawn below. Kept
-- separate from nvidia_stale_ticks/intel_stale_ticks -- those two answer
-- "how many ticks since the last valid line", this answers "how many more
-- ticks until the owner is allowed to try killing-and-restarting this
-- stream again". `gap` is the current backoff (grown by
-- respawn_backoff.next_gap after every attempt that did not recover the
-- stream before the next one came due, reset to respawn_backoff.INITIAL as
-- soon as the stream is fresh again); `attempt_at` is the absolute
-- nvidia_stale_ticks/intel_stale_ticks value the NEXT attempt is due at,
-- so the schedule keeps counting from where the last attempt actually
-- landed rather than restarting from "now" every tick. `awaiting_recovery`
-- is only used to decide whether a recovery is worth the one log line
-- requirement 6 allows -- a stream that has never needed a respawn has
-- nothing to "recover" from.
-- One entry now, because there is one stream. The two-stream version needed
-- independent schedules so a broken NVIDIA helper could not disturb Intel's
-- backoff; with both cards behind one process that isolation is neither
-- possible nor meaningful -- if the process dies, both readings stop, and one
-- respawn restores both.
local respawn = {
  gpu = { gap = respawn_backoff.INITIAL, attempt_at = respawn_backoff.INITIAL, awaiting_recovery = false },
}

-- Owner-only: kill-then-respawn exactly one GPU helper stream, independent
-- of the other, when it has gone quiet while this instance stays alive and
-- healthy -- the gap the heartbeat/ownership-reclaim mechanism above does
-- NOT cover (that mechanism only fires for a dead OWNER; a dead child
-- stream under a healthy owner was flagged as a known follow-up in the
-- task-11 report, and closing it is this function's whole job).
--
-- The old `known_available` gate is gone with the two-stream design. It
-- existed so a helper the startup probe never found (no nvidia-smi, no
-- ksystemstats_intel_helper) could not be "respawned" forever, since a stream
-- that never ran cannot legitimately be stale. Availability is now discovered
-- BY this stream rather than probed before it, so that gate would be
-- circular: refusing to start until availability is known, when starting is
-- what establishes it.
--
-- What replaces it is the caller's choice of counter. update() passes
-- stream_stale_ticks -- "has the process produced any line at all" -- not
-- either per-GPU counter, so an absent second card can never present as a
-- broken stream. See the call site for why that distinction matters.
--
-- Kill-before-respawn is unconditional whenever an attempt fires (never
-- "maybe still alive, skip the kill"): a stream can go quiet without its
-- process dying (a hung process, or a broken output pipe), so `streams.X`
-- being non-nil proves nothing about whether the process is actually still
-- running or producing anything. kill_stream_pid is the exact SIGTERM-then-
-- SIGKILL-then-pkill sequence stop_streams() already uses for full
-- teardown -- reused here unchanged, not reimplemented, so there is only
-- ever one kill path in this file to reason about.
local function maybe_respawn(key, label, is_stale, stale_ticks_val, pkill_pattern, start_fn, on_before_start)
  local r = respawn[key]

  if not is_stale then
    -- Fresh data this tick (or never available in the first place, in
    -- which case is_stale is always false and this branch is a no-op every
    -- tick, which is fine). A respawn attempt earlier in this stale run
    -- worked -- log the recovery exactly once, then reset the backoff back
    -- to its initial value so the NEXT failure (a fully independent future
    -- outage) starts counting from respawn_backoff.INITIAL again, not from
    -- wherever this outage's backoff happened to grow to.
    if r.awaiting_recovery then
      noctalia.log("[sysmon] " .. label .. " stream recovered after respawn")
      r.awaiting_recovery = false
    end
    r.gap = respawn_backoff.INITIAL
    r.attempt_at = respawn_backoff.INITIAL
    return
  end

  if stale_ticks_val < r.attempt_at then
    -- Still within the current backoff window -- not due for another
    -- attempt yet. This is what turns "respawn a genuinely broken helper"
    -- into exponential backoff instead of a busy-loop: without this gate,
    -- a stream that respawns but immediately dies again would be
    -- kill-and-restarted on every single 2s tick for the rest of the
    -- session.
    return
  end

  local killed_pid = stream_pids[key]
  noctalia.log("[sysmon] respawning " .. label .. " stream (stale " ..
    stale_ticks_val .. " ticks" ..
    (killed_pid and (", killed pid " .. killed_pid) or ", no recorded pid") .. ")")

  kill_stream_pid(key, pkill_pattern)
  streams[key] = nil
  if on_before_start then on_before_start() end
  start_fn()

  r.gap = respawn_backoff.next_gap(r.gap)
  r.attempt_at = stale_ticks_val + r.gap
  r.awaiting_recovery = true
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
    -- CPU icon+percentage replaced by two single-purpose graphs, nested in
    -- their own row so a small GRAPH_GAP (4px) separates them from each
    -- other without disturbing the outer row's own gap (8px) to the RAM/PSI
    -- elements beside them. This is a deliberate split, not a doubled-up
    -- version of the old single graph: ui.graph only accepts two series
    -- from Lua (values/values2 -- the C++ Graph class does have
    -- setValues3/setColor3, but the prop whitelist in
    -- ui_tree_reconciler.cpp omits values3/color3, so a third series is not
    -- reachable from a plugin at all), and the previous single graph used
    -- to spend its second series on math.max(nvidia, intel) -- which hid
    -- which GPU was actually busy. Two graphs is how CPU, Intel iGPU and
    -- NVIDIA dGPU all become visible: graph 1 is CPU alone, graph 2 gives
    -- each GPU its own series.
    --
    -- "primary"/"secondary"/"tertiary" are plain distinct Material palette
    -- roles (confirmed in the host's src/ui/palette.h ColorRole table), not
    -- health colours from thresholds.color -- a graph trend line has no
    -- single "level" to colour by the way a scalar percent does, and
    -- borrowing thresholds.color's roles here would falsely imply a series
    -- is always "critical" (thresholds.color's "error"/red role) rather
    -- than just being a different series. "error" is deliberately left
    -- alone for that reason. RAM and PSI keep using thresholds.color
    -- exactly as before -- they are unchanged by this task.
    --
    -- graph_history.flatten (not the raw history tables) is what actually
    -- goes to ui.graph -- see that function's comment for the full rules,
    -- summarised: nothing valid anywhere -> {} (no line at all), the tail
    -- gone stale -> also {} (never leave a frozen "now" on screen), else a
    -- same-length array with short gaps carried forward. All three series
    -- are flattened with the SAME stale_ticks threshold, and each GPU's
    -- flatten is independent of the other's -- Intel going stale blanks
    -- only intel_history's line, NVIDIA's keeps drawing, and vice versa,
    -- because gpu_stale is tracked and applied per GPU (see
    -- intel_gpu_pct/nvidia_gpu_pct above and update() below), never
    -- combined the way the old higher_gpu_pct() used to combine the
    -- readings themselves.
    ui.row({ gap = GRAPH_GAP }, {
      ui.graph({
        width = GRAPH_WIDTH,
        height = GRAPH_HEIGHT,
        values = graph_history.flatten(cpu_history, STALE_TICKS),
        color = "primary",
        lineWidth = 1,
        fillOpacity = 0.15,
      }),
      ui.graph({
        width = GRAPH_WIDTH,
        height = GRAPH_HEIGHT,
        values = graph_history.flatten(intel_history, STALE_TICKS),
        values2 = graph_history.flatten(nvidia_history, STALE_TICKS),
        color = "secondary",
        color2 = "tertiary",
        lineWidth = 1,
        fillOpacity = 0.15,
      }),
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

  -- Owner-only: age the per-GPU staleness counters and republish STALE_KEY
  -- every tick, regardless of whether anything changed -- a consumer must
  -- be able to tell "still fresh" from "nothing new happened" even when
  -- the underlying boolean hasn't flipped, and a stream that goes quiet
  -- produces no onLine callback of its own to trigger a publish, so this
  -- tick-driven publish is the only thing that ever ages it forward.
  if is_owner then
    nvidia_stale_ticks = nvidia_stale_ticks + 1
    intel_stale_ticks = intel_stale_ticks + 1
    stream_stale_ticks = stream_stale_ticks + 1
    -- Deliberately not the `A and B or C` ternary idiom: when B itself can
    -- be `false` (it can, here), that idiom silently falls through to C
    -- instead of returning `false` -- it only happens to be safe when C
    -- and the intended false-case value are identical, which is easy to
    -- break on a future edit. `== true` forces a real boolean explicitly.
    local nvidia_known_available = gpu_available ~= nil and gpu_available.nvidia == true
    local intel_known_available = gpu_available ~= nil and gpu_available.intel == true
    local nvidia_is_stale = nvidia_known_available and nvidia_stale_ticks >= STALE_TICKS
    local intel_is_stale = intel_known_available and intel_stale_ticks >= STALE_TICKS
    noctalia.state.set(STALE_KEY, { nvidia = nvidia_is_stale, intel = intel_is_stale })

    -- Respawn the shared helper when it stops producing, on the same
    -- exponential backoff the two-stream version used -- see maybe_respawn's
    -- own comment for the full reasoning.
    --
    -- Gated on stream_stale_ticks, NOT on either per-GPU counter: a machine
    -- with one GPU leaves the other card's counter climbing forever, which
    -- would read as a permanently broken stream and trigger an endless
    -- kill-and-restart of a process that is working perfectly.
    --
    -- No `on_before_start` hook anymore. It existed only to clear the Intel
    -- percent baseline (intel_prev) so a freshly-spawned helper did not
    -- compute a delta against a sample from minutes earlier; nvtop reports
    -- utilisation directly, so there is no baseline to invalidate.
    maybe_respawn("gpu", "GPU", stream_stale_ticks >= STALE_TICKS,
      stream_stale_ticks, HELPER, start_gpu_stream)
  end

  -- History is sampled once per tick, in lockstep with cpu/ram/psi, so all
  -- three histories share one cadence regardless of how often the GPU
  -- stream lines actually arrive (nvidia-smi dmon ticks on its own -d 2
  -- schedule, the Intel helper on its own).
  --
  -- ALL THREE histories are pushed unconditionally, every tick, even when
  -- the reading is nil -- graph_history.push stores an explicit invalid
  -- entry rather than the call being skipped. Skipping a push on an invalid
  -- tick (the previous approach, and the same mistake this task must not
  -- reintroduce for intel_history/nvidia_history) lets a history drift to a
  -- different length than the others over time, and ui.graph stretches
  -- each series independently across the same pixel width -- so a shorter,
  -- drifted series would render its samples at different x positions than
  -- another series' samples taken at the very same tick. This matters
  -- doubly for intel_history/nvidia_history: they share one graph
  -- (values/values2), so if either drifts out of step with the other, the
  -- two GPU lines would no longer even agree with EACH OTHER on which
  -- pixel column is "now", not just with the CPU graph next to them.
  -- Pushing unconditionally keeps index i of all three histories anchored
  -- to the same tick, always; graph_history.flatten (used in render()
  -- above) is what turns a nil-containing history into the "no misleading
  -- flat line" values ui.graph actually receives.
  local intel_pct = intel_gpu_pct()
  local nvidia_pct = nvidia_gpu_pct()
  graph_history.push(cpu_history, cpu and clamp01(cpu / 100) or nil, HISTORY_LEN)
  graph_history.push(intel_history, intel_pct and clamp01(intel_pct / 100) or nil, HISTORY_LEN)
  graph_history.push(nvidia_history, nvidia_pct and clamp01(nvidia_pct / 100) or nil, HISTORY_LEN)

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
