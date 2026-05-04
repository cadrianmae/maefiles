# Terminal Migration: kitty + tmux → wezterm (tmux optional)

- **Author:** cadrianmae
- **Date:** 2026-05-04
- **Status:** Draft — deferred to Summer 2026 (last academic summer before full-time work)
- **Supersedes:** `~/.config/kitty/kitty.conf` + `~/.tmux.conf` as the daily-driver stack
- **Related:**
  - `~/.claude/projects/-home-cadrianmae/memory/project_kitty_summer_2026.md`
  - Origin conversation: `claude --resume e3dc53c3-3d24-45a8-9354-77522094b9b3`

## 1. Context

Current stack (as of 2026-05-04):

- **Layer 1 (terminal):** kitty 0.43.1, minimal config (catppuccin-macchiato, CaskaydiaCove Nerd Font Mono, powerline tabs, beam cursor).
- **Layer 2 (multiplexer):** tmux with 12 plugins via TPM — `tmux-resurrect`, `tmux-continuum`, `vim-tmux-navigator`, `extrakto`, `tmux-yank`, `tmux2k` (catppuccin status bar with pomodoro/claude/RAM/time), `tmux-which-key`, etc. C-Space prefix. `nvsl` substitution for nvim session restore.
- **Workflow pattern:** ad-hoc workspaces — open new tmux windows as work arrives, accumulate ~7 long-running ones (each typically nvim + claude + zsh). Only `dev-split` is a pre-defined named layout. Continuum auto-snapshots every 15 min; resurrect replays on startup.
- **Status (2026-05-04):** oh-my-zsh tmux autostart disabled (`ZSH_TMUX_AUTOSTART=false`). tmux now opt-in. Kitty is the bare-metal default.

Pain / motivation:

1. **Two-layer overlap.** Kitty's tabs/splits/sessions duplicate tmux's, doubling keybind cognitive load and producing nested copy modes.
2. **Graphics protocol passthrough cost.** image.nvim/snacks.nvim work through tmux's `allow-passthrough on`, which is fragile and slower than native.
3. **Maintainer ecosystem concerns for kitty.** Kovid Goyal's well-documented hostility toward bug reporters (HN, "Goodbye, Kitty" by Gavin Howard) makes the long-term position of kitty as a *platform* (vs a tool) unattractive if upstream engagement ever becomes necessary.
4. **WezTerm covers the workspace-persistence gap natively** via its built-in multiplexer + workspaces, which is the single feature that kept tmux indispensable. Kitty has no equivalent and would require a custom tmux-continuum-like kitten (estimated 1-2 weekends).
5. **Lua extensibility in WezTerm** is broader than Python kittens — full event API, status bar via `update-right-status`, key tables for modal binds, multi-machine domain configs.

Goals:

1. Single-layer terminal that handles both rendering and persistent multiplexing without a separate Layer 2 daemon.
2. Native graphics protocol support without passthrough hacks.
3. Preserve tmux muscle memory (C-Space leader chord) during transition.
4. Replicate tmux2k status bar in Lua (pomodoro / claude / RAM / time, catppuccin theme).
5. Replicate `nvim` per-cwd session resume (`nvsl` → `nvw`-style alias) so workspace restoration produces a meaningful nvim state, not a fresh blank buffer.
6. tmux remains installed and configured for **remote SSH use** (where its disconnect-survival actually earns its keep) and for **rare local cases** where a specific tmux2k feature is wanted.
7. Reversible — if WezTerm doesn't stick, fall back to kitty without losing the kitty config.

## 2. Decision Summary

| Decision | Choice | Why |
|---|---|---|
| Target terminal | **WezTerm** | Built-in multiplexer + workspace persistence solves the ad-hoc 7-workspace pattern natively. Kitty would need a custom kitten (~1-2 weekends) to match. |
| Extension language | **Lua** (WezTerm) over Python (kitty kittens) | Lua-from-Python is ~1 weekend to internalise; broader API surface (event hooks, status bar, key tables) outweighs the language switch cost. |
| Local tmux status | **Opt-in only** (`ZSH_TMUX_AUTOSTART=false` already applied) | Keep installed for remote SSH and one-off local use; not the default workspace mechanism. |
| Remote tmux | **Keep as-is on remote hosts** | Server-side persistence is the one job multiplexers do uniquely well; WezTerm is the *client*, can't replace remote-side tmux. |
| Migration shape | **Trial week → commit-or-rollback → summer build-out** | Reversible by design. Kitty config preserved at `~/.config/kitty/kitty.conf` throughout. |
| Status bar replacement | **Lua `update-right-status` event handler** matching tmux2k segments | Pomodoro / Claude / RAM / time / catppuccin colours. Custom file-based pomodoro state already exists (`~/.config/pomodoro/`). |
| Keybind philosophy | **C-Space leader chord** mirroring tmux prefix | Muscle memory carries; native WezTerm `Ctrl+Shift+*` defaults stay alongside as secondary. |
| Pane navigation | **smart-splits.nvim** with WezTerm helper | Solves the `Ctrl+hjkl` shell-shortcut conflict (Ctrl+L clear-screen etc.) by detecting nvim focus and forwarding correctly. |
| Workspace restoration | **WezTerm workspaces + per-cwd nvim sessions** | Replace `nvsl` (global "last") with `nvw` alias loading a session named after `basename $PWD`. Eliminates session clobbering across workspaces. |
| Fallback / kill switch | **Keep `~/.config/kitty/` intact for 30 days post-migration** | If WezTerm doesn't click after 30 days of daily use, revert by re-enabling `ZSH_TMUX_AUTOSTART=true` and switching default terminal back to kitty. |

