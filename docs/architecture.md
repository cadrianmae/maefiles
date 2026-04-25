# Architecture

The full design spec lives outside this site at `~/dotfiles-plan/docs/superpowers/specs/2026-04-20-dotfiles-yadm-design.md` (working-copy artefact from the brainstorming phase). This document is a condensed in-repo reference.

## Three-layer secret flow

```
Bitwarden Secrets Manager  →  pass  →  ~/.env (sourced by .zshrc)
         (source of truth)   (local)    (daily reads)
```

- **BWS** — source of truth. Touched only on new-machine bootstrap and when `yadm-refresh-secrets` runs (TTL-triggered or manual).
- **pass** — on-machine cache, GPG-encrypted. Read by scripts (`build-memory`, `convert-pdf`, etc.) and by `.env##template.esh` during `yadm alt`.
- **gpg-agent** — 24h passphrase cache. One pinentry prompt per day; every `pass show` within 24h is instant.

## Three-cache rhythm

| Cache | Refresh cadence |
|---|---|
| Bitwarden | Monthly-ish, manual rotation |
| pass | 7-30 days per secret (TTL from `manifest.yaml`) |
| gpg-agent | 24h (config in `~/.gnupg/gpg-agent.conf`) |

Each layer's TTL is strictly longer than the one above → every read hits the fastest available cache, upstream resync only when needed.

## Manifest-driven template (B.1)

Single source of truth: `docs/secret/manifest.yaml` (git-crypt encrypted).

- `bin/render-env` generates `.env##template.esh` from the manifest (gitignored; regenerated locally)
- `.config/yadm/bootstrap` uses the same manifest to seed `pass` from BWS
- `bin/yadm-audit` + `bin/yadm-check-staleness` read the manifest for verification

No duplication: adding a new secret = one line in `manifest.yaml`.

## Seven-layer leakage defence

1. **Structural** — rendered outputs (`.env`, `.env##template.esh`) gitignored
2. **Pre-commit** — `gitleaks` + `shellcheck` + `yadm-audit`
3. **Pre-push / yadm pre_commit hook** — second gitleaks pass
4. **`yadm encrypt`** — SSH keys wrapped into GPG archive
5. **`git-crypt`** — transparent file encryption for `docs/secret/**`
6. **`bin/yadm-verify-encryption`** — locks git-crypt, scans tree for leaks
7. **Identity separation** — `.gitconfig##template.esh` branches on `$YADM_CLASS`

## Runbooks

- `docs/runbooks/new-machine.md` — bootstrap on a new system
- `docs/runbooks/rotate-secret.md` — rotate an API key end-to-end
- `docs/runbooks/recovery.md` — GPG key loss, machine account revocation
