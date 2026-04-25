# maefiles

Personal dotfiles, secrets, ADRs, and runbooks for `cadrianmae`. Managed by [yadm](https://yadm.io) with a single GPG key gating `pass` (on-machine cache), `git-crypt` (in-repo encryption), and commit signing. Bitwarden Secrets Manager is the source of truth for API keys.

## Quick links

- **[Architecture](architecture.md)** — how the pieces fit together
- **[ADRs](decisions/001-yadm-over-chezmoi.md)** — the why behind every decision
- **Runbooks** — concrete procedures:
    - [New machine](runbooks/new-machine.md) — bootstrap a fresh install
    - [Loading keys](runbooks/loading-keys.md) — env-key, direnv, on-demand patterns
    - [Rotate secret](runbooks/rotate-secret.md) — update bw → pass → env
    - [Recovery](runbooks/recovery.md) — losing this machine
    - [GPG key recovery](runbooks/gpg-key-recovery.md) — backups + restoration
    - [Publish claude-config](runbooks/publish-claude-config.md) — separate repo workflow

## Conventions

- ADRs live in `docs/decisions/NNN-kebab-title.md` and follow a consistent template (status, context, decision, alternatives, consequences).
- Runbooks live in `docs/runbooks/<verb>-<noun>.md` and lead with prerequisites + the happy-path procedure.
- Anything under `docs/secret/**` is git-crypted and excluded from this site.

## Local preview

```bash
just docs-serve  # http://127.0.0.1:7700
```
