# maenotes — Unified Obsidian Vault Design

- **Author:** cadrianmae
- **Date:** 2026-05-04
- **Status:** Design locked, pending implementation plan
- **Supersedes:**
  - `~/Documents/Computer Science TU856/` (academic vault, ~2,710 notes, git-tracked)
  - `~/Documents/The Nexus Vault/` (personal vault, ~923 notes, no git)
- **Related:**
  - `~/Documents/Computer Science TU856/PKM Methods/` — methodology research (carried forward into `60 library/vault-studies/`)
  - `~/Documents/Computer Science TU856/CLAUDE.md` — existing vault architecture guidance (informs design)
  - `~/maefiles/` — naming convention precedent (`mae*` personal namespace)

## 1. Context

Mae maintains two Obsidian vaults that have diverged in shape and discipline:

- **Computer Science TU856** — well-structured (ISO date prefixes, JD-style numeric folder prefixes inside Year 4, git-tracked, has `CLAUDE.md`/`WORKFLOW.md`/`PLUGINS.md`). Plugins lean modern (Bases over Dataview). Active.
- **The Nexus Vault** — fragmented (60+ root-level pollution, 7× `Untitled N.md`, no git, two empty `daily/` folders due to case collision, mixed casing). Plugins lean older (Dataview, Periodic Notes, Readwise). Active but cluttered.

Both vaults overlap (TU856 fragments leaked into Nexus; both have `Extracurricular/`, both have shared templates with slight drift). Migration to a single vault is the only way to eliminate fragmentation rather than reshuffle it.

### Pain / motivation

**Framing:** Mae is neurodivergent. The fragmented-capture-no-processing pattern is a *symptom* of executive dysfunction, not a workflow preference. The vault is therefore designed as an **executive-function prosthetic** — its core job is to compensate for unreliable working memory, decision fatigue, and non-linear engagement.

This means the vault must:

- **Remember for Mae**, so she doesn't have to (semantic search + Claude chat as the primary access path, not folder navigation)
- **Never moralise non-engagement** (no inbox-zero, no missed-day guilt, no "you should be using this" plugins)
- **Reduce decisions at capture** (no filing choice — every capture lands in `10 inbox/` with an auto-generated timestamp filename)
- **Surface relevance over demanding recall** (AI brings relevant past notes up automatically when Mae works on adjacent things)
- **Forgive non-linearity** (the stream is the artifact, captures earn promotion through *use*, not *review*)

Specific pain points:

