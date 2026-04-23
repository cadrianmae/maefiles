# CLI Tools and Configuration

Personal CLI setup for cadrianmae on Fedora 43 with KDE Plasma.

## Shell: Zsh + Oh My Zsh

**Theme:** robbyrussell

**Config:** `~/.zshrc`

### Oh My Zsh Plugins

| Plugin | Description |
|--------|-------------|
| `git` | Git aliases and functions |
| `zoxide` | Smarter cd command with frecency |
| `tmux` | Tmux aliases and auto-start support |
| `vi-mode` | Vi keybindings in the shell |
| `zsh-autosuggestions` | Fish-like autosuggestions |
| `fast-syntax-highlighting` | Syntax highlighting for commands |
| `zsh-autocomplete` | Real-time type-ahead completion |

### Custom Aliases (`~/.zsh_aliases`)

| Alias | Command | Description |
|-------|---------|-------------|
| `vi` | `vim` | Vim shortcut |
| `nv` | `nvim` | Neovim shortcut |
| `cs` | `cheat` | Cheatsheet lookup (function with grep) |
| `csp` | `cheat -p personal` | Personal cheatsheets |
| `clip` | `wl-copy` | Wayland clipboard |
| `open` | `xdg-open` | Open files with default app |
| `restart-plasma` | `systemctl --user restart plasma-plasmashell.service` | Restart KDE Plasma |
| `docker-start/stop/restart/status/log` | systemctl user commands | Docker rootless management |

### Custom Functions (`~/.zsh_functions`)

| Function | Description |
|----------|-------------|
| `compress-video <file> [quality]` | Compress video with NVENC (GPU) or CPU fallback |
| `libre2pdf <file>` | Convert document to PDF via LibreOffice |
| `libre2pdf-batch <files...>` | Batch convert to PDF |
| `libre2pdf-all` | Convert all documents in current directory |
| `cs <sheet> [term]` | Cheatsheet with optional grep search |
| `direnv_prompt_info` | Show direnv status in prompt |
| `odino <cmd>` | Semantic search wrapper (finds .odino in parents) |

### convert-pdf

PDF to Markdown converter with OCR and AI enhancement.

```bash
convert-pdf document.pdf                    # Basic conversion
convert-pdf document.pdf --enhance          # With AI enhancement (light)
convert-pdf document.pdf --enhance medium   # Medium enhancement
convert-pdf *.pdf -o output/                # Batch convert
```

**OCR Backends:** `mistral`, `pymupdf`, `claude`, `marker`

**Key Options:**
| Option | Description |
|--------|-------------|
| `--enhance [level]` | AI enhancement (light/medium/heavy) |
| `--doc-style <style>` | article, presentation, academic, notes, technical, email |
| `--frontmatter <style>` | obsidian, pandoc, minimal, none |
| `--save-images` | Save images to subdirectory (default) |
| `--embed-images` | Embed as base64 |
| `--preset <name>` | obsidian, pandoc, clean, academic |

### build-memory

Generate project memory summaries from Claude Code conversation history.

```bash
build-memory                    # Process current directory
build-memory /path/to/project   # Process specific project
build-memory --all              # Process all active projects (batch mode)
```

**What it does:**
- Analyzes Claude Code transcript history (last 30 days)
- Generates concise summaries (200-300 words) focusing on tasks, decisions, and context
- Saves to `.claude/memory.md` in each project root
- Maintains temporal consistency by reading previous memories
- Uses aggregated API calls for efficiency (single Claude call for all projects)

**Automatic Updates:**
- Runs daily at 11 PM via systemd timer
- Only processes projects with activity in last 24 hours
- Skips projects where memory is already up-to-date

**Manual Control:**
```bash
# Enable/disable timer
systemctl --user enable build-memory.timer
systemctl --user disable build-memory.timer

# Check next scheduled run
systemctl --user list-timers build-memory.timer

# View logs
journalctl --user -u build-memory.service -n 50

# Trigger manually
systemctl --user start build-memory.service
```

**Environment Variables:**
| Variable | Default | Description |
|----------|---------|-------------|
| `BUILD_MEMORY_VERBOSE` | `false` | Show detailed progress output |

**Example output location:** `/path/to/project/.claude/memory.md`

**Key Features:**
- Fast project discovery using `.claude.json` index
- Batch processing with single Claude API call
- Temporal consistency across updates
- Low system impact (nice=19, idle I/O scheduling)

