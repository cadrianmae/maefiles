# ADR 006 — never use `yadm stash -u`; enforce gc auto-thresholds

- **Status:** accepted
- **Date:** 2026-04-23

## Context

During Phase 3 (git-crypt unlock/lock cycling), an invocation of

```bash
yadm stash push -u -m "..."
```

hung for 15+ minutes then was killed. After the kill, yadm's bare repo
at `~/.local/share/yadm/repo.git` was **133 GB**, with:

- One 28 GB orphan tmp_pack file (partial repack never finalised)
- Hundreds of loose blobs totalling ~100 GB (100-500 MB each)

Root cause: yadm's work-tree is `$HOME`. `stash push -u` captures all
**untracked** files in the work-tree. In yadm's case that means
`~/Downloads/`, `~/Videos/`, `~/.cache/`, `~/.local/share/*`, browser
caches, everything a home directory accumulates. git blob-encoded
every one of those into the object store before the kill.

Recovery was clean — `git gc --prune=now --aggressive` reclaimed the
full 133 GB down to 8.1 MB (normal for a ~200-file repo). But the
footgun remains.

## Decision

**Never use `yadm stash -u` or any wildcard-including-untracked
operation on yadm.** The `-u` flag is safe on a normal repo scoped to a
project directory. It is catastrophic on yadm because the work-tree is
`$HOME`.

If you need to stash yadm work temporarily:

```bash
yadm stash push                        # tracked files only — SAFE
yadm stash push -- <specific-files>    # explicit paths — SAFE
# never:
# yadm stash push -u                   # DANGEROUS — pulls all of $HOME
# yadm stash push -a                   # DANGEROUS — pulls even ignored
```

## Safeguards applied

Per-repo git config on `~/.local/share/yadm/repo.git`:

```
gc.auto = 256                         # auto-gc when loose object count > 256
gc.autoPackLimit = 50                 # auto-gc when pack count > 50
gc.reflogExpire = 30.days             # prune reflog entries older than 30d
gc.reflogExpireUnreachable = 7.days   # unreachable entries older than 7d
```

Git's auto-gc will kick in on any `yadm add`/`commit`/`push` if the
thresholds are exceeded. If a `stash -u` accident occurs again, the
next normal operation will at least run gc automatically (though it
may still take a while to reclaim).

Baked into `.config/yadm/bootstrap` so every new-machine install gets
the same settings on first run.

## Consequences

### Advantages

- Future yadm gc runs trigger automatically on threshold breach
- Reflog prunes aggressively, minimising orphan-retention window
- `stash -u` remains available for normal repos; only yadm is affected
  (and we document the footgun in the ADR)

### Disadvantages

- Tighter reflog retention means less history for "undo" after mistakes
  — 7 days for unreachable commits, down from git's 90-day default
- Auto-gc may briefly block operations on a 16 GB RAM machine when it
  fires on large work (rare for dotfile repos)

## Related

- `docs/runbooks/gpg-key-recovery.md` — other yadm-specific gotchas
- ADR 001 (yadm choice) — frames why the work-tree is `$HOME`