## 3. Out of scope

- **Replacing tmux on remote hosts.** Stays as-is.
- **Ghostty trial.** Considered and ruled out — no extension language, weaker for the "build platform" intent.
- **Alacritty / iTerm2.** Wrong category (single-purpose / Mac-only).
- **Migrating to zellij.** Same Layer 2 problem; doesn't address the "stop running two layers" goal.
- **Marketplace publishing of any custom WezTerm config.** Maybe later; not part of this migration.

## 4. Migration phases

### Phase 0 — Parallel install (already done, 2026-05-04)

- WezTerm installed; `~/.config/wezterm/wezterm.lua` written with kitty-equivalent appearance + C-Space leader binds.
- `wezconfig` alias added to `~/.zsh_aliases`.
- oh-my-zsh tmux autostart disabled.
- Kitty config untouched.

### Phase 1 — Trial week (2-3 evenings of real work)

- Daily-drive WezTerm for one week. Use it for actual coursework / projects, not just toy tasks.
- Force-test the **workspace persistence** (the deciding feature). Open ~7 workspaces over the week, leave them, restart machine, verify restoration UX.
- Force-test the **Lua config feel**. Try writing one small custom binding or status bar segment.
- Decision point at end of week: **commit or rollback.**
  - **Commit:** continue to Phase 2.
  - **Rollback:** delete `~/.config/wezterm/`, re-enable `ZSH_TMUX_AUTOSTART=true`, archive this spec as "trialled but rejected, reasons: …". Update memory entry.

### Phase 2 — Status bar replacement (~1 weekend)

- Port tmux2k segments to Lua via `wezterm.on('update-right-status', ...)`:
  - Pomodoro state (read `~/.config/pomodoro/state` or equivalent)
  - Claude indicator (process check or marker file)
  - RAM (`/proc/meminfo` parse)
  - Time (`os.date`)
  - Catppuccin colours matching current tmux2k theme
- Acceptance: bar visually approximates tmux2k; updates on a 1-2s tick.

### Phase 3 — Workspace + nvim session integration (~1 weekend)

- Replace `nvsl` alias with `nvw` (per-cwd named resession sessions). Update tmux config to use `nvw` too (resurrect compatibility during transition).
- Configure WezTerm workspaces for the recurring patterns (FYP, marketplace, dotfiles, etc.) — start with launcher-style entries, evolve as real usage settles.
- smart-splits.nvim installation + WezTerm helper config.

### Phase 4 — Default terminal switch + soak (1-2 weeks)

- Set WezTerm as default in KDE.
- 30-day soak. Kitty stays installed but unused.
- Daily journal of any "I miss kitty's X" moments — use to identify either feature ports or rollback signals.

### Phase 5 — Cleanup (only if soak passes)

