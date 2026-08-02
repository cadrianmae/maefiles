-- Threshold table. The psi_mem_full pair is NOT free to change: it mirrors
-- MEMNOTIFY_TIER_WARN_PSI / MEMNOTIFY_TIER_CRIT_PSI in
-- ~/bin/lib/memory-notify/core.sh so the ambient bar and the notifier agree
-- about when memory pressure matters. Everything else is tunable.
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
  local t = TABLE[metric]
  -- An unknown metric must not be styled as alarming. Silent "ok" beats a
  -- red bar caused by a typo in a metric name.
  if not t or type(value) ~= "number" then return "ok" end
  if value >= t.critical then return "critical" end
  if value >= t.activity then return "activity" end
  return "ok"
end

function thresholds.color(level)
  if level == "critical" then return "error" end
  if level == "activity" then return "primary" end
  return "on_surface"
end

return thresholds
