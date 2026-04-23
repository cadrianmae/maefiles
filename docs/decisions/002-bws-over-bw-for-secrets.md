# ADR 002 — Bitwarden Secrets Manager over bw password manager for dotfile secrets

- **Status:** accepted
- **Date:** 2026-04-20
- **Amends:** ADR 001 (refines the BW→pass layer)

## Context

Initial design used Bitwarden Password Manager CLI (`bw get`) for the machine-bootstrap flow. Mae already pays for Bitwarden, so Secrets Manager (BWS) is available — its free tier allows 2 machine accounts + unlimited secrets.

## Decision

Use **BWS** (`bws` CLI) instead of `bw` for the secret seeding step. Retain `bw` only for one specific purpose: retrieving the BWS access token from the personal vault at bootstrap time (so the token never lives plaintext on disk).

## Flow

```
Personal bw vault  →  BWS access token (one-time interactive unlock per machine)
BWS project        →  secret values        (non-interactive via access token)
                   →  pass                  (seeded once, TTL-refreshed)
```

## Consequences

### Advantages

- **Purpose-built for programmatic access** — BWS is designed for machine consumers; bw is designed for humans
- **Per-machine access tokens** — revoke one machine without touching others; better blast radius
- **Audit trail** — BWS logs secret reads
- **Non-interactive after bootstrap** — every refresh is zero-prompt (given a valid access token)
- **Separation of concerns** — personal credentials (logins, notes) stay in the password manager; API keys / machine secrets live in Secrets Manager

### Disadvantages

- Two CLIs to install (`bw` + `bws`) vs just one
- BWS access token still needs secure storage — resolved by storing it IN the personal bw vault, so the chicken/egg reduces to "one master password at bootstrap"
- Free tier caps at 2 machine accounts — sufficient for 2-3 machines if we reuse accounts per class (personal machines share one account; work gets its own)

## Implementation

- `install.sh` installs both `bw` + `bws` from official sources
- `.config/yadm/bootstrap` retrieves token via `bw get password "BWS Access Token - $(hostname -s)"` then uses `bws secret get` for values
- Machine-account setup documented in `docs/runbooks/new-machine.md`
