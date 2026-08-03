-- Rolling, index-aligned history for two-series bar graphs. Both series fed
-- to a single ui.graph MUST be pushed exactly once per tick (see push()) so
-- they stay the same length at all times -- ui.graph stretches each series
-- independently across the same pixel width (confirmed by reading the
-- host's Graph::sync/GraphNode: each series gets its own count, spread
-- evenly across the control's width by the shader), so two series of
-- different lengths render at different time-per-pixel and a feature at
-- "index i" in one no longer lines up with "index i" in the other, even
-- though both are drawn at the same x position. Skipping a push on an
-- invalid tick (rather than pushing an explicit invalid entry) is exactly
-- the bug this module exists to prevent -- see widget.luau's task-10
-- report for the concrete failure this was written to fix.
--
-- noctalia's Luau runtime has no require/load (proven Task 2), so this file
-- is inlined into widget.luau rather than imported, same as parse.luau and
-- thresholds.luau. This file stays the source of truth;
-- ~/scripts/noctalia-sysmon/test_parse.lua asserts the inlined copy matches
-- it byte-for-byte, so any edit belongs here, not in widget.luau.
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

return graph_history
