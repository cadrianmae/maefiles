# maefiles — docs

Documentation for the `maefiles` yadm-managed dotfiles repo.

## Map

```
docs/
├── README.md                              this file — nav index
├── architecture.md                        three-layer secret flow, TTL rhythm,
│                                          manifest-driven template, leakage defences
├── decisions/                             Architecture Decision Records (ADRs)
│   ├── 001-yadm-over-chezmoi.md           why yadm; what it costs us
│   └── 002-bws-over-bw-for-secrets.md     why Secrets Manager not just the password CLI
├── runbooks/                              how-to guides
│   ├── new-machine.md                     bootstrap on a fresh system
│   ├── rotate-secret.md                   rotate an API key end-to-end
│   └── recovery.md                        GPG loss, token compromise, broken repo
└── secret/                                git-crypt encrypted
    └── manifest.yaml                      SSOT: env ↔ pass ↔ BWS mapping + TTL
```

## Getting started

New machine? Start at [runbooks/new-machine.md](runbooks/new-machine.md).

Rotating a secret? See [runbooks/rotate-secret.md](runbooks/rotate-secret.md).

Lost a key or a machine? See [runbooks/recovery.md](runbooks/recovery.md).

## Understanding the design

Architecture at a glance — [architecture.md](architecture.md).

Why yadm + BWS + pass (and not chezmoi / raw bw / Nix)? See the ADRs in [decisions/](decisions/).

## Conventions

- ADRs are numbered `NNN-short-kebab-slug.md`. Status + date in frontmatter. Never reword an accepted ADR; supersede it with a new one.
- Runbooks are task-oriented: opening line states the *scenario* ("I need to rotate a key"), not the title of the feature.
- `docs/secret/**` is git-crypt encrypted. If a file in there reads like binary goop, run `yadm git-crypt unlock`.
