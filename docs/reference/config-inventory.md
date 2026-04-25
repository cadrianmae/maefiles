# Config inventory

Every config file tracked in this repo, grouped by area. The "Documented in" column points at the guide / runbook / reference that explains it. Generate this list yourself with `yadm ls-files`.

## Shell

| Path | Documented in |
|---|---|
| `.zshrc`, `.zshenv`, `.zsh_aliases`, `.zsh_functions` | [Shell environment](../guides/shell.md) |
| `.bashrc`, `.bash_profile`, `.profile` | [Shell environment](../guides/shell.md) |
| `.tmux.conf` | [Shell environment](../guides/shell.md) |
| `shell/env-key.zsh` | [Loading keys](../runbooks/loading-keys.md) |
| `lib/runlib.sh` | helper used by install.sh + bootstrap |

## Editor

| Path | Documented in |
|---|---|
| `.config/nvim` (submodule) | [Neovim](../guides/neovim.md); deep-dive in `~/.config/nvim/CLAUDE.md` |

## Desktop — Niri / Wayland

| Path | Documented in |
|---|---|
| `.config/niri/config.kdl` | [Niri](../guides/desktop-niri.md) |
| `.config/niri/scripts/{power-monitor,usb-monitor}.sh` | [Niri](../guides/desktop-niri.md) |
| `.config/waybar/{config,style.css,catppuccin.css}` | [Niri](../guides/desktop-niri.md) |
| `.config/waybar/scripts/*.sh` | [Niri](../guides/desktop-niri.md) — progress-bar generators |
| `.config/rofi/{config.rasi,catppuccin-macchiato.rasi,keybinds.txt}` | [Niri](../guides/desktop-niri.md) |
| `.config/rofi/scripts/keybinds.sh` | [Niri](../guides/desktop-niri.md) |
| `.config/fuzzel/fuzzel.ini` | [Niri](../guides/desktop-niri.md) |
| `.config/wofi/{config,style.css}` | [Niri](../guides/desktop-niri.md) |
| `.config/mako/config` | [Niri](../guides/desktop-niri.md) — notification daemon |
| `.config/wlogout/{layout,style.css}` | [Niri](../guides/desktop-niri.md) — power menu |
| `.config/swaylock/config` | [Niri](../guides/desktop-niri.md) — lock screen |
| `.config/kitty/{kitty.conf,catppuccin-macchiato.conf,current-theme.conf}` | [Niri](../guides/desktop-niri.md) — terminal emulator |
| `.config/xsettingsd/xsettingsd.conf` | [Niri](../guides/desktop-niri.md) — GTK settings under Wayland |

## Audio

| Path | Documented in |
|---|---|
| `.config/pipewire/pipewire.conf.d/51-memlock.conf` | [Audio stack](../guides/audio.md) |
| `.config/wireplumber/wireplumber.conf.d/{50-safer-default-volume,51-mic-soft-mixer}.conf` | [Audio stack](../guides/audio.md) |
| `.config/easyeffects/output/*.json` (28 presets) | [Audio stack](../guides/audio.md) |
| `.config/easyeffects/input/*.json` | [Audio stack](../guides/audio.md) |
| `.config/easyeffects/irs/*.irs` (14 IRs) | [Audio stack](../guides/audio.md) |
| `.config/easyeffects/autoload/output/*.json` | [Audio stack](../guides/audio.md) — per-device autoload |
| `.config/speech-dispatcher/speechd.conf` | [Audio stack](../guides/audio.md) |
| `.config/speech-dispatcher/modules/piper-generic.conf` | [Audio stack](../guides/audio.md) |
| `.config/speech-dispatcher/piper/{daemon.py,client.py,run.sh}` | [Audio stack](../guides/audio.md) |
| `.config/speech-dispatcher/desktop/speechd.desktop` | [Audio stack](../guides/audio.md) |
| `.config/speech-dispatcher/backups/*` | historical backups (kept for reference) |
| `.config/cava/{config,waybar.conf,shaders/*}` | [Audio stack](../guides/audio.md) |

## Pomodoro

| Path | Documented in |
|---|---|
| `.config/pomodoro/{cycle,watcher,orchestrator,design-sounds}.sh` | [Pomodoro timer](../guides/pomodoro.md) |
| `.config/pomodoro/sounds/*.wav` | [Pomodoro timer](../guides/pomodoro.md) |

## Git

| Path | Documented in |
|---|---|
| `.gitconfig` | [Git configuration](../guides/git-config.md) |
| `.config/git/ignore` | [Git configuration](../guides/git-config.md) |
| `.config/git/template/{commit-template.txt,description,hooks/commit-msg}` | [Git configuration](../guides/git-config.md) |

