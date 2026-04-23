# ADR 003 — claude-config as a local-only repo (deferred publish)

- **Status:** accepted (transitional)
- **Date:** 2026-04-23
- **Amends:** ADR 001
- **Superseded by:** (none yet — will supersede this when claude-config is published)

## Context

During Phase 2 adoption, `~/.claude/` was initially committed into the
main `maefiles` yadm repo, with personal files wrapped by git-crypt to
protect student number, legal name, and medical references.

Two concerns arose:

1. **SNDL risk.** git-crypt wraps AES-256 with RSA-4096 (via GPG). AES
   itself is quantum-resistant but RSA-4096 is not. An adversary who
   snapshots the repo today and breaks RSA in future decrypts historic
   commits retroactively. For permanent identifiers (student number,
   legal name) and lifelong medical references, this is not
   theoretical enough to ignore.

2. **Scope coupling.** Mixing public-safe configs (hooks, statuslines)
   with deeply personal files in one repo makes `maefiles` hard to ever
   publish, forever.

## Decision

**Separate `~/.claude/` into its own git repo**, mirroring how
`~/.config/nvim/` is treated (own repo at `cadrianmae/nvim-config`).

**However, do not push yet.** The current `~/.claude/` tree contains raw
PII that should be scrubbed or templated before any remote push — even
to a private repo. Until that cleanup lands, the claude-config repo is
**local only**:

- `~/.claude/.git` exists and tracks commits locally
- No GitHub remote yet
- yadm explicitly ignores `.claude/` (`./.gitignore` entry)
- Not wired as a submodule

## Consequences

### Advantages

- **No PII in maefiles at all.** maefiles can eventually be made public
  without leaking anything personal.
- **Privacy via access control, not crypto.** When claude-config is
  eventually pushed to a private repo, GitHub's auth (password + 2FA +
  SSH key) protects the data — not RSA-4096. Orthogonal to quantum
  threats.
- **Staged migration.** We can do PII cleanup incrementally without
  blocking other Phase 2 work.
- **Same mental model as nvim-config.** One pattern for "code repos
  that happen to live inside $HOME".

### Disadvantages

- **No single-command bootstrap for `.claude` on new machines** (yet).
  Until published, users must manually rsync or scp the directory over.
- **Transitional state.** The migration is incomplete until claude-config
  is published.

## Required follow-up

See `docs/runbooks/publish-claude-config.md` for the PII cleanup +
publish sequence. Do NOT push claude-config to any remote until that
runbook is completed.

### Checklist before publishing

- [ ] Template student number as `{{ .student_id }}` in `CLAUDE.md` + `rules/academic.md`
- [ ] Template legal name as `{{ .name_full }}` / `{{ .name_first }}` in same files
- [ ] Review `rules/neurodivergence.md` + `rules/me/neurodivergence.md` — decide: scrub, keep, or move into a git-crypted sub-scope
- [ ] Review `memory.md` — it references project paths + personal work; audit before publishing
- [ ] Add `pass show academic/student-id`, `pass show identity/name-full` items to the manifest
- [ ] Add post-render step in `post_alt` hook for claude-config templates
- [ ] Decide: rules file per-repo (if templates reference `pass`, template rendering must happen where both pass and files coexist — i.e. at bootstrap time)
- [ ] Create `cadrianmae/claude-config` **private** repo on GitHub
- [ ] Push
- [ ] Add as yadm submodule (mirror nvim-config setup)
- [ ] Supersede this ADR with `004-claude-config-submodule.md`

## Alternatives rejected

- **Keep git-crypt in maefiles** — rejected in this amendment due to SNDL risk on permanent identifiers.
- **Scrub inline without splitting** — would work, but mixing public-safe + personal in one repo still couples their lifecycles.
- **Skip tracking `.claude/` entirely** — loses bootstrap benefit and version history of the personal files.

## Related

- Design spec: `~/dotfiles-plan/docs/superpowers/specs/2026-04-20-dotfiles-yadm-design.md`
- Previous ADR: `decisions/001-yadm-over-chezmoi.md`, `decisions/002-bws-over-bw-for-secrets.md`
- Runbook: `runbooks/publish-claude-config.md` (to be written)
