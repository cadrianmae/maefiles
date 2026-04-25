# CLI tools reference

Custom commands, environment variables, and file locations. The shell and tmux setup that hosts these tools is documented in [Shell environment](../guides/shell.md).

## Custom commands

### `convert-pdf` — PDF → markdown with OCR + AI enhancement

```bash
convert-pdf document.pdf                    # basic
convert-pdf document.pdf --enhance          # AI enhancement (light)
convert-pdf document.pdf --enhance medium   # medium
convert-pdf *.pdf -o output/                # batch
```

| Option | Effect |
|---|---|
| `--enhance [level]` | AI cleanup — `light` / `medium` / `heavy` |
| `--doc-style <style>` | `article` / `presentation` / `academic` / `notes` / `technical` / `email` |
| `--frontmatter <style>` | `obsidian` / `pandoc` / `minimal` / `none` |
| `--save-images` | Save to subdir (default) |
| `--embed-images` | Inline as base64 |
| `--preset <name>` | `obsidian` / `pandoc` / `clean` / `academic` |

OCR backends: `mistral`, `pymupdf`, `claude`, `marker`.

### `build-memory` — Claude Code per-project memory summaries

Reads the last 30 days of Claude Code transcripts for a project and writes a 200–300 word summary to `<project>/.claude/memory.md`. Runs daily at 23:00 via `build-memory.timer` (only processes projects with activity in the last 24h).

```bash
build-memory                    # current dir
build-memory /path/to/project
build-memory --all              # every active project, batched into one Claude call
```

| Env var | Default | Effect |
|---|---|---|
| `BUILD_MEMORY_VERBOSE` | `false` | Show progress |

```bash title="manual control"
systemctl --user enable build-memory.timer
systemctl --user disable build-memory.timer
systemctl --user list-timers build-memory.timer
journalctl --user -u build-memory.service -n 50
systemctl --user start build-memory.service
```

### Memory monitoring

See [Memory management](../guides/memory-management.md) for the full set (`memory-watchdog`, `monitor-memory`, `analyze-memory-leaks`, `free-memory`, etc.).

## CLI utilities (third-party)

| Tool | Purpose | Config |
|------|---------|--------|
| `zoxide` | Frecency `cd` (`z <dir>`) | oh-my-zsh plugin |
| `fzf` | Fuzzy finder | Used by cheat + tmux |
| `direnv` | Per-directory env | `~/.zshrc` hook |
| `cheat` | Cheatsheets w/ fzf | `~/.config/cheat/conf.yml` |
| `btop` | System monitor | `~/.config/btop/btop.conf` |
| `odino` | Semantic code search | wrapper function in `~/.zsh_functions` |
| `laio` | Flexbox-style tmux layouts | `~/.config/laio/` |

## Environment variables

| Variable | Value | Purpose |
|---|---|---|
| `EDITOR` | `nvim` (local) / `vim` (SSH) | Default editor |
| `MANPAGER` | `nvim +Man!` | Man pages in nvim |
| `CHEAT_USE_FZF` | `true` | fzf in cheat |
| `ZSH_TMUX_CONFIG` | `$HOME/.tmux.conf` | Tmux config path for oh-my-zsh |

## File locations

```
~/.zshrc                    # main zsh config
~/.zsh_aliases              # aliases
~/.zsh_functions            # functions
~/.tmux.conf                # tmux
~/.tmux/plugins/            # TPM plugins
~/.config/nvim/             # AstroNvim
~/.config/btop/             # btop
~/.config/cheat/            # cheat
~/.config/laio/             # laio
~/.config/pomodoro/         # pomodoro scripts + sounds
~/.claude/                  # Claude Code config (own repo, see ADR 003)
~/bin/                      # personal scripts
~/lib/                      # shared shell helpers (runlib.sh)
~/docs/                     # this site's source
```

## Related

- [Shell environment](../guides/shell.md) — how it's all wired together
- [Git aliases](git-aliases.md)