## Yadm + secrets

| Path | Documented in |
|---|---|
| `.config/yadm/{bootstrap,config,encrypt,hooks/*}` | [Architecture](../architecture.md), [New machine](../runbooks/new-machine.md) |
| `.gitattributes`, `.gitignore`, `.gitmodules` | [Architecture](../architecture.md) |
| `.git-crypt/keys/default/0/*.gpg` | [GPG key recovery](../runbooks/gpg-key-recovery.md) |
| `docs/secret/manifest.yaml` | [Architecture](../architecture.md) — git-crypted |
| `install.sh` | [New machine](../runbooks/new-machine.md) |

## CLI helpers — `bin/`

| Path | Documented in |
|---|---|
| `bin/yadm-{audit,check-staleness,discover,refresh-secrets,verify-encryption}` | [Recovery](../runbooks/recovery.md), [Loading keys](../runbooks/loading-keys.md) |
| `bin/render-env`, `bin/pii-scan` | [Architecture](../architecture.md), [New machine](../runbooks/new-machine.md) |
| `bin/cleanup-review` | [`docs/cleanup/README.md`](https://github.com/cadrianmae/maefiles/blob/main/docs/cleanup/README.md) |
| `bin/new-adr`, `bin/new-runbook` | [Home](../index.md) — scaffolds |
| `bin/{memory-watchdog,monitor-memory,analyze-memory-leaks,free-memory,auto-restart-leaky-apps}` | [Memory management](../guides/memory-management.md) |
| `bin/{check-browser-memory,check-obsidian-memory,memcheck.sh,monitor-zram}` | [Memory management](../guides/memory-management.md) |
| `bin/{cc-ask,claude-bare,claude-memory-index,claude-session-list,claude-session-summary,claude-usage-status}` | [CLI tools](cli-tools.md) — Claude Code helpers |
| `bin/{jsonl-to-markdown,markdown-tabs}` | [CLI tools](cli-tools.md) |
| `bin/{convert-pdf,build-memory}` (in `~/.local/bin`) | [CLI tools](cli-tools.md) |
| `bin/{sp,spotify-cli}` | [CLI tools](cli-tools.md) |
| `bin/{dslrcam,dslr-pipeline.sh}` | [CLI tools](cli-tools.md) |
| `bin/godot-dev` | [CLI tools](cli-tools.md) |
| `bin/{nvim-sync,parse-d2l-toc,transcribe.py,watch-transcript.sh}` | [CLI tools](cli-tools.md) |
| `bin/{cleanup_folder,organize_images.sh,monitor}` | [CLI tools](cli-tools.md) |
| `bin/eduroam-linux-TU_Dublin-TU_Dublin_Students.py` | TU Dublin eduroam installer (third-party) |

## systemd --user

| Path | Documented in |
|---|---|
| `.config/systemd/user/build-memory.{service,timer}` | [systemd user units](../guides/systemd-user-units.md) |
| `.config/systemd/user/memory-notify.{service,timer}` | [systemd user units](../guides/systemd-user-units.md) |
| `.config/systemd/user/piper-daemon.service` | [systemd user units](../guides/systemd-user-units.md) |
| `.config/systemd/user/todoist-ai.service` | [systemd user units](../guides/systemd-user-units.md) |
| `.config/systemd/user/yadm-secrets-check.{service,timer}` | [systemd user units](../guides/systemd-user-units.md) |

## Other tooling

| Path | Tool / role |
|---|---|
| `.config/bat/config`, `.config/bat/themes/Catppuccin*.tmTheme` | `bat` — pretty `cat` with Catppuccin themes |
| `.config/btop/btop.conf` | `btop` system monitor |
| `.config/cheat/conf.yml` | `cheat` cheatsheets (fzf-driven via `cs`) |
| `.config/claudia-statusline/config.toml` | claudia statusline customisation |
| `.config/laio/dev.yaml` | flexbox-style tmux layout |
| `.config/swi-prolog/{dir-history/*,xpce/Tracer.cnf}` | SWI-Prolog history + tracer state |

## Site & repo plumbing

| Path | Role |
|---|---|
| `mkdocs.yml` | [Home](../index.md) — site config |
| `justfile` | task runner (`docs-serve`, `health`, `new-adr`, …) |
| `.pre-commit-config.yaml` | pre-commit hooks (gitleaks + shellcheck + yadm-audit) |
| `.github/workflows/ci.yml` | CI: shellcheck + gitleaks + install.sh dry-run |
| `README.md` | repo landing |
| `docs/**/*.md` | this site's source |
