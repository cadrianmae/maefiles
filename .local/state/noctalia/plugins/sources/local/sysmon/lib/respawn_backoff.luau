-- Pure backoff arithmetic for respawning a single dead GPU helper stream
-- while its owning widget instance stays alive (see widget.luau's
-- maybe_respawn). Kept separate from graph_history.luau: this module has
-- nothing to do with graph rendering, and giving the backoff schedule its
-- own tiny library keeps it independently testable without dragging in
-- graph_history's unrelated concerns.
--
-- noctalia's Luau runtime has no require/load (proven Task 2), so this file
-- is inlined into widget.luau rather than imported, same as parse.luau,
-- thresholds.luau and graph_history.luau. This file stays the source of
-- truth; ~/scripts/noctalia-sysmon/test_parse.lua asserts the inlined copy
-- matches it byte-for-byte, so any edit belongs here, not in widget.luau.
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

return respawn_backoff