---

## Terminal Multiplexer: Tmux + TPM

**Plugin Manager:** [TPM](https://github.com/tmux-plugins/tpm) (Tmux Plugin Manager)

**Config:** `~/.tmux.conf`

### Tmux Plugins

| Plugin | Description |
|--------|-------------|
| `tmux-plugins/tpm` | Plugin manager |
| `tmux-plugins/tmux-sensible` | Sensible default settings |
| `alexwforsythe/tmux-which-key` | Keybinding hints popup |
| `christoomey/vim-tmux-navigator` | Seamless vim/tmux navigation (Ctrl+hjkl) |
| `2kabhishek/tmux-tilit` | Tiling WM-style pane management (Alt+hjkl) |
| `catppuccin/tmux` | Catppuccin theme (v2.1.3) |
| `2kabhishek/tmux2k` | Status bar with catppuccin theme |
| `tmux-plugins/tmux-resurrect` | Save/restore sessions across restarts |
| `tmux-plugins/tmux-continuum` | Auto-save sessions (with auto-restore) |
| `tmux-plugins/tmux-yank` | System clipboard integration |
| `laktak/extrakto` | Fuzzy extract text from terminal output |

### TPM Commands

| Keybinding | Action |
|------------|--------|
| `Prefix + I` | Install plugins |
| `Prefix + U` | Update plugins |
| `Prefix + Alt + u` | Uninstall removed plugins |

### tmux-tilit Keybindings

| Keybinding | Action |
|------------|--------|
| `Alt + hjkl` | Navigate panes |
| `Alt + Shift + hjkl` | Move panes |
| `Alt + Enter` | New pane |
| `Alt + /` | Horizontal split |
| `Alt + -` | Vertical split |
| `Alt + Shift + m` | Main-vertical layout |
| `Alt + Shift + t` | Tiled layout |
| `Alt + Shift + e` | Even horizontal |
| `Alt + z` | Zoom toggle |
| `Alt + x` | Close pane |

---

## Editor: Neovim (AstroNvim)

**Distribution:** [AstroNvim](https://github.com/AstroNvim/AstroNvim) v4+

**Config:** `~/.config/nvim/`

---

## Version Managers

### Python: pyenv

**Version:** pyenv 2.6.8

**Current Python:** 3.13.9

**Config:** Loaded in `~/.zshrc`

```bash
export PYENV_ROOT="$HOME/.pyenv"
eval "$(pyenv init - bash)"
eval "$(pyenv virtualenv-init -)"
```

### Node.js: nvm

**Config:** `~/.nvm/`

Loaded in `~/.zshrc` with bash completion.

---

## CLI Utilities

| Tool | Description | Config |
|------|-------------|--------|
| `zoxide` | Smarter cd with frecency | via oh-my-zsh plugin |
| `fzf` | Fuzzy finder | Used by cheat, tmux plugins |
| `direnv` | Per-directory environment | `~/.zshrc` hook |
| `cheat` | Cheatsheets with fzf | `~/.config/cheat/conf.yml` |
| `btop` | System monitor | `~/.config/btop/btop.conf` |
| `odino` | Semantic code search | Custom wrapper function |
| `laio` | Flexbox-style tmux layout manager | `~/.config/laio/` |

### Fun Stuff

Terminal greeting on shell start:
```bash
fortune | cowsay -f $(random cow) | lolcat -b
```

---

## Environment Variables

| Variable | Value | Purpose |
|----------|-------|---------|
| `EDITOR` | `nvim` (local) / `vim` (SSH) | Default editor |
| `MANPAGER` | `nvim +Man!` | View man pages in neovim |
| `CHEAT_USE_FZF` | `true` | Enable fzf in cheat |
| `ZSH_TMUX_CONFIG` | `$HOME/.tmux.conf` | Tmux config path for oh-my-zsh |

---

## File Locations

```
~/.zshrc                    # Main zsh config
~/.zsh_aliases              # Custom aliases
~/.zsh_functions            # Custom functions
~/.tmux.conf                # Tmux configuration
~/.tmux/plugins/            # TPM plugins
~/.config/nvim/             # Neovim (AstroNvim)
~/.config/btop/             # btop config
~/.config/cheat/            # cheat config
~/.config/laio/             # laio layout configs
~/.claude/                  # Claude Code config
~/.claude/hooks/notify.sh   # Claude notification hook
```

---

## Troubleshooting

### NVIDIA Driver Updates

NVIDIA driver updates can sometimes leave packages out of sync, causing issues with Qt/KDE applications and other system components.

**Common symptoms:**
- Qt symbol errors (e.g., `undefined symbol: _ZN...Qt_6.9_PRIVATE_API`)
- KDE applications failing to start (KClock, Plasma widgets, etc.)
- Missing library errors
- Graphics glitches after update

**Diagnosis:**

```bash
# Check for pending updates
dnf check-update

# Check current NVIDIA driver version
rpm -qa | grep -i nvidia | sort

# Check for broken dependencies
dnf check
```

**Fix:**

```bash
# 1. Full system sync (recommended)
sudo dnf upgrade --refresh

# 2. If that doesn't work, force package alignment
sudo dnf distro-sync

# 3. Rebuild kernel modules
sudo akmods --force

# 4. Reboot
sudo reboot
```

**Prevention:**
- Always run full system updates (`dnf upgrade`) rather than partial updates
- Don't mix updates from different repos (especially RPM Fusion and Fedora)
- After NVIDIA updates, check for pending updates before rebooting

**Emergency recovery:**
If the system won't boot after NVIDIA update:
1. Boot with `nomodeset` kernel parameter
2. Run `sudo dnf upgrade --refresh`
3. Run `sudo akmods --force`
4. Reboot normally

### KDE Plasma Panel Applets - Black Text After Upgrade

Third-party panel applets (Window Title Fork, Thermal Monitor, Minimal Chaac Weather) can show black/unreadable text after a Fedora upgrade due to colour token changes in Plasma.

**Fix:** Install [Panel Colorizer](https://store.kde.org/p/2130967), then toggle any setting and apply to force a colour refresh across all panel widgets.

**Audio sink disappeared:** If built-in speakers vanish from audio settings, check the device profile — it may have switched to input-only. Set it back to Stereo Duplex in System Settings → Audio.

---

### Fedora Version Upgrade (DNF System Upgrade)

```bash
# 1. Import GPG key for new release (required if upgrade fails with signature error)
sudo rpm --import https://fedoraproject.org/static/keys/RPM-GPG-KEY-fedora-43-primary

# 2. Download upgrade packages
sudo dnf system-upgrade download --releasever=43

# 3. Reboot into upgrade environment (plug in first - don't upgrade on battery)
sudo dnf system-upgrade reboot
```

**Post-upgrade checklist:**
- `sudo dnf distro-sync` — clean up leftover packages from old release
- Check `/boot` space: `df -h /boot` — remove old kernels if >80%
- Remove old kernels: `sudo dnf remove kernel-{core,modules,}-<old-version>`
- Restart Docker containers: `docker start <name>`
- COPR repos may need re-enabling for new release: `sudo dnf copr enable <user>/<repo>`
- NVIDIA kmods: verify with `lsmod | grep nvidia` and `rpm -q kmod-nvidia | sort`

---

## Memory Management

System with 16GB RAM experiencing memory leaks reaching 90%+ usage after extended use (22+ days uptime).

### Known Memory Leak Culprits

**Identified Issues:**
1. **Copilot.lua language server** - Can leak to 879MB+ if Neovim left open in tmux
2. **Zen Browser** (Firefox-based) - Accumulates zombie processes over time ([GitHub #11721](https://github.com/zen-browser/desktop/issues/11721))
3. **Obsidian plugins** - terminal (never clears buffers), hover-editor (known leak)
4. **Dark Reader extension** - Dynamic mode can cause infinite memory growth (500MB+)

### Memory Monitoring Tools

**Created scripts in `~/bin/`:**

| Command | Description |
|---------|-------------|
| `memory-watchdog` | Check all known leaky apps, log to `~/.cache/memory-watchdog.log` |
| `check-browser-memory` | Check Zen browser total memory across processes |
| `check-obsidian-memory` | Check Obsidian total memory and plugin list |
| `monitor-memory` | Log memory usage every 5 min to `~/.cache/memory-monitor-YYYY-MM-DD.log` |
| `analyze-memory-leaks` | Analyze monitor logs to identify growing processes |
| `free-memory` | Emergency cleanup: restart copilot, clear caches |
| `auto-restart-leaky-apps` | Auto-restart Zen/Obsidian when exceeding thresholds |

**Usage:**
```bash
# Quick check current state
memory-watchdog

# Start continuous monitoring (every 5 min)
monitor-memory &

# Analyze logs to find leak culprit
analyze-memory-leaks

# Emergency cleanup when at 90%+
free-memory
```

### Applied Solutions

**Zen Browser Optimizations (`about:config`):**
```
browser.cache.memory.capacity → 102400       # 100MB (down from ~1GB)
browser.cache.disk.capacity → 102400         # 100MB disk cache
browser.sessionhistory.max_entries → 5       # 5 pages (down from 50)
config.trim_on_minimize → true               # Free memory when minimized
dom.ipc.processCount → 4                     # 4 processes (down from 8)
browser.sessionstore.interval → 30000        # Save every 30s (down from 15s)
browser.tabs.remote.warmup.enabled → false   # Disable tab warmup
network.http.max-connections → 30            # Limit connections
```

**Obsidian Plugin Changes:**
- ✅ **Disabled:** terminal (buffer leak), hover-editor (known leak)
- ⚠️ **Monitor:** excalidraw (8.4MB, close canvases when done)
- **Large vault:** 2,439 markdown files = higher baseline memory

**Dark Reader Optimization (if using):**
```
Settings → Performance:
- ✅ Use system color scheme
- ❌ Disable "Dynamic Theme Generation"
- Switch to "Filter" mode (83% memory reduction)
```

### Expected Memory Baseline

After optimizations on 16GB system:

| State | Memory Usage | Percentage |
|-------|--------------|------------|
| **Baseline (boot)** | ~3.2GB | 20% |
| **+ Discord/Spotify** | ~6GB | 38% |
| **+ Zen/Claude** | ~7.8GB | 49% |
| **+ Obsidian** | ~8.8GB | 55% |
| **After fixes** | ~7GB | 44% |

**Warning thresholds:**
- **Normal:** <75% RAM
- **Monitor:** 75-85% RAM
- **Critical:** >85% RAM (systemd timer alerts)

### Common Issues & Fixes

**Zen Browser memory growth:**
- Check zombie processes: `pgrep -f "zen/zen" | wc -l`
- Should be ~10-15 processes, not 100+
- Check `about:memory` in browser for heavy tabs
- Restart Zen if total exceeds 2.5GB

**Obsidian memory growth:**
- Check terminal panes left open (never clear buffers)
- Close Excalidraw canvases when done
- Restart Obsidian if exceeds 2GB
- Vault size matters: 2,439 notes = ~600MB baseline

**Forgotten Neovim instances:**
- Check: `ps aux | grep nvim | grep -v grep`
- Copilot language server spawns per nvim instance
- Each can leak to 500-800MB over time
- Close forgotten tmux windows with nvim open

### Community References

Issues confirmed by other users:

- [Obsidian Large Vault Memory (6-10GB)](https://forum.obsidian.md/t/request-for-assistance-with-memory-issue-in-obsidian/97962)
- [Obsidian 4GB Electron/V8 Limit](https://forum.obsidian.md/t/basic-memory-management-to-avoid-oom-errors/102927)
- [Zen Browser Memory Leak (40GB over time)](https://github.com/zen-browser/desktop/issues/11721)
- [Zen Zombie Processes (1,499 instances)](https://github.com/zen-browser/desktop/issues/10797)
- [Dark Reader Memory Leak (1GB spike)](https://github.com/darkreader/darkreader/issues/8865)
- [Firefox Memory Optimization Guide](https://support.mozilla.org/en-US/kb/firefox-uses-too-much-memory-or-cpu-resources)

---

## Quick Reference

```bash
# Tmux
tmux                    # Start/attach session
ta <name>               # Attach to session (oh-my-zsh alias)
tl                      # List sessions
ts <name>               # New named session

# Tmux Layouts (laio)
laio list               # List available layouts
laio start <name>       # Start layout session
laio stop <name>        # Stop layout session

# Navigation
z <dir>                 # Jump to frecent directory (zoxide)
Ctrl+h/j/k/l            # Navigate vim/tmux panes

# Cheatsheets
cs <topic>              # View cheatsheet
cs <topic> <term>       # Search within cheatsheet
csp                     # Personal cheatsheets

# Python
pyenv versions          # List installed versions
pyenv install <ver>     # Install Python version
pyenv local <ver>       # Set local version
```
