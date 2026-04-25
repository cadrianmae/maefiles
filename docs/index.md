# maefiles

Personal dotfiles, secrets, ADRs, runbooks, and system documentation for `cadrianmae`. Managed by [yadm](https://yadm.io) with a single GPG key gating `pass` (on-machine cache), `git-crypt` (in-repo encryption), and commit signing. Bitwarden Secrets Manager is the source of truth for API keys.

## Sections

- **[Architecture](architecture.md)** — how the pieces fit together
- **Guides** — system & tooling how-tos:
    - [Shell environment](guides/shell.md) — zsh, tmux, version managers
    - [Neovim](guides/neovim.md) — AstroNvim v4, LSP, language quirks
    - [Desktop — KDE Plasma](guides/desktop-kde.md) — Karousel scrolling tiler, Catppuccin
    - [Desktop — Niri](guides/desktop-niri.md) — scrolling Wayland compositor
    - [Audio stack](guides/audio.md) — PipeWire, WirePlumber, EasyEffects, Piper TTS, CAVA
    - [Pomodoro timer](guides/pomodoro.md) — CLI timer with audio + voice + Obsidian logging
    - [Git configuration](guides/git-config.md) — gitconfig, commit template, soft-warn hook
    - [systemd user units](guides/systemd-user-units.md) — services + timers
    - [Memory management](guides/memory-management.md) — leak watchdogs and per-app fixes
- **Runbooks** — concrete procedures:
    - [New machine](runbooks/new-machine.md) · [Loading keys](runbooks/loading-keys.md) · [Rotate secret](runbooks/rotate-secret.md)
    - [Recovery](runbooks/recovery.md) · [GPG key recovery](runbooks/gpg-key-recovery.md) · [Publish claude-config](runbooks/publish-claude-config.md)
    - [Upgrade Fedora](runbooks/upgrade-fedora.md) · [Troubleshoot NVIDIA](runbooks/troubleshoot-nvidia.md) · [Troubleshoot KDE applets](runbooks/troubleshoot-kde-applets.md)
- **Reference**:
    - [CLI tools](reference/cli-tools.md) — env vars, file locations, custom commands
    - [Git aliases](reference/git-aliases.md) — full oh-my-zsh git plugin reference
    - [Config inventory](reference/config-inventory.md) — every tracked config file, by area
- **[ADRs](decisions/001-yadm-over-chezmoi.md)** — the why behind every decision
- **[Specs](specs/2026-04-20-dotfiles-yadm-design.md)** — original brainstorm artefacts

## Conventions

- ADRs live in `docs/decisions/NNN-kebab-title.md`. Scaffold one with `just new-adr "title"`.
- Runbooks live in `docs/runbooks/<verb>-<noun>.md`. Scaffold with `just new-runbook "verb noun"`.
- Anything under `docs/secret/**` is git-crypted and excluded from this site.

## Local preview

```bash
just docs-serve  # http://127.0.0.1:7700
```
