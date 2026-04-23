# ADR 001 — yadm over chezmoi

- **Status:** accepted
- **Date:** 2026-04-20
- **Superseded by:** —

## Context

Need to pick a dotfiles manager. Considered chezmoi, yadm, GNU Stow (current), plain bare-git, home-manager. Shortlist came down to chezmoi vs yadm after a feature comparison.

Mae's profile:

- 2-3 similar Linux machines
- Uses password-manager-backed secrets (Bitwarden)
- Wants real files (not symlinks) and low lock-in
- Already has existing scripts (`build-memory`, `convert-pdf`, `transcribe.py`) that use API keys outside the dotfiles rendering pipeline

## Decision

Use **yadm** with three tiers: Bitwarden Secrets Manager → pass → dotfiles.

## Consequences

### Advantages

- Real files in `$HOME`, not symlinks — some tools misbehave with symlinked configs
- Feels like git; well-understood mental model
- `pass` becomes a **general-purpose local secret store** — any shell script can read `pass show api/foo` without knowing about yadm. chezmoi's secrets stay siloed inside its rendering pipeline.
- No daily Bitwarden unlock — bw is touched only on machine bootstrap or TTL resync; `pass` handles daily reads
- One GPG key covers pass + yadm encrypt + git-crypt + commit signing
- Low lock-in: if yadm is abandoned, files are already in place; walk away by deleting `~/.local/share/yadm/`

### Disadvantages

- More glue to maintain than chezmoi (~100 LOC across `bin/` scripts + bootstrap)
- Less prior art online for yadm + BWS specifically
- Manifest-driven template is a custom mechanism we own (chezmoi has built-in PM templates)

## Alternatives rejected

- **chezmoi** — would save ~100 LOC of glue. Rejected because it ties secrets to the rendering pipeline; shell scripts couldn't read secrets without running chezmoi. Also imposes an edit/apply cycle.
- **bare git repo** — simplest possible. Rejected because no templating or per-machine divergence.
- **home-manager / Nix** — most reproducible. Rejected because of lock-in and steep learning curve for a personal dotfiles project.
- **GNU Stow (current)** — rejected because of symlink fragility, no encryption, no per-machine alternates, no template engine.

## Related

- Full design spec: `docs/superpowers/specs/2026-04-20-dotfiles-yadm-design.md`
- Transcript of the brainstorm: `docs/transcript-2026-04-20-dotfiles-brainstorm.md`