- Archive `~/.config/kitty/` to `~/.config/kitty.archive-2026-MM/` (don't delete — see footgun below).
- Remove kitty from KDE default applications.
- Update memory: kitty entry → archived, WezTerm entry → primary.

## 5. Risks / rollback

| Risk | Mitigation |
|---|---|
| WezTerm Lua learning curve too steep | 30-day soak gives time. If frustrating, fall back to Path C from origin convo: stay hybrid kitty + tmux. |
| Workspace persistence doesn't match tmux-resurrect feel | Phase 1 trial week catches this; rollback before commit. |
| Custom status bar takes longer than 1 weekend | Acceptable to ship Phase 2 with a stripped-down bar (just time + RAM); pomodoro / claude indicators are nice-to-haves. |
| smart-splits.nvim WezTerm helper has rough edges | Fall back to Alt+hjkl for pane nav; lose vim ↔ pane fluidity but no shell conflicts. |
| Lose access to a specific tmux plugin (extrakto, which-key) | Document the loss; either find Lua equivalent or accept. WezTerm has command palette + quickselect that cover most of what extrakto+which-key give. |
| Want a feature only kitty has (e.g. specific kitten) | tmux already retained for opt-in use; kitty config retained for 30 days; reversible. |

## 6. Footguns

- **Don't `rm -rf ~/.config/kitty/`** during cleanup. Archive instead. Kitty's config files are small; the cost of keeping them is zero, the cost of needing them after deletion is real.
- **Don't migrate `nvsl` → `nvw` in isolation.** It must update in both `~/.zsh_aliases` AND `~/.tmux.conf` (`@resurrect-processes` line) atomically, or tmux restoration will start loading the wrong sessions.
- **Don't bind `Ctrl+hjkl` in WezTerm without smart-splits.nvim.** It silently breaks `Ctrl+L` clear-screen and other shell shortcuts. Either install smart-splits + helper, or use `Alt+hjkl`.
- **Don't trust the trial week if you've spent it on toy tasks.** The whole point is the ad-hoc workspace pattern; if you don't actually accumulate 7 workspaces during the trial, you haven't tested the deciding feature.

## 7. Open questions (for summer)

- **Per-machine WezTerm configs?** WezTerm has `wezterm.target_triple` and host-name detection — could share `wezterm.lua` across machines via yadm with per-host overrides. Decide during Phase 4 if needed.
- **Promote any custom Lua to a public repo?** WezTerm's plugin system is `wezterm.plugin.require` from a git URL — possible to publish status bar / smart-splits config / workspace launcher as small modules. Not in scope, but worth noting if the community asks.
- **Long-term: kitty's graphics protocol skill transfer.** Even if WezTerm wins, the protocol knowledge applies — image.nvim, snacks.nvim, matplotlib-backend-kitty all target the same protocol. So summer time spent on this is portable.

## 8. Acceptance criteria (post-soak)

The migration is "successful" if **all** of:

1. WezTerm has been the daily driver for 30 consecutive days without falling back to kitty.
2. Workspace persistence after reboot delivers a usable workspace (not a fresh blank slate) ≥80% of the time.
3. Status bar provides at least: time, RAM, pomodoro state, and matches catppuccin theme.
4. `Ctrl+L` clears the screen in shell panes (i.e. smart-splits or Alt+hjkl is correctly configured).
5. tmux is *only* invoked deliberately (remote SSH, or one-off local) — never as a default workspace mechanism.
6. No "I wish I had kitty's X" entries in the soak journal that aren't trivially portable to WezTerm.

If any fail at end of soak, decision is rollback or extend.

## 9. References

Research consulted during the 2026-05-03/04 decision conversation.

**Official documentation:**
- Kitty homepage: https://sw.kovidgoyal.net/kitty/
- Kitty on GitHub: https://github.com/kovidgoyal/kitty
- Kittens (extension framework): https://sw.kovidgoyal.net/kitty/kittens_intro/
- Kitty integrations index: https://sw.kovidgoyal.net/kitty/integrations/
- WezTerm config files (paths + precedence): https://wezterm.org/config/files.html

**Community discussion:**
- r/KittyTerminal: https://www.reddit.com/r/KittyTerminal/

**Deep-dive write-ups:**
- Mastering kitty terminal — Paul Nameless: https://paul-nameless.com/mastering-kitty.html
- Kitty customisation tour — It's FOSS: https://itsfoss.com/kitty-customization/
- Kitty Terminal — Practicalli Engineering Playbook: https://practical.li/engineering-playbook/os/command-line/kitty-terminal/

**Ecosystem (relevant to the migration):**
- image.nvim (kitty graphics in nvim): https://github.com/3rd/image.nvim
- smart-splits.nvim (vim-tmux-navigator successor for kitty/wezterm): https://github.com/mrjones2014/smart-splits.nvim
- snacks.nvim (folke's toolkit, includes kitty graphics): https://github.com/folke/snacks.nvim

**Comparisons (informed the wezterm choice):**
- Terminal Trove compatibility matrix: https://terminaltrove.com/compare/terminals/
- Modern Terminals Showdown — Code Miner: https://blog.codeminer42.com/modern-terminals-alacritty-kitty-and-ghostty/
- Choosing a Terminal on macOS (2025) — Chris Evans: https://medium.com/@dynamicy/choosing-a-terminal-on-macos-2025-iterm2-vs-ghostty-vs-wezterm-vs-kitty-vs-alacritty-d6a5e42fd8b3
- Switching from Ghostty back to Kitty — linkarzu: https://linkarzu.com/posts/terminals/ghostty-to-kitty/

**Maintainer reputation calibration (factored into the kitty-as-platform concern):**
- Goodbye, Kitty — Gavin D. Howard: https://gavinhoward.com/2022/02/goodbye-kitty/
- HN thread on Kovid's communication style: https://news.ycombinator.com/item?id=24644055
- Why Terminal Multiplexers Are an Anti-Pattern (Kovid's view) — Jon Roosevelt: https://jonroosevelt.com/blog/terminal-design-philosophy-rethinking-multiplexers
