# Memory management

A 16 GB system that hits 90 %+ RAM after extended uptime is normal here unless watchdogs fire. This guide names the recurring leak culprits, the scripts that monitor them, and the per-application tweaks that bring baseline RSS back into sane territory.

## Known leak culprits

| Process | Symptom | Reference |
|---|---|---|
| Copilot.lua language server | Leaks to 879 MB+ if Neovim is left open in tmux | — |
| Zen Browser (Firefox-based) | Accumulates zombie processes over time | [zen-browser/desktop#11721](https://github.com/zen-browser/desktop/issues/11721) |
| Obsidian plugins (`terminal`, `hover-editor`) | Buffers never freed | — |
| Dark Reader extension | Dynamic mode → infinite growth (500 MB+ spikes) | [darkreader#8865](https://github.com/darkreader/darkreader/issues/8865) |

## Watchdog scripts (all in `~/bin/`)

| Command | Purpose |
|---|---|
| `memory-watchdog` | Snapshot all known leaky apps → `~/.cache/memory-watchdog.log` |
| `check-browser-memory` | Total Zen RSS across all processes |
| `check-obsidian-memory` | Total Obsidian RSS + plugin list |
| `monitor-memory` | Log every 5 min → `~/.cache/memory-monitor-YYYY-MM-DD.log` |
| `analyze-memory-leaks` | Parse monitor logs to find growing processes |
| `free-memory` | Emergency cleanup — restart copilot, drop caches |
| `auto-restart-leaky-apps` | Auto-restart Zen / Obsidian past thresholds |

```bash
# Snapshot now
memory-watchdog

# Long-running monitor (background it)
monitor-memory &

# After hours of monitoring, see which process is climbing
analyze-memory-leaks

# Panic button at 90 %+
free-memory
```

## Applied mitigations

### Zen browser — `about:config`

```ini
browser.cache.memory.capacity         = 102400  # 100 MB (was ~1 GB)
browser.cache.disk.capacity           = 102400  # 100 MB
browser.sessionhistory.max_entries    = 5       # 5 (was 50)
config.trim_on_minimize               = true    # Free RAM when minimised
dom.ipc.processCount                  = 4       # 4 (was 8)
browser.sessionstore.interval         = 30000   # 30 s (was 15 s)
browser.tabs.remote.warmup.enabled    = false
network.http.max-connections          = 30
```

### Obsidian

| Plugin | Status | Reason |
|---|---|---|
| `terminal` | Disabled | Buffer leak |
| `hover-editor` | Disabled | Known leak |
| `excalidraw` | Watch | 8.4 MB; close canvases when done |

Vault size matters — 2 439 markdown files ⇒ ~600 MB baseline.

### Dark Reader (Firefox / Zen extension)

Settings → Performance:

- ✅ Use system colour scheme
- ❌ Disable "Dynamic Theme Generation"
- Switch to **Filter** mode → 83 % memory reduction

## Expected baseline

After the mitigations above, on a 16 GB system:

| State | Usage | % |
|---|---|---|
| Boot | ~3.2 GB | 20 % |
| + Discord / Spotify | ~6.0 GB | 38 % |
| + Zen / Claude Code | ~7.8 GB | 49 % |
| + Obsidian | ~8.8 GB | 55 % |
| After all fixes | ~7.0 GB | 44 % |

### Thresholds

| Band | Range | Action |
|---|---|---|
| Normal | < 75 % | None |
| Monitor | 75–85 % | Watch `analyze-memory-leaks` output |
| Critical | > 85 % | systemd timer alerts; consider `free-memory` |

## Common-issue playbook

### Zen growth

```bash
# Zombie process count — should be 10–15, not 100+
pgrep -f "zen/zen" | wc -l
```

If total exceeds **2.5 GB**, restart Zen. `about:memory` inside the browser names the heaviest tabs.

### Obsidian growth

- Look for terminal panes left open (no buffer flush).
- Close Excalidraw canvases when done.
- If RSS > **2 GB**, restart Obsidian.

### Forgotten Neovim instances

```bash
ps aux | grep nvim | grep -v grep
```

Each `nvim` spawns a Copilot LS that can climb to 500–800 MB. Close forgotten tmux windows hosting `nvim`.

## Community references

- [Obsidian large vault memory (6–10 GB)](https://forum.obsidian.md/t/request-for-assistance-with-memory-issue-in-obsidian/97962)
- [Obsidian 4 GB Electron / V8 limit](https://forum.obsidian.md/t/basic-memory-management-to-avoid-oom-errors/102927)
- [Zen browser leak (40 GB over time)](https://github.com/zen-browser/desktop/issues/11721)
- [Zen zombie processes (1 499 instances)](https://github.com/zen-browser/desktop/issues/10797)
- [Dark Reader memory leak (1 GB spike)](https://github.com/darkreader/darkreader/issues/8865)
- [Firefox memory optimisation guide](https://support.mozilla.org/en-US/kb/firefox-uses-too-much-memory-or-cpu-resources)

## Related

- [CLI tools reference](../reference/cli-tools.md) — env vars and watchdog command list
