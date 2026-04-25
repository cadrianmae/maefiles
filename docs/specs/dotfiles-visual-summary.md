# Dotfiles Plan — At a Glance

Migration from GNU Stow → yadm + Bitwarden + pass, big-bang in 5 phases.

---

## The Stack

```mermaid
flowchart TD
  subgraph Sources["Source of truth"]
    BW[Bitwarden vault]
  end
  subgraph Local["Local caches"]
    PASS[pass store<br/>gpg-encrypted]
    AGENT[gpg-agent<br/>24h passphrase cache]
  end
  subgraph Tools["Consumers"]
    ENV[~/.env<br/>sourced by shell]
    SCRIPTS[bin/ scripts<br/>build-memory, convert-pdf, claude]
  end

  BW -->|bootstrap + TTL refresh| PASS
  PASS -->|pass show via agent| ENV
  PASS -->|pass show via agent| SCRIPTS
  AGENT -.caches passphrase.-> PASS
```

Three caches, three rhythms: **Bitwarden** (monthly), **pass** (7-30d TTL), **gpg-agent** (daily unlock).

---

## Key Decisions

| # | Decision | Why |
|---|---|---|
| 1 | **yadm** over chezmoi | Real files, git-native feel, low lock-in |
| 2 | **Bitwarden → pass → tools** tiered | Daily reads don't need bw unlock |
| 3 | **One GPG key** | Covers pass + yadm encrypt + git-crypt + commit signing |
| 4 | **esh** template engine | Maintained single-file shell script |
| 5 | **git-crypt** for encrypted docs | Transparent per-file, editable in place |
| 6 | **Manifest-driven template (B.1)** | Single source of truth; generated template gitignored |
| 7 | **Big-bang migration** in 5 phases | User doesn't rely on current setup heavily |
| 8 | **`bash <(curl …)` installer** | Inspectable, trace-logged, dry-run supported |

---

## Secrets Lifecycle

```mermaid
flowchart LR
  subgraph D["Daily"]
    SH[Open shell] --> W{Stale?}
    W -->|yes| WARN["[WARN] Run: yadm-refresh-secrets"]
    W -->|no| OK[normal]
    PASS1[pass show api/foo] --> AG{Agent cached?}
    AG -->|yes| INSTANT[instant]
    AG -->|no| PIN[pinentry once/day]
    PIN --> INSTANT
  end
  subgraph P["Periodic - 7-30d"]
    TIMER[systemd timer daily] --> STALE{Any stale?}
    STALE -->|no| QUIET[silent]
    STALE -->|yes| FLAG[set stale flag]
  end
  subgraph R["On demand"]
    REFRESH[yadm-refresh-secrets] --> UNLOCK[bw unlock]
    UNLOCK --> SYNC[bw get → pass insert]
    SYNC --> LOCK[bw lock]
  end
```

---

## Bootstrap Flow

```mermaid
flowchart TD
  START([bash curl...]) --> SHA[print script SHA256]
  SHA --> REVIEW{Review first?}
  REVIEW -->|yes default| LESS[less/bat]
  LESS --> CONFIRM
  REVIEW -->|no| CONFIRM{Proceed?}
  CONFIRM -->|n| ABORT([exit])
  CONFIRM -->|y| PM[detect PM]
  PM --> DEPS[install git gnupg pass yadm git-crypt bw esh]
  DEPS --> GPG{GPG key?}
  GPG -->|no| FAIL([abort - generate key first])
  GPG -->|yes| CLONE[yadm clone]
  CLONE --> UNLOCK[git-crypt unlock]
  UNLOCK --> BOOT[yadm bootstrap]
  BOOT --> DONE([complete])
```

---

## Migration Phases

```mermaid
stateDiagram-v2
  [*] --> P0
  P0: Phase 0 Prep<br/>30-60 min<br/>backup + GPG verify<br/>seed bw from .env.local
  P1: Phase 1 Scaffold<br/>30-60 min<br/>author files in /tmp
  P2: Phase 2 Adoption<br/>1-2 h<br/>un-symlink stow<br/>yadm init + add + push
  P3: Phase 3 Secrets<br/>30-60 min<br/>manifest + bootstrap<br/>verify pass render
  P4: Phase 4 Soak<br/>30 min + 24 h<br/>container test<br/>24h normal use
  DONE: Stow archived

  P0 --> P1 : zero-impact
  P1 --> P2 : still zero-impact
  P2 --> P3 : risk begins
  P3 --> P4
  P4 --> DONE
  P4 --> P3 : regression found
```

---

## Leakage Defences (Layered)

| # | Layer | Catches |
|---|---|---|
| 1 | Structural: rendered outputs gitignored | Accidental `yadm add` of rendered `.env` |
| 2 | Pre-commit: gitleaks + shellcheck | Entropy patterns, script bugs |
| 3 | Pre-push: gitleaks --staged | Bypassed pre-commits |
| 4 | yadm encrypt + git-crypt | SSH keys + secret docs never plaintext in repo |
| 5 | `yadm-verify-encryption` | Encryption gaps (files that should be encrypted but aren't) |
| 6 | `.gitconfig##template.esh` class branching | Wrong identity on commits |
| 7 | Explicit denylist | Files that must never leave the machine |

---

## Verification Strategy

```mermaid
flowchart LR
  DEV[Local dev] --> PC[pre-commit hook<br/>gitleaks + shellcheck + audit]
  PC --> PUSH[push]
  PUSH --> CI[GitHub Actions<br/>shellcheck + gitleaks + distro matrix]
  CI --> PR[PR merge]

  MANUAL[Manual] --> AUDIT[yadm-audit<br/>yadm-check-staleness<br/>yadm-verify-encryption]
  CONTAINER[Pre-release] --> PODMAN[podman test<br/>install.sh --dry-run<br/>across distros]
```

Five layers: pre-commit → on-demand → container → CI → manual post-migration checklist. Seven failure modes, each caught by at least one automated layer.

---

## Repo Scope

**Tracked:** `.zshrc` et al., `.config/{nvim,btop,cheat,laio,pomodoro,speech-dispatcher}`, `.claude/rules/`, `bin/`, `.config/yadm/`, `docs/`.

**Denylist:** `.claude.json`, `.env` (rendered), `.cache/`, `.local/share/`, language version managers (`.pyenv`, `.nvm`, `.cargo`, `.bun`), `.claude/projects/`.

**Encrypted:**
- `docs/secret/**` → git-crypt (editable, transparent)
- SSH keys, GPG backups → `yadm encrypt` (opaque archive)
- `.env` → gitignored, rendered from template

---

## Next Steps

1. Review full spec (see **Design Spec** tab)
2. Verify no surprises in the transcript (see **Transcript** tab)
3. Invoke `writing-plans` skill to produce a concrete implementation plan
4. Execute Phase 0 when ready
