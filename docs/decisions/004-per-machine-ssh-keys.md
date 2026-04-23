# ADR 004 — per-machine SSH keys; empty yadm encrypt scope

- **Status:** accepted
- **Date:** 2026-04-23

## Context

The scaffold's `.config/yadm/encrypt` originally listed SSH keys
(`id_ed25519`, `id_rsa`, `known_hosts`) and GPG revocation certs. Running
`yadm encrypt` would bundle these, GPG-encrypt them with Mae's key, and
produce a committable archive at `~/.local/share/yadm/archive`. Intent
was single-command bootstrap on a new machine — `yadm clone && yadm
decrypt` would materialise SSH keys automatically.

## Decision

**Do not track SSH keys in yadm.** Each machine generates its own SSH
keypair locally. `.config/yadm/encrypt` is stripped to a commented-out
scaffold for future use; no archive exists.

## Consequences

### Advantages

- **Better blast radius.** A compromised GPG key doesn't expose SSH
  access on every other machine. One compromised machine → revoke one
  key from GitHub + servers; other machines unaffected.
- **GPG is no longer a single point of failure for SSH.** The GPG key
  protects git-crypt-scoped content and pass, but SSH auth is
  independent.
- **Aligns with standard device-lifecycle posture** — per-device keys
  are the default recommendation from most security guides.

### Disadvantages

- **Extra step on new-machine bootstrap:** `ssh-keygen -t ed25519`, add
  the public key to GitHub + any servers. ~15 seconds per machine.
- **The `yadm submodule` for `.config/nvim` uses HTTPS** (not SSH) to
  avoid chicken/egg between SSH key setup and submodule clone. Same for
  `maefiles` itself if we ever want bootstrap before SSH keys exist.

## What changes

- `.config/yadm/encrypt`: stripped to comments only; no patterns active.
- `.config/yadm/config`: keeps `gpg-recipient = C8ABE62412652B9E` as a
  default in case something else gets added later.
- `install.sh`: already uses SSH URL for the maefiles repo; follow-up
  needed to switch to HTTPS OR document the "generate SSH key first,
  add to GitHub, then bootstrap" flow.
- `docs/runbooks/new-machine.md`: update — add SSH key generation +
  GitHub registration step.

## Alternatives rejected

- **Track encrypted SSH keys** (original scaffold). Rejected for
  blast-radius reasons.
- **Track only GPG revocation certs.** Marginal — the rev cert is only
  useful if the main GPG key is compromised, and at that point the
  attacker has the archive too (it's wrapped by that same key). Store
  rev certs offline instead (printed or on a separate USB).

## Related

- ADR 001: yadm over chezmoi (overall framework)
- ADR 003: claude-config as deferred local-only repo
- Runbook: `docs/runbooks/new-machine.md` (needs SSH step added)