1. **Findability** — knowledge exists across both vaults but cannot be located when needed
2. **Outdated structure** — folders reflect who Mae was earlier in the degree, not current life shape
3. **Capture friction + processing chasm** — Mae captures ad-hoc, unstructured, in volume, and rarely revisits or processes captures. This is exec-function symptom, not character flaw. The existing Fleeting Notes plugin requires a paid external service Mae will not adopt. The new design accepts pile-up and makes captures useful *unprocessed* (see §6.0a).
4. **Cognitive load** — managing two vaults plus deciding *which* vault for *what* is itself a tax
5. **Recall reliance** — current vault assumes Mae remembers what she wrote and where. neurodivergent-affected working memory makes this unreliable. Vault must do the remembering.
6. **No public surface** — work that could be shared (each year's CS notes, vault-methodology research) has no path to publication
7. **Workflow itself is ad-hoc** — Mae cannot describe an "ideal day"; the design accommodates emergent rather than predetermined use

### Goals (in priority order)

1. **Consolidation** — one knowledge hub for all aspects of life
2. **Organisational refresh** — replace outdated structure of both vaults
3. **Frictionless fleeting capture** — free, self-hostable, phone-capable, ≤ 2 taps from idle
4. **Better discovery and linking** — surface forgotten knowledge, support the one stable use pattern (mid-day "reference + build")
5. **Reduced cognitive load** — fewer recurring decisions, one rule per situation
6. **Learning in public** — selected areas (CS years, vault-studies) become public git repos
7. **Per-aspect git repos** — independent history and visibility per knowledge area

### Non-goals

- Prescribed daily/weekly ritual (workflow emerges from use; templates exist but rituals are not enforced)
- Replacing Obsidian Sync immediately (Syncthing migration is a separate, deferred project)
- Configuring Quartz publishing now (deferred; design stays publish-tool-agnostic)
- Wholesale adoption of any single PKM methodology (Zettelkasten, PARA, GTD) — take what works, leave what doesn't
- Migrating Year 1-3 to public repos on a schedule (cleanup-on-demand only; some may never flip public)
- Eliminating Obsidian dependence (the vault is Obsidian-shaped; portability via plain markdown is a side-effect, not a requirement)

## 2. Decision summary

| Decision | Choice | Why |
|---|---|---|
| Vault name | **maenotes** | Follows `maefiles` convention; anti-naming (name = identity + thing) |
| Vault count | **One unified vault** | Two vaults preserve the fragmentation pain; focus modes solved differently |
| Top-level skeleton | **Johnny Decimal areas (00-99 in tens-blocks)** | Promotes Year 4's existing numeric-prefix scheme to vault root |
| Repo strategy | **Pattern X — nested git repos in vault** | Phone sync via single tree; symlink-based Pattern Y breaks Android sync |
| Forge during migration | **GitHub only** | Codeberg multi-remote migration deferred to summer project; vault migration ships on familiar forge |
| Vault root git status | **Not a git repo** | Sync (Obsidian Sync now, Syncthing future) replicates the tree; per-area repos handle history |
| Visibility default | **Option C — private; flip public per repo after cleanup** | Removes recurring decision; respects unpublishability asymmetry |
| Sync mechanism | **Obsidian Sync (current); Syncthing (future)** | Vault design is sync-mechanism-agnostic; defer migration |
| Phone capture (primary) | **Memos PWA → sync script → `10 inbox/<timestamp>.md`** | Self-hosted FleetingNotes-equivalent (FOSS, AGPL, no paywall). Polished card-style capture UX. Offline-buffered. |
| Phone capture (fallback) | **Obsidian Mobile share-sheet → new note in `10 inbox/`** | Always-works backstop when Memos infra is unavailable (e.g., laptop off and offline buffer flushed). |
| Structured Claude vault access | **`mcp-obsidian` MCP server** + Local REST API plugin | Backlinks / tags / frontmatter via Obsidian's index, not raw FS regex. Wireable into Claude Code and Claude Desktop. |
| Inbox model | **Per-note files with auto-generated timestamp filenames** | Matches "Keep / Apple Notes / FleetingNotes" mental model; each capture is wikilinkable, promotable, individually indexed. Decision-at-capture eliminated by auto-naming. |
| Reading pipeline | **Readwise (kept; overhaul deferred)** | Existing setup is bloated/underused; tool is valued, configuration needs rework |
| Publishing tool | **Quartz (deferred)** | Preserves wikilinks; configuration deferred until first cleanup-flip |
| Query/dashboard layer | **Bases (replaces Dataview)** | Modern, Obsidian-native; CS vault already uses it |
| Claude integration | **Copilot for Obsidian (logancyang)** + Claude Code at FS level | First-class Claude vault chat; AGPL; bring-your-own-key; replaces Smart Connections' chat UI |
| Semantic search | **Copilot's vector index** (Ollama-hosted) + Obsidian core search for exact-phrase fallback | neurodivergent recall prosthetic — surfacing without remembering. Quick Switcher++ handles navigation; Omnisearch deferred (redundant with Copilot semantic). |
| Navigation | **Quick Switcher++** (darlal) | Modal, keyboard-first; searches filenames, headings, aliases, tags, commands. Fast — uses Obsidian's index. |
| Daily/weekly notes | **Optional only — no plugin, no enforced cadence** | Maintenance creates overhead Mae has explicitly rejected; per-note inbox captures absorb the daily-journal role |
| Focus modes | **Three Bases dashboards + saved Workspaces** | Studies / Personal / Everything — switchable from `00 meta/` |
| Migration direction | **CS vault skeleton, Nexus content imports in** | CS vault is more disciplined and git-tracked; reversing the direction would lose Year 4 structure |

## 3. Top-level structure

```
~/Documents/MaeNotes/                    ← sync folder, NOT a git repo
├── .stignore                            ← Syncthing ignores .git internals (when migrated)
├── 00 meta/                             ← vault rules, templates, dashboards, PKM research
├── 10 inbox/                            ← per-capture files (`<YYYY-MM-DD-HHMM>.md`); weekly/, daily/ only if/when manually created
├── 20 studies/
│   ├── cs-year-1/  [.git]               ← independent repo, default private
│   ├── cs-year-2/  [.git]
│   ├── cs-year-3/  [.git]
│   └── cs-year-4/  [.git]               ← active during transition; flips public post-FYP
├── 30 projects/
│   ├── snappy-fyp-notes/  [.git]
│   └── sol-notes/  [.git]
├── 40 self/                             ← plain folder, private always (health, ND, identity)
├── 50 people/                           ← plain folder, private always
├── 60 library/
│   ├── readwise/                        ← Readwise plugin sync target
│   ├── literature/                      ← formal literature notes
│   └── vault-studies/  [.git]           ← public-leaning (research on Nicole van der Hoeven et al.)
├── 70 life admin/                       ← plain folder, private (home, finance, appointments)
├── 80 creative/                         ← cosplay, music, hobbies; per-project repos optional
└── 90 archive/                          ← plain folder; periodically pruned
```

### 3.1 Area allocations (tens-blocks)

| Range | Area | Repo? | Visibility |
|---|---|---|---|
| 00-09 | Meta | no | n/a (private) |
| 10-19 | Inbox | no | private |
| 20-29 | Studies | yes (per year) | private → public per cleanup |
| 30-39 | Projects | yes (per project) | private → public per project |
| 40-49 | Self | no | private always |
| 50-59 | People | no | private always |
| 60-69 | Library | yes (vault-studies only initially) | mixed |
| 70-79 | Life admin | no | private |
| 80-89 | Creative | optional | per-project decision |
| 90-99 | Archive | no | private |

### 3.2 Inside each tens-block

Existing Year 4 numeric subdivision pattern carries forward. Example for `21 computer science/cs-year-4/`:

```
21 computer science/cs-year-4/
├── 10 lecture notes/
├── 11 lab notes/
├── 12 meeting notes/
├── 13 knowledge/
├── 14 final year project/
├── 15 reference/
├── 16 logs/
├── 17 tracker/
├── 20 modules/                          ← Brightspace-synced; READ-ONLY
├── 21 module descriptors/
├── 30 exam papers/
├── 31 exam answers/
├── 32 revision/
├── 40 attachments/
├── 41 quick access/
└── 50 archive/
```

This pattern is **already proven** in the CS vault — design simply preserves it.

## 4. Repository strategy (Pattern X)

### 4.1 Mechanics

- Vault root is a plain folder, not a git repo
- Selected sub-areas are **independent** git repos (no submodules, no subtrees, no parent repo)
- Each repo starts on **GitHub only**; Codeberg multi-remote mirroring is deferred to the summer project (see §4.4)
- Repos use `maenotes-<area-slug>` prefix on GitHub for traceability:
  - `~/Documents/MaeNotes/21 computer science/cs-year-1/` → `github.com/cadrianmae/cs-year-1`
  - `~/Documents/MaeNotes/30 projects/snappy-fyp-notes/` → `github.com/cadrianmae/snappy-fyp-notes` (project repos may keep their original name; no prefix)

### 4.2 Sync compatibility

- **Obsidian Sync (current):** indifferent to nested `.git/` directories; syncs all working-tree files
- **Syncthing (future):** `.stignore` at vault root excludes `.git/objects/`, `.git/index.lock`, `.git/logs/` and similar internals to avoid sync churn

### 4.3 Cross-repo wikilinks

Within Obsidian, wikilinks resolve across repo boundaries (Obsidian sees one tree). When a repo is cloned standalone, cross-repo links become dangling.

**Discipline:**
- Within a repo, prefer internal links
- Across repos, use a `> [!note] See also (in main vault): <full-path>` callout that degrades gracefully to plain text on standalone clones
- Cleanup pass before any public flip resolves dangling cross-repo references

### 4.4 Forge strategy: GitHub now, Codeberg multi-remote (summer project)

Decided in side-tangent investigation (`ctx-child-to-parent-github-migration-options`); migration itself is deferred:

- **GitHub** is the sole forge for vault repos during migration. Familiar, working, no setup overhead while migration is in progress.
- **Codeberg multi-remote** (codeberg.org primary + GitHub mirror via single multi-remote `origin`) is the **target end state** — non-profit, EU-hosted, ethics + sovereignty + redundancy. Migration deferred to summer project (see §16).
- **`claude-marketplace`** stays GitHub-primary forever (audience discoverability for Claude Code plugin users) — the lone exception even after the Codeberg migration.
- **Forgejo self-host** = future option, on the VPS, after Codeberg trial.

**Target multi-remote setup per repo (summer project):**
```bash
git remote set-url origin https://codeberg.org/cadrianmae/cs-year-1
git remote set-url --add --push origin https://codeberg.org/cadrianmae/cs-year-1
git remote set-url --add --push origin https://github.com/cadrianmae/cs-year-1
```

After that, `git push` pushes to both remotes via a single `origin`. Pulls come from Codeberg.

The `vault-status` helper script (deferred to implementation) can drive `git push --all` across nested repos once multi-remote is configured.

**Why deferred:** running the Codeberg migration concurrently with vault migration doubles the in-flight cognitive load. Vault migration ships GitHub-only; the summer project flips remotes in one focused pass once vault state is stable.

### 4.5 Commit cadence

No enforced rhythm. Recommended: end-of-session commit per touched repo. Public repos pushed immediately on commit; private repos pushed on a comfortable cadence (weekly is fine).

A helper script `vault-status` (~10 lines of bash) walks every nested `.git` and reports `git status -s`, surfacing what's dirty across repos. Spec'd in implementation plan, not now.

## 5. Visibility model

### 5.1 Rule (single rule, no exceptions)

**Every new repo starts private.** Public is an explicit, per-repo decision after a cleanup pass.

### 5.2 Rationale

- Once published, content is cached, archived, forkable — unpublishability is asymmetric
- Removes the "is this OK to be seen yet?" decision at commit time (cognitive load goal)
- Year 1-3 contain content written assuming privacy (frustration vents, supervisor commentary, grade speculation, half-thoughts about lecturers); defaulting public would force retroactive cleanup before any commit could land

### 5.3 What this means in practice

| Repo | Initial state | Likely outcome |
|---|---|---|
| `computer-science` | private | maybe never flipped — that's fine, it's a working archive |
| (merged into `computer-science`) | private | maybe never flipped |
| (merged into `computer-science`) | private | maybe never flipped |
| (merged into `computer-science`) | private | flip public post-FYP after cleanup pass |
| `snappy-fyp-notes` | private | flip when project itself goes public |
| `sol-notes` | private | flip when ready |
| `vault-studies` | private | flip after first 3-5 case studies populated |

### 5.4 Learning in public — adjusted definition

Learning in public happens with a **delay**. Flow:

1. Capture freely (private)
2. Cleanup pass when motivated (no schedule)
3. Flip public + push to Quartz site
4. Public surface lags reality by weeks/months — honest about retrospective understanding

## 6. Capture flow

### 6.0 Philosophy: no enforced rituals

Mae has explicitly rejected the maintenance burden of daily/weekly notes — both the plugin-driven kind and the manual habit. The vault must not imply "you should be doing this."

**Design response:**

- **`10 inbox/` is the only required folder.** Every capture lands here as a per-note timestamped file. Absorbs the journal/daily-log role. No daily-note creation. No weekly-note creation. No plugin commands implying you should.
- **Periodic Notes plugin is NOT installed.** Its presence creates an "I should be using this" tax. Without it, daily/weekly notes become an active opt-in, not a passive expectation.
- **Templates for weekly/monthly reviews exist** (in `00 meta/templates/`) for when (if ever) Mae wants to write one. They sit dormant until summoned. They never nag.
- **Bases dashboards never query "today's daily note"** — they query content that exists, not content that's expected to exist.

### 6.0a Principle: the stream is the artifact

Captures pile up. They don't get processed. Mae has explicitly named this as how it actually works. The design must accommodate this rather than fight it.

**The rule:** an unprocessed capture is *not* a debt. It's the artifact. It has lasting value because:

- It is **searchable** — Obsidian core full-text search + Copilot semantic index cover every capture file in `10 inbox/` and any year-archived subfolders
- It is **timestamped** — "what was I thinking around the time of X" is answerable without any organising work
- It is **surfaceable** — Copilot's semantic index brings related old captures up when you work on adjacent things later. Resurfacing happens organically, not on a schedule.
- It is **never lost** — capture commits to disk; sync replicates; nothing demands you act on it

**What this means in practice:**

- "Inbox Zero" is not a goal. There is no inbox-zero ritual.
- "Processing" is opt-in, sporadic, and guilt-free. If a capture turns into something, it does. If it doesn't, it sits as part of the stream.
- The vault never displays "X unprocessed captures" or any guilt-inducing metric.
- Captures earn promotion to permanent notes by being *referenced in real work*, not by scheduled review.

This aligns with Andy Matuschak's observation that most fleeting notes stay fleeting forever, and that's correct — only the ones that prove themselves through repeated relevance earn evergreen status.

### 6.1 Inbox model: per-note files with auto-generated timestamps

`10 inbox/<YYYY-MM-DD-HHMM>.md` — every capture creates its own file. Filename is auto-generated from timestamp; Mae never names a capture at capture time.

```
~/Documents/MaeNotes/10 inbox/
├── 2026-05-04-1432.md
├── 2026-05-04-1501.md
├── 2026-05-04-1547.md
├── 2026-05-05-0915.md
└── ...
```

Collisions (multiple captures within the same minute) get a `-2`, `-3` suffix. Otherwise the timestamp is the filename forever — and that's fine.

**Why per-note files (not a single `inbox.md`):**

- **Matches your "Keep / Apple Notes / FleetingNotes" mental model** — discrete notes, browseable as cards in Obsidian
- **Promotion is `mv`** — when a capture earns its way into a permanent note, just rename and move; Obsidian auto-updates wikilinks pointing at it
- **Each capture is a graph node** — wikilinkable, individually indexed by Copilot for semantic search
- **Mobile-native** — Obsidian Mobile's share-sheet creates a new note by default; per-note model works *with* Obsidian's grain
- **Loss tolerance** — a corrupted save affects one capture, not your entire stream

**The decision-at-capture problem (and why this still solves it):** filing decision is replaced by *no decision at all*. Filename is computed; folder is fixed; content is whatever you typed. One motion, no choices.

Format:
```markdown
## 2026-05-04 14:32
quick thought goes here

## 2026-05-04 15:01
another thought, possibly with [[wikilinks]] if convenient
```

### 6.2 Capture mechanisms

All paths land a new file in `10 inbox/` with an auto-generated timestamp filename.

| Source | Mechanism | Latency |
|---|---|---|
| **Phone (primary)** | **Memos PWA** — card-style UI; sync script ingests captures into `10 inbox/<timestamp>.md` (see §6.4) | 1 tap |
| **Phone (fallback)** | Obsidian Mobile share-sheet → "New note in Inbox" — native per-note behaviour | 2 taps |
| Desktop terminal | `qcap "thought"` shell function — creates `10 inbox/$(date +%Y-%m-%d-%H%M).md` | 1 keystroke + thought |
| Desktop browser | Bookmarklet → `qcap`; Readwise Reader extension for highlight-driven article capture | 1 click |
| Desktop in Obsidian | QuickAdd command `C — Capture` — creates new note in `10 inbox/` from template | 1 keystroke |
| KDE Connect | "Send text" → triggers `qcap` on desktop | desktop side automated |

The `qcap` shell function (~10 lines of bash) lives in `~/bin/qcap`. Spec at implementation time.

### 6.3 Processing (or not)

There is no expected processing cadence. See §6.0a.

If a capture is ever revisited, three things can happen:

1. **Promotion** — `mv` the capture file from `10 inbox/` to its real home (e.g., `21 computer science/cs-year-4/13 knowledge/embedding-models.md`). Rename optional. Obsidian auto-updates any wikilinks pointing at it. This is the lowest-friction promotion possible.
2. **Linking** — add wikilinks inside the capture file connecting it to existing notes. Capture itself stays in `10 inbox/`.
3. **Nothing** — most common. The capture stays in the stream. Still searchable, still semantically surfaceable, still useful.

Deletion is rare — only for genuinely embarrassing captures or accidentally-pasted credentials. Otherwise, captures stay forever.

### 6.4 Memos as primary phone capture surface

**Memos** (`usememos/memos`, AGPL, ~37k★) is the self-hosted, FOSS, FleetingNotes-equivalent capture surface. It addresses Mae's stated frustration with FleetingNotes: nailed UX, paywalled multi-device sync.

**Why Memos:**

- Card-style mobile UI matching the FleetingNotes / Apple Notes / Keep mental model
- AGPL — fully open source, inspectable, customisable
- Self-hosted Docker container, ~50MB RAM, trivial to run anywhere
- Web app installable as PWA on phone (offline-capable, app-shaped icon)
- HTTP API for integration
- Active maintenance, large community

**Architecture:**

```
┌─────────────────┐
│  Phone (PWA)    │  Memos PWA installed; offline-buffer captures
└────────┬────────┘
         │ HTTPS
         ▼
┌─────────────────┐
│  Memos server   │  Docker container; persistent SQLite DB
│  (Hetzner VPS)  │  provisioning post-FYP — see §14
└────────┬────────┘
         │ Memos API (GET /api/memos)
         ▼
┌─────────────────┐
│  Sync script    │  cron / systemd timer; pulls new memos
│  (on desktop)   │  → `10 inbox/<timestamp>.md`
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  maenotes vault │  per-note files; Obsidian Sync replicates
└─────────────────┘
```

**Sync script behaviour:**

1. Polls Memos API on a schedule (every 5 min on desktop; manual trigger via `qsync`)
2. For each new memo not yet in the vault, creates `10 inbox/<memo-created-timestamp>.md`
3. Marks memos as "synced" in Memos (via tag or memo update) to avoid re-processing
4. Logs failures; doesn't lose captures

**Hosting decision: VPS (post-FYP)**

Memos hosting is **part of a broader self-hosting initiative** (see ctx-child-to-parent-github-migration-options for full architecture). Provisional plan:

- **Target VPS:** Hetzner Cloud CAX21 Helsinki (ARM) — €5.39/mo, 4 vCPU / 8 GB / 80 GB
- **Rationale:** Headroom to stack Memos + Forgejo + Syncthing + Caddy + future services on one box. CX22 Intel (€3.99/mo) viable as tighter budget alternative.
- **Architecture:** Plain Docker Compose under `~/homeops/` repo; Caddy reverse proxy (auto-HTTPS); Tailscale from day one; all volumes under `/srv/<service>/` for trivial rsync-migration to future homelab.
- **Provisioning:** Deferred until post-FYP. Vault design itself is hosting-agnostic — Memos can also run locally on laptop or Raspberry Pi if the VPS plan slips.

The maenotes vault design does not depend on Memos hosting being solved. The fallback (Obsidian Mobile share-sheet) works always; Memos-via-VPS is the *polished* primary capture path that arrives when the VPS does.

**Failure modes & mitigations:**

| Failure | Effect | Mitigation |
|---|---|---|
| Memos server down | Phone can't reach server, but PWA buffers captures locally | Memos PWA flushes buffer on reconnect; nothing lost |
| Phone offline | Memos PWA caches in IndexedDB | Syncs when online |
| Sync script crashes | Captures stay in Memos (not in vault) | Script is idempotent; next run catches up |
| Both paths fail | Use Obsidian Mobile fallback | Always-on backstop via Obsidian Sync |

**Setup tasks (Phase 1 of migration):**

- Choose host (laptop / Pi / VPS) — see §14 for the deferred decision
- Deploy Memos via Docker
- Configure auth (single-user, generate API token)
- Install PWA on phone
- Write sync script in `~/bin/qsync` or similar
- Add systemd timer or cron for periodic sync
- Test end-to-end (capture on phone → appears in vault within 5 min)

### 6.5 Rotation (when the folder feels crowded)

Per-note files don't suffer the "single huge file" problem, so rotation is largely cosmetic. If the inbox folder feels visually crowded, archive by year:

```bash
mkdir -p "10 inbox/2026"
mv "10 inbox/2026-"*.md "10 inbox/2026/"
```

This groups older captures into a year subfolder. They remain searchable. Copilot continues to index them. New year's captures land at the top level again.

This is opt-in and never required. Some people will leave 5,000 timestamped files at the top level forever — that's also fine. Modern filesystems and Obsidian both handle it.

## 7. AI integration and semantic search

This is **load-bearing for the neurodivergent recall problem.** Folders file; AI finds. The vault treats AI as a primary access path — the executive-function prosthetic from §1 — not optional polish.

### 7.1 Tool stack

| Layer | Tool | Role |
|---|---|---|
| Vault chat | **Copilot for Obsidian** (logancyang, AGPL) | Ask questions; Claude synthesises answers grounded in vault content |
| Semantic search | Copilot's vector index | "Find the thing I half-remember writing" — vector search by meaning |
| Full-text search | **Obsidian core search** (Cmd+Shift+F) | When you do remember exact phrases. Omnisearch deferred — redundant with Copilot semantic + core search covers exact-match needs. |
| Navigation | **Quick Switcher++** (darlal) | Filenames + headings + tags + commands. Fast modal navigation. |
| FS-level agent | **Claude Code** | Multi-file edits, restructures, migrations, generation |
| Active recall | Spaced Repetition plugin | Anki for things explicitly elevated for retention |

These layers complement, not duplicate:

- **Copilot Smart Chat** when you have a question and want an answer
- **Semantic search** when you have a fuzzy concept and need to locate notes
- **Obsidian core search** (Cmd+Shift+F) when you remember exact phrases
- **Quick Switcher++** for keyboard-first navigation (filenames, headings, commands)
- **Claude Code** when you want to edit/restructure/create across many files
- **Anki** for spaced reinforcement of things you've actively chosen to retain

### 7.2 Why Copilot for Obsidian over Smart Connections

Mae has used Smart Connections and named real grievances: the chat UI is opinionated; the ecosystem leans toward the paid Smart Connect SaaS; the embedding pipeline is hard to inspect or customise. The plugin is technically MIT, but the experience drifts toward closed.

Copilot for Obsidian:

- **AGPL** — copyleft open source; everything inspectable
- **Bring-your-own-API-key** — Claude API direct; Voyage / Cohere / OpenAI / local Ollama for embeddings
- **No vendor SaaS layer** — embeddings stored as JSON in the vault
- **Less opinionated UX** — sidebar chat with composable prompts; vault context is configurable, not predetermined
- **Solves the same surfacing job** — vector index for semantic recall

If a specific Smart Connections feature is missed in practice, **both plugins can run alongside** without conflict — Copilot for Claude chat and primary surfacing; Smart Connections for any feature it uniquely handles. Fallback option, not first choice.

### 7.3 Embedding model (deferred decision)

Configuration deferred to post-migration. Candidates:

- **Voyage-3** (Anthropic-affiliated, low cost, high quality) — strong default for English
- **OpenAI text-embedding-3-large** — gold standard for English; ~$0.13 per 1M tokens
- **Local via Ollama (`nomic-embed-text` / `mxbai-embed-large`)** — zero cost, slower indexing, lower quality but acceptable

For Mae's vault scale (~3,500 notes after migration, ~10MB markdown), full embedding is one-time ~$0.10-0.50 (cloud) or ~30 minutes (local). Re-embedding on changes is incremental and trivial.

### 7.4 Claude Code as first-class FS integration

Claude Code complements Copilot at the file-system layer, not via the plugin sidebar:

- **Copilot** — interactive vault chat ("answer me from notes")
- **Claude Code** — agentic editing across files ("rewrite, refactor, migrate, generate")

They don't conflict. They run in different surfaces. Copilot inside Obsidian; Claude Code in the terminal. This spec was written using Claude Code on Mae's vault.

### 7.5 MCP server: structured Obsidian access for Claude

For richer Claude integration than raw filesystem reads, install **`mcp-obsidian`** (MarkusPfundstein, https://github.com/MarkusPfundstein/mcp-obsidian) as an MCP server. Wireable into both Claude Code and Claude Desktop.

**Stack:**

```
Claude Code / Claude Desktop
        ↓ MCP protocol
   mcp-obsidian server
        ↓ HTTP + token
Obsidian Local REST API plugin
        ↓
   Obsidian vault state
```

**What it adds beyond raw FS:**

- Native backlinks (what links here?) via Obsidian's own index
- Structured tag operations
- Frontmatter manipulation through API (no fragile YAML hand-editing)
- Renames + moves that preserve wikilinks (Obsidian handles relink)
- Use Obsidian's search ranking instead of grep

**Setup (deferred — install during Phase 1):**

1. Install **Local REST API** plugin in Obsidian; generate a token
2. Install `mcp-obsidian` server: `uvx mcp-obsidian` or `npx`-equivalent per upstream README
3. Register in Claude Code: `claude mcp add obsidian` with the appropriate command
4. (Optional) Register in Claude Desktop via `~/.config/Claude/claude_desktop_config.json`

**Note on the official Obsidian CLI:** the `obsidian` binary's built-in CLI is limited (open vault, open URI). Mae uses it for vault-launching and URI handoff; richer FS operations go through Claude Code or `mcp-obsidian`. Third-party CLIs (e.g. `obsidian-cli` by Yannick Loiseau) are not in use.

### 7.6 Privacy

- API calls to Anthropic — standard commercial API privacy (not used for training per Anthropic policy on commercial API)
- Embeddings stored locally in vault JSON, never in a third-party service
- `40 self/`, `50 people/`, `70 life admin/` content can be excluded from Copilot's index via plugin configuration — recommended for sensitive material
- Readwise still operates as a separate paid service for highlight harvesting; that is unchanged by this section

### 7.7 neurodivergent-specific design rationale

The choices above directly address pain points in §1:

- **Recall reliance** → Copilot answers from notes you forgot you wrote; semantic search surfaces by meaning
- **Capture-without-processing** → unprocessed captures are still queryable via Copilot, so processing is not a prerequisite for value
- **Cognitive load** → "ask the vault" is one access path that replaces "remember which folder, then navigate, then skim"
- **Findability** → semantic + full-text + Claude Code's grep all available; one of them will find it

This is the section that makes the rest of the design *actually work* for a neurodivergent brain. The folder structure, the JD skeleton, the focus modes — those are organisational scaffolding. AI is what makes the vault *findable* without demanding executive function Mae cannot reliably summon.

## 8. Reading pipeline

**Readwise is kept.** The current setup is bloated and underused, but the tool itself earns its keep — Readwise's strength (highlight harvesting + spaced-resurfacing daily review) is not replicated by free alternatives. The work is configuration, not replacement.

### 8.1 Tool stack

- **Readwise Reader** — read articles, books, PDFs; highlight inline
- **Readwise Official plugin** (`readwise-official`) — syncs highlights into vault
- **Drop zone:** `60 library/readwise/` (per-source files, the plugin default)
- **Resurfacing:** daily review surfaces past highlights — feeds back into vault discovery

### 8.2 Overhaul scope (deferred to post-migration)

The current Readwise setup needs rework. Deferred items, to address after vault migration completes:

- **Sync target audit** — verify highlights land in one consistent location (current: scattered across vaults)
- **Template overhaul** — Readwise highlight template should match vault literature-note conventions; current template is plugin-default
- **Tag taxonomy reset** — current Readwise tags don't align with vault's tag conventions (none exist yet, but design should anticipate)
- **Reading habit** — Readwise Reader use is sporadic; the technical tooling can't fix this, but a cleaner setup removes one excuse
- **Folder organisation** — single flat `60 library/readwise/` vs per-source-type subfolders (articles, books, tweets); decide post-migration

### 8.3 Why not Obsidian Web Clipper instead

- Web Clipper saves a snapshot; Readwise harvests *highlights* + resurfaces them. Different jobs.
- Mae values the resurfacing flow specifically — that's what makes reading "stick"
- Web Clipper can co-exist later if a snapshot-style use case emerges, but is not adopted now

## 9. Plugin reconciliation

Unified vault adopts CS-vault-leaning plugin set with selected Nexus additions and one new plugin.

### 9.1 Adopt from CS vault

- **Bases** — modern Obsidian-native query/dashboard layer; replaces Dataview
- Templater, QuickAdd, Obsidian Linter, Excalidraw
- vimrc-support, terminal, advanced-new-file, recent-files
- Spaced Repetition (Anki integration — keep for retention practice)
- Folder Focus Mode (per-area focus when needed)
- Homepage (configures startup view)

### 9.2 Adopt from Nexus vault

- **Readwise Official** — kept; setup overhaul deferred (see §8)
- ~~Aloud TTS~~ — **NOT adopted.** Mae prefers external piper-based TTS workflow over the in-Obsidian plugin.

### 9.2a Explicitly NOT installed

- **Periodic Notes** — *not installed.* Its presence creates an implicit "you should be using daily/weekly notes" tax. Mae has rejected this maintenance burden. Daily/weekly notes are opt-in via manual file creation when desired (templates in `00 meta/`). See §6.0.
- **Core "Daily Notes" plugin** — also disabled, same reason

### 9.3 Add new

- **Copilot for Obsidian** (logancyang/obsidian-copilot, AGPL) — Claude chat over vault + semantic search via embeddings. Replaces Smart Connections. See §7 for rationale.
- **Workspaces** (core, enable saved layouts) — for focus-mode pane configurations
- **Quick Switcher++** (darlal) — modal navigation: filenames + headings + tags + commands. Replaces Obsidian's default Quick Switcher.
- ~~Omnisearch~~ — **deferred.** Copilot semantic search + Obsidian core full-text + Claude Code's `search_vault_smart` provide redundant discovery coverage; Omnisearch would mostly duplicate. Reconsider only if a specific gap emerges.

### 9.4 Drop

- **Dataview** — replaced by Bases
- **Smart Connections** — replaced by Copilot for Obsidian. Real grievances: opinionated chat UI, ecosystem leans toward paid Smart Connect SaaS, embedding pipeline is hard to inspect/customise

### 9.5 Migration concern

Any Dataview queries in Nexus content must be migrated to Bases during Phase 3. Audit at start of phase.

## 10. Focus modes

Three Bases dashboards in `00 meta/`, switchable via Homepage plugin:

- **`Home — Studies`** — filters to areas 20, 60, 10
- **`Home — Personal`** — filters to areas 30, 40, 50, 70, 80, 10
- **`Home — Everything`** — master compass, no filters

Combined with Workspaces plugin for per-mode pane layouts (sidebar pins, default open notes, ribbon icons).

Switching is one click. No vault restart, no plugin reload.

## 11. Templates

Inherits from CS vault `system/templates/` and merges in Nexus-only templates.

### 11.1 Carried forward from either vault (existing, no changes)

From CS vault:

- `+log.md` (interstitial logging)
- `+add drawing.md`, `+page break.md` (formatting helpers)
- `fleeting.md` (Templater template: tags `[fleeting]`, stamps date frontmatter, wraps payload in a `> [!QUOTE] Original Capture` callout under a `# References` heading. Distinct role from per-note inbox files — this is for *framed* captures where attribution matters: someone else's words, a quote, a snippet preserved verbatim with provenance. Per-note inbox handles raw thought-capture; this handles citation-shaped capture.)
- `permanent-note.md` (Zettelkasten permanent / evergreen)
- `meeting notes.md`, `person.md`, `book.md`

From Nexus vault:

- `recipe.md` (low-volume but useful)

### 11.2 Resolve duplicates

Where CS and Nexus have variants of the same template (e.g., `note.md` vs `permanent-note.md`):

- Keep the more specific name
- Diff content; merge useful additions
- Document choices in `00 meta/templates/CHANGELOG.md`

### 11.3 New templates to add

All templates below are **opt-in**. They sit dormant unless explicitly invoked via Templater/QuickAdd. None are tied to a periodic schedule.

- `literature-note.md` — Zettelkasten literature (Mae's existing PKM Methods doc has the schema)
- `project-moc.md` — project index template (status, location-of-real-repo, log)
- `weekly-review.md` — *optional* weekly-review template; manually invoked when wanted, never on schedule. File goes to `10 inbox/weekly/<YYYY-WNN>.md` only when Mae creates it.
- `daily-log.md` — *optional* daily-log template; same opt-in semantics as weekly. Most likely unused — per-note inbox captures already cover the journaling role.
- `vault-study.md` — case study on other vaults (Nicole van der Hoeven et al.)
- `readwise-highlight.md` — overhauled Readwise highlight template (replaces plugin default; aligned with vault literature-note conventions)

## 12. Migration plan (high-level)

Detailed steps go into the implementation plan (next step). Three phases.

### Phase 1: Scaffold new vault
- Create `~/Documents/MaeNotes/`
- Build JD top-level skeleton (empty area folders + `00 meta/`)
- Migrate `system/templates/` from CS vault; resolve template duplicates
- Configure plugins (CS-leaning baseline + Readwise Official, Quick Switcher++); explicitly disable Periodic Notes, core Daily Notes, Aloud TTS
- Build three Home dashboards (Studies, Personal, Everything) via Bases
- Save Workspaces for each focus mode
- Write `qcap` shell function (creates per-note timestamped file in `10 inbox/`) and capture-note template
- Test on one device before content migration

### Phase 2: Migrate CS vault contents
- Move Year 4 (active) into `21 computer science/cs-year-4/` and initialise as nested git repo
- Move Year 1-3 each into `21 computer science/cs-year-N/` and initialise each as nested git repo
- Repoint Brightspace `modules/` sync target paths
- Move `PKM Methods/` → `60 library/vault-studies/` (initialise as nested git repo)
- Migrate root-level `system/`, `fleeting/`, and other top-level files
- Triage CS vault root pollution (PDFs, audit docs, princess-bubblegum-cosplay-guide.md → `80 creative/`)
- Verify Brightspace sync works post-migration with one module before declaring success

### Phase 3: Migrate Nexus vault contents
- Triage 60+ root-level Nexus files (file or delete; many are personal capture that just need a real home)
- Move topical folders: `Cooking Recipes/` → `80 creative/cooking/` (or `70 life admin/`); `Bespoke Diamonds/`, `tabletop/`, `poki_tan_jan_Jasi/` → `80 creative/`
- Move `private/` → split across `40 self/` and `50 people/` per content
- Move `archive/` → `90 archive/nexus-archive/`
- Move `CompTIA/` (3 files) → `20 studies/certifications/`
- Move 1 file from Nexus `Computer Science TU856/` → appropriate Year 3 location
- Audit `Extracurricular/` for duplicates between vaults; deduplicate
- Migrate Dataview queries to Bases (audit each query individually)
- Drop Dataview plugin once migration complete

### Decommission (Phase 4)
- Both old vaults remain read-only for **one semester** as backup
- Remove after backup window — documented rollback path: restore from git history (CS vault) + Obsidian Sync history (Nexus, until expiry)

## 13. Risks and mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Loss of Nexus git history | Certain | Low | Acceptable; one-time migration commit captures starting state |
| Cross-repo link breakage on standalone clone | Medium | Low | Discipline + cleanup pass before public flip |
| Copilot embedding regen cost | Certain | Low | One-time post-migration; runs in background; ~$0.10-0.50 cloud or ~30 min local |
| Bases vs Dataview transition gaps | Medium | Medium | Migrate queries during Phase 3 with manual audit; test before content migration |
| Old vaults re-fragmenting if both kept active during migration | Medium | High | Strict freeze on old vaults during/after migration; rename folders to `*.old` to discourage editing |
| Brightspace `modules/` sync repointing breaks | Low | High | Verify with one module before bulk migration; document rollback |
| Cognitive load spike during migration | High | Medium | Phased approach; each phase deliverable independently usable |
| Phone sync hiccups during nested-repo creation | Low | Medium | Run `git init` in each nested folder *before* committing; let Obsidian Sync settle between operations |
| Plugin config drift between devices | Low | Low | Commit `.obsidian/` selectively (excluding device-specific cache) to one of the meta repos |

## 14. Open / deferred decisions

These are intentionally not locked. Decide when relevant.

- **Readwise overhaul** — sync target, template, tag taxonomy, folder organisation. Deferred to post-migration. Detail in §8.2.
- **Quartz configuration** — site theme, deployment target, per-repo vs aggregate. Deferred until first repo flips public.
- **`vault-status` helper script** — small bash to walk nested repos. Spec at implementation time.
- **Syncthing migration** — independent future project. Vault design is sync-mechanism-agnostic.
- **PKM methodology refinement** — return after migration to refine workflows (Zettelkasten depth, evergreen note discipline, GTD weekly review adoption). Mae's existing PKM Methods research carries forward as `60 library/vault-studies/`.
- **Year 1-4 cleanup-for-public-flip** — folded into the summer project (see §16). All four years get a cleanup pass alongside the Codeberg multi-remote migration; flip-public is a per-repo decision after cleanup.
- **Whether to commit `.obsidian/`** — and to which repo. Probably a small `00 meta/` repo or `maenotes-config`.
- **Mobile-side capture beyond Obsidian** — Markor / Termux flows depend on Syncthing migration; revisit when sync changes.
- **Whether `80 creative/` becomes a repo or stays a plain folder** — depends on whether cosplay guides etc. are ever shared publicly.

## 15. Success criteria

The migration is complete when:

1. `~/Documents/MaeNotes/` exists and contains all content from both prior vaults
2. Both old vaults are renamed `.old` and read-only
3. All plugins working; Bases dashboards rendering; Readwise Official syncing to `60 library/readwise/`
4. Phone capture verified end-to-end on both paths: Memos PWA → sync script → `10 inbox/<timestamp>.md` (primary, when VPS is up); Obsidian Mobile share-sheet → new note in `10 inbox/` visible on desktop within 60s (fallback, always works)
5. All four Year-N nested repos (`computer-science` through (merged into `computer-science`)) initialised, committed, and pushed to GitHub (private). Cleanup-for-public-flip on all four years is its own summer project; Codeberg multi-remote also added during that pass — see §16.
6. `qcap` works from terminal
7. PKM Methods research preserved in `60 library/vault-studies/`
8. Mae can locate three previously hard-to-find pieces of knowledge in under 30 seconds each (informal findability test)

The design is **not** complete just because content has moved. It must reduce, not maintain, cognitive load.

## 16. Future work (post-migration)

Out of scope for this design but on the radar:

- Migrate Obsidian Sync → Syncthing (peer-to-peer; no VPS needed; FOSS)
- **Memos as polished mobile capture surface** (FOSS self-hosted FleetingNotes-equivalent at https://github.com/usememos/memos). Card-style PWA on phone for capture, sync script pulls Memos → `10 inbox/<timestamp>.md` periodically. Solves the "FleetingNotes UX is great but paywalled and closed" frustration without paying or running closed-source. Hosting target: Hetzner CAX21 Helsinki (see §6.4).
- **VPS provisioning + homeops repo** (post-FYP). Hetzner CAX21 ARM Helsinki (€5.39/mo) hosts Memos + Forgejo + Syncthing + Caddy + Tailscale via Docker Compose under a `~/homeops/` repo. Architecture detail in `ctx-child-to-parent-github-migration-options`. Deserves its own spec when work begins.
- **Forgejo self-host** as eventual primary forge — replaces Codeberg as origin once the VPS is up and Mae has run-time appetite. GitHub mirror remains for redundancy / discoverability. No content lock-in: flip remotes, repush.
- **Codeberg multi-remote + Year 1-4 cleanup (summer project)** — combined pass after vault migration is stable. Sequence: (1) trial Codeberg multi-remote on 1-2 personal repos (~10 min) to validate workflow + account setup; (2) cleanup pass on each cs-year-N repo (frustration vents, supervisor commentary, half-thoughts) ahead of any potential public flip; (3) bulk-flip all nested vault repos to multi-remote `origin` (Codeberg + GitHub mirror); (4) per-repo public-flip decision after cleanup; (5) `claude-marketplace` stays GitHub-primary forever.
- Quartz site for first cleanup-flipped repo
- `vault-status` script + git workflow shortcuts
- ND-friendly daily ritual experimentation (no commitment yet)
- Cross-vault link audit tool (find dangling links across repo boundaries)
- Optional: digital-garden aggregator if multiple repos go public
- Possible adoption of any periodic review pattern *only if* one emerges organically — never imposed
