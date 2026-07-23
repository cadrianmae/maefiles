# maenotes Implementation Plan — Phases 1, 2a, 2b

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the unified `maenotes` Obsidian vault and migrate all CS TU856 academic content (Years 1-4, PKM Methods, system + root content) into it, reaching a state where Mae can do college work in maenotes and the old CS vault can be safely retired.

**Architecture:** Nested git repos under a plain-folder Obsidian vault root (Pattern X per spec §4). Vault root at `~/Documents/MaeNotes/`, top-level Johnny Decimal areas (00-99 in tens-blocks). Migration uses `cp -a` to preserve old vault as rollback safety net; old vault renamed `.old` only after Phase 2b verification.

**Tech Stack:** Obsidian + plugins (Bases, Templater, QuickAdd, Copilot for Obsidian, Workspaces, Omnisearch, Spaced Repetition, Folder Focus Mode, Homepage, Linter, Excalidraw, Readwise Official, Aloud TTS), git, GitHub (`gh`), bash. Codeberg multi-remote deferred to summer project per spec §4.4.

**Spec:** [`~/docs/specs/2026-05-04-maenotes-vault-design.md`](../specs/2026-05-04-maenotes-vault-design.md) — authoritative for design decisions; this plan only executes them.

**Out of scope of this plan:** Phase 3 (Nexus migration), Phase 4 (decommission), summer project (Codeberg + Year 1-4 cleanup-for-public-flip), VPS provisioning, Memos deployment, Readwise overhaul, embedding model selection.

**Hard guardrails:**

1. **Source vaults are read-only.** Never modify `~/Documents/Computer Science TU856/` or `~/Documents/The Nexus Vault/` — only `cp -a` from them. Migration is one-way: source → maenotes. No `mv`, no `rm`, no edits in source. Source vaults stay intact as rollback for at least one semester.
2. **GitHub repo creation is owned by Mae.** Do not run `gh repo create` or `git remote add` or `git push` to a remote that doesn't yet exist. Local `git init` + `git add` + `git commit` are fine; pushing happens after Mae creates the remote.
3. **No Obsidian Sync coordination needed for source vaults** — since source is read-only, sync state is irrelevant. Sync setup for the new maenotes vault is part of Task 7.

---

## Pre-flight

- [ ] **Verify prerequisites**

Run:
```bash
command -v git && git --version
ls -d "/home/cadrianmae/Documents/Computer Science TU856"
ls -d /home/cadrianmae/docs/specs/2026-05-04-maenotes-vault-design.md
```
Expected: all three commands succeed.

(Source vaults are read-only — no sync pause needed. GitHub remote operations are deferred to Mae.)

---

# Phase 1: Scaffold

## Task 1: Create maenotes vault directory + JD skeleton

**Files:**
- Create (via Obsidian GUI): `~/Documents/MaeNotes/` (vault root, with `.obsidian/` populated by Obsidian)
- Create (FS): JD area subfolders inside the vault

- [ ] **Step 1a: Create the vault via Obsidian GUI** *(human)*

Obsidian → vault switcher → "Create new vault" →
  - Vault name: `maenotes`
  - Location: `/home/cadrianmae/Documents/`
  - Click "Create"

Obsidian opens the empty vault and populates `~/Documents/MaeNotes/.obsidian/` with default config.

Verification:
```bash
ls -la ~/Documents/MaeNotes/.obsidian/ | head
```
Expected: directory exists with `app.json`, `appearance.json`, etc.

- [ ] **Step 1b: Create JD area subfolders inside the vault** *(FS)*

```bash
mkdir -p ~/Documents/MaeNotes/{"00 meta","10 inbox","20 studies","30 projects","40 self","50 people","60 library","70 life admin","80 creative","90 archive"}
mkdir -p ~/Documents/MaeNotes/"00 meta"/{templates,dashboards}
mkdir -p ~/Documents/MaeNotes/"60 library"/{readwise,literature,vault-studies}
```

- [ ] **Step 2: Verify the skeleton**

```bash
tree -L 2 -d ~/Documents/MaeNotes/
```
Expected: 10 top-level area folders; `00 meta/` has `templates/` and `dashboards/`; `60 library/` has `readwise/`, `literature/`, `vault-studies/`.

- [ ] **Step 3: Add a README at vault root**

Create `~/Documents/MaeNotes/README.md`:
```markdown
# maenotes

Unified knowledge vault. Design spec: `~/docs/specs/2026-05-04-maenotes-vault-design.md`.

Vault root is **not** a git repo. Selected sub-areas under `20 studies/`, `30 projects/`, `60 library/vault-studies/` are independent nested repos (Pattern X). See spec §4.

Capture rule: every quick thought goes into `10 inbox/<YYYY-MM-DD-HHMM>.md`. No daily-note ritual.
```

- [ ] **Step 4: Commit-equivalent (no git here, just verify)**

```bash
ls ~/Documents/MaeNotes/
```
Expected: README.md + 10 area folders.

---

## Task 2: Migrate templates from CS vault

**Files:**
- Source: `~/Documents/Computer Science TU856/system/templates/`
- Destination: `~/Documents/MaeNotes/00 meta/templates/`

- [ ] **Step 1: Copy all CS templates into 00 meta/templates/**

```bash
cp -a "/home/cadrianmae/Documents/Computer Science TU856/system/templates/." \
      "/home/cadrianmae/Documents/MaeNotes/00 meta/templates/"
```

- [ ] **Step 2: Verify templates landed**

```bash
ls "/home/cadrianmae/Documents/MaeNotes/00 meta/templates/"
```
Expected: `+add drawing.md`, `+log.md`, `+page break.md`, `book.md`, `fleeting.md`, `meeting notes.md`, `note with drawing.md`, `permanent-note.md`, `person.md`, `review/`, `tu856/`.

- [ ] **Step 3: Add the new templates per spec §11.3**

Create `~/Documents/MaeNotes/00 meta/templates/literature-note.md`:
```markdown
---
type: literature
source: 
author: 
date created: <% tp.date.now() %>
tags: [literature]
---
# <% tp.file.title %>

## Summary

## Key claims

## My commentary

## Source link
```

Create `~/Documents/MaeNotes/00 meta/templates/project-moc.md`:
```markdown
---
type: project-moc
status: active
repo: 
date created: <% tp.date.now() %>
tags: [moc, project]
---
# <% tp.file.title %>

## Status

## Real repo location

## Notes index

## Log
```

Create `~/Documents/MaeNotes/00 meta/templates/vault-study.md`:
```markdown
---
type: vault-study
subject: 
url: 
date created: <% tp.date.now() %>
tags: [vault-study]
---
# <% tp.file.title %>

## Vault overview

## Structural choices

## Plugin / tool stack

## What I'd steal

## What I'd reject
```

Create `~/Documents/MaeNotes/00 meta/templates/readwise-highlight.md`:
```markdown
---
type: readwise-highlight
source: 
author: 
date created: <% tp.date.now() %>
tags: [readwise]
---
# <% tp.file.title %>

> {{highlight}}

## My note

## Why this matters
```

Create `~/Documents/MaeNotes/00 meta/templates/weekly-review.md` (opt-in, per spec §11.3):
```markdown
---
type: weekly-review
week: <% moment().format("YYYY-[W]WW") %>
date created: <% tp.date.now() %>
tags: [review, weekly]
---
# Week <% moment().format("YYYY-[W]WW") %>

## What happened

## What I'm carrying forward

## What I'm letting go
```

Create `~/Documents/MaeNotes/00 meta/templates/daily-log.md` (opt-in):
```markdown
---
type: daily-log
date: <% tp.date.now("YYYY-MM-DD") %>
tags: [daily]
---
# <% tp.date.now("YYYY-MM-DD") %>

```

- [ ] **Step 4: Add a CHANGELOG to record template choices**

Create `~/Documents/MaeNotes/00 meta/templates/CHANGELOG.md`:
```markdown
# Template changelog

- 2026-05-04: Initial seed from CS vault `system/templates/`. Added per spec §11.3: literature-note, project-moc, vault-study, readwise-highlight, weekly-review (opt-in), daily-log (opt-in).
```

- [ ] **Step 5: Verify final template inventory**

```bash
ls "/home/cadrianmae/Documents/MaeNotes/00 meta/templates/"
```
Expected: original CS templates + 6 new + CHANGELOG.md.

---

## Task 3: Configure Obsidian — open the new vault and install plugins

**Files:**
- Modify (via Obsidian GUI): `~/Documents/MaeNotes/.obsidian/`

This task is GUI-driven. Each step is a single Obsidian setting flip; document below.

- [ ] **Step 1: Open the new vault in Obsidian**

Obsidian → "Open another vault" → "Open folder as vault" → `~/Documents/MaeNotes/`.

Verification: Obsidian opens with empty file tree showing the JD skeleton.

- [ ] **Step 2: Enable community plugins**

Settings → Community plugins → "Turn on community plugins".

- [ ] **Step 3: Install the plugin set per spec §9**

Settings → Community plugins → Browse. Install each:

- Templater
- QuickAdd
- Linter (obsidian-linter)
- Excalidraw
- Vimrc Support
- Terminal
- Advanced New File
- Recent Files
- Spaced Repetition
- Folder Focus Mode
- Homepage
- Readwise Official
- Aloud TTS
- Copilot for Obsidian (logancyang)
- Omnisearch
- Local REST API (deferred config — install only)

After installing each, click "Enable".

- [ ] **Step 4: Enable core plugins per spec**

Settings → Core plugins:
- Enable: **Workspaces**, **Bases**, **Templates**
- **Disable**: **Daily notes** (explicitly off per spec §6.0/9.2a)
- Verify: **Periodic Notes** is NOT installed

- [ ] **Step 5: Configure Templater path**

Settings → Templater → Template folder location: `00 meta/templates`

- [ ] **Step 6: Configure QuickAdd capture macro**

Settings → QuickAdd → Add a "Capture" macro:
- Name: `C — Capture`
- Capture to: `10 inbox/{{DATE:YYYY-MM-DD-HHmm}}.md`
- Template: blank or `00 meta/templates/fleeting.md` (Mae's choice)

- [ ] **Step 7: Configure Readwise Official sync target**

Settings → Readwise Official → Sync folder: `60 library/readwise`

(Token + library overhaul deferred per spec §8.2 — minimum viable connection here.)

- [ ] **Step 8: Verify plugin state**

```bash
ls ~/Documents/MaeNotes/.obsidian/plugins/
```
Expected: directories for each installed community plugin.

---

## Task 4: Build the three Bases dashboards

**Files:**
- Create: `~/Documents/MaeNotes/00 meta/dashboards/home-studies.md`
- Create: `~/Documents/MaeNotes/00 meta/dashboards/home-personal.md`
- Create: `~/Documents/MaeNotes/00 meta/dashboards/home-everything.md`

- [ ] **Step 1: Create Home — Studies dashboard**

Create `~/Documents/MaeNotes/00 meta/dashboards/home-studies.md`:
````markdown
# Home — Studies

## Recent inbox captures

```base
filters:
  and:
    - file.inFolder("10 inbox")
views:
  - type: list
    name: Recent captures
    sort:
      - property: file.mtime
        direction: DESC
    limit: 20
```

## Recent study notes

```base
filters:
  or:
    - file.inFolder("20 studies")
    - file.inFolder("60 library")
views:
  - type: table
    name: Recent activity
    order:
      - file.name
      - file.mtime
    sort:
      - property: file.mtime
        direction: DESC
    limit: 20
```

## Knowledge stubs

```base
filters:
  and:
    - file.inFolder("20 studies")
    - file.hasTag("todo/stub")
views:
  - type: list
    name: Stubs to expand
    sort:
      - property: file.mtime
        direction: DESC
    limit: 30
```
````

- [ ] **Step 2: Create Home — Personal dashboard**

Create `~/Documents/MaeNotes/00 meta/dashboards/home-personal.md`:
````markdown
# Home — Personal

## Recent inbox captures

```base
filters:
  and:
    - file.inFolder("10 inbox")
views:
  - type: list
    name: Recent captures
    sort:
      - property: file.mtime
        direction: DESC
    limit: 20
```

## Active projects

```base
filters:
  and:
    - file.inFolder("30 projects")
views:
  - type: cards
    name: Projects
    sort:
      - property: file.mtime
        direction: DESC
```

## Recent personal notes

```base
filters:
  or:
    - file.inFolder("40 self")
    - file.inFolder("50 people")
    - file.inFolder("70 life admin")
    - file.inFolder("80 creative")
views:
  - type: table
    name: Personal-area activity
    order:
      - file.name
      - file.mtime
    sort:
      - property: file.mtime
        direction: DESC
    limit: 20
```
````

- [ ] **Step 3: Create Home — Everything dashboard**

Create `~/Documents/MaeNotes/00 meta/dashboards/home-everything.md`:
````markdown
# Home — Everything

## Recent across the whole vault

```base
filters: {}
views:
  - type: table
    name: Everything
    order:
      - file.name
      - file.folder
      - file.mtime
    sort:
      - property: file.mtime
        direction: DESC
    limit: 30
```

## Recent inbox

```base
filters:
  and:
    - file.inFolder("10 inbox")
views:
  - type: list
    name: Inbox stream
    sort:
      - property: file.mtime
        direction: DESC
    limit: 30
```
````

- [ ] **Step 4: Verify dashboards render in Obsidian**

In Obsidian, open each dashboard file in `00 meta/dashboards/`. Each Bases code block should render a table/list/cards view (likely empty since no content yet — but no syntax errors).

Verification: no red error banners; views show "No results" gracefully.

- [ ] **Step 5: Configure Homepage plugin to point at Studies dashboard**

Settings → Homepage → Homepage: `00 meta/dashboards/home-studies`

---

## Task 5: Save Workspaces for the three focus modes

**Files:**
- Modify (via Obsidian GUI): `~/Documents/MaeNotes/.obsidian/workspaces.json`

- [ ] **Step 1: Configure Studies layout, then save as workspace**

In Obsidian:
1. Open `00 meta/dashboards/home-studies.md` in main pane
2. Pin it
3. Sidebar: file explorer scrolled to `20 studies/`
4. Command palette → "Manage workspace layouts" → "Save layout as..." → name: `Studies`

- [ ] **Step 2: Configure Personal layout, then save as workspace**

1. Switch to `00 meta/dashboards/home-personal.md`
2. Pin it
3. Sidebar: file explorer scrolled to `30 projects/`
4. Command palette → "Manage workspace layouts" → "Save layout as..." → name: `Personal`

- [ ] **Step 3: Configure Everything layout, then save as workspace**

1. Switch to `00 meta/dashboards/home-everything.md`
2. Pin it
3. Sidebar: file explorer at vault root
4. Command palette → "Manage workspace layouts" → "Save layout as..." → name: `Everything`

- [ ] **Step 4: Verify workspaces saved**

```bash
cat "/home/cadrianmae/Documents/MaeNotes/.obsidian/workspaces.json" | python3 -c "import json, sys; d = json.load(sys.stdin); print(list(d.get('workspaces', {}).keys()))"
```
Expected: `['Studies', 'Personal', 'Everything']`.

---

## Task 6: Write the `qcap` shell function

**Files:**
- Create: `~/bin/qcap`

- [ ] **Step 1: Verify `~/bin/` is on PATH**

```bash
echo "$PATH" | tr ':' '\n' | grep -F "$HOME/bin"
```
Expected: `/home/cadrianmae/bin` printed.

- [ ] **Step 2: Write the `qcap` script**

Create `~/bin/qcap`:
```bash
#!/usr/bin/env bash
# qcap — quick capture into the maenotes inbox.
# Usage: qcap "thought" | qcap < file | echo "thought" | qcap

set -euo pipefail

VAULT="${MAENOTES_VAULT:-$HOME/Documents/maenotes}"
INBOX="$VAULT/10 inbox"
TS="$(date '+%Y-%m-%d-%H%M')"
DEST="$INBOX/$TS.md"

# Collision suffix
i=2
while [[ -e "$DEST" ]]; do
  DEST="$INBOX/$TS-$i.md"
  ((i++))
done

mkdir -p "$INBOX"

if [[ $# -gt 0 ]]; then
  printf '%s\n' "$*" > "$DEST"
elif [[ ! -t 0 ]]; then
  cat > "$DEST"
else
  ${EDITOR:-nvim} "$DEST"
fi

echo "$DEST"
```

- [ ] **Step 3: Make executable**

```bash
chmod +x ~/bin/qcap
```

- [ ] **Step 4: Smoke test — string arg**

```bash
qcap "test capture from qcap arg"
```
Expected: prints path like `/home/cadrianmae/Documents/MaeNotes/10 inbox/2026-05-04-1900.md`.

```bash
ls "/home/cadrianmae/Documents/MaeNotes/10 inbox/"
cat "/home/cadrianmae/Documents/MaeNotes/10 inbox/"*.md
```
Expected: file exists with the test string as its contents.

- [ ] **Step 5: Smoke test — stdin pipe**

```bash
echo "test capture via stdin" | qcap
```
Expected: second timestamped file appears in `10 inbox/` containing the piped text.

- [ ] **Step 6: Clean the smoke-test captures (optional)**

```bash
rm "/home/cadrianmae/Documents/MaeNotes/10 inbox/"*.md
```

---

## Task 7: Phase 1 device test

- [ ] **Step 1: Re-enable Obsidian Sync on the new maenotes vault**

Settings → Sync → Choose "maenotes" vault (or create a new sync remote for it). Pause sync remains on the old CS vault.

- [ ] **Step 2: Verify sync replicates the scaffold**

Wait for initial sync to settle. On a second device (or via Obsidian Sync web UI / second client), confirm the JD skeleton + templates + dashboards appear.

- [ ] **Step 3: End-to-end capture verification**

```bash
qcap "phase 1 verification capture"
```

Open the new vault on Obsidian. The new file should appear in `10 inbox/` within seconds. Open it; it should render correctly.

- [ ] **Step 4: Dashboards verification**

Open each Home dashboard. The "phase 1 verification capture" should appear in the inbox list view of Studies, Personal, and Everything.

- [ ] **Phase 1 success criteria**

Before moving to Phase 2a, all of these must hold:
- ✅ `~/Documents/MaeNotes/` exists with the JD skeleton
- ✅ All planned plugins installed and enabled (Daily Notes core OFF, Periodic Notes NOT installed)
- ✅ Three Home dashboards render without errors
- ✅ Three Workspaces saved
- ✅ `qcap` works (arg + stdin)
- ✅ Obsidian Sync replicates new vault (or sync explicitly deferred)
- ✅ At least one capture from `qcap` appears in dashboard views

---

# Phase 2a: Year 4 migration (working state for college)

This is the unlock for doing college work in maenotes. Old CS vault remains intact as rollback.

## Task 8: Copy Year 4 content into `21 computer science/cs-year-4/`

**Files:**
- Source: `~/Documents/Computer Science TU856/Year 4/`
- Destination: `~/Documents/MaeNotes/21 computer science/cs-year-4/`

- [ ] **Step 1: Create destination + copy contents**

```bash
mkdir -p "/home/cadrianmae/Documents/MaeNotes/21 computer science/cs-year-4"
cp -a "/home/cadrianmae/Documents/Computer Science TU856/Year 4/." \
      "/home/cadrianmae/Documents/MaeNotes/21 computer science/cs-year-4/"
```

- [ ] **Step 2: Verify content count and structure**

```bash
SRC_COUNT=$(find "/home/cadrianmae/Documents/Computer Science TU856/Year 4" -type f | wc -l)
DST_COUNT=$(find "/home/cadrianmae/Documents/MaeNotes/21 computer science/cs-year-4" -type f | wc -l)
echo "source: $SRC_COUNT, dest: $DST_COUNT"
[[ "$SRC_COUNT" == "$DST_COUNT" ]] && echo "OK" || echo "MISMATCH"
```
Expected: equal counts; "OK".

- [ ] **Step 3: Spot-check a known file**

```bash
ls "/home/cadrianmae/Documents/MaeNotes/21 computer science/cs-year-4/Year 4.md"
ls "/home/cadrianmae/Documents/MaeNotes/21 computer science/cs-year-4/10 lecture notes/" | head -5
```
Expected: `Year 4.md` exists; `10 lecture notes/` has files.

---

## Task 9: Initialise Year 4 as a nested git repo

**Files:**
- Create: `~/Documents/MaeNotes/21 computer science/cs-year-4/.git/`
- Create: `~/Documents/MaeNotes/21 computer science/cs-year-4/.gitignore`

- [ ] **Step 1: Initialise repo**

```bash
cd "/home/cadrianmae/Documents/MaeNotes/21 computer science/cs-year-4"
git init -b main
```
Expected: "Initialized empty Git repository".

- [ ] **Step 2: Add `.gitignore` excluding Brightspace-synced + cache**

Create `~/Documents/MaeNotes/21 computer science/cs-year-4/.gitignore`:
```
# Brightspace-synced — never commit
20 modules/

# Obsidian cache that shouldn't be repo-tracked
.smart-env/
.trash/
```

- [ ] **Step 3: First commit**

```bash
cd "/home/cadrianmae/Documents/MaeNotes/21 computer science/cs-year-4"
git add .
git commit -m "chore: initial import of cs-year-4 from CS TU856 vault

Migrated from ~/Documents/Computer Science TU856/Year 4/ as part of
maenotes Phase 2a. Source vault remains intact pending decommission.
Brightspace-synced 20 modules/ excluded via .gitignore.

Spec: ~/docs/specs/2026-05-04-maenotes-vault-design.md"
```

- [ ] **Step 4: Verify clean working tree**

```bash
cd "/home/cadrianmae/Documents/MaeNotes/21 computer science/cs-year-4"
git status
```
Expected: "nothing to commit, working tree clean".

---

## Task 10: Repoint Brightspace `modules/` sync + verify

The Brightspace `modules/` content is downloaded by an external sync mechanism Mae configures (per CS vault's `CLAUDE.md`: "synced from Brightspace"). The destination path needs updating to the new location.

- [ ] **Step 1: Identify the Brightspace sync mechanism**

```bash
grep -ril -e "brightspace" -e "Brightspace" ~/bin ~/scripts ~/.config 2>/dev/null | head
ls "/home/cadrianmae/Documents/Computer Science TU856/Year 4/20 modules/" | head
```
Action: locate the script / cron / app config that populates `Year 4/20 modules/`. (May be a manual download — if so, treat as "next download lands in new path".)

- [ ] **Step 2: Update sync target path**

Edit the sync mechanism's destination from:
- old: `~/Documents/Computer Science TU856/Year 4/20 modules/`
- new: `~/Documents/MaeNotes/21 computer science/cs-year-4/20 modules/`

(Exact location depends on what Step 1 found.)

- [ ] **Step 3: Trigger a sync run**

Run the sync mechanism manually (e.g., script invocation, app refresh).

- [ ] **Step 4: Verify one module ends up in the new path**

```bash
ls "/home/cadrianmae/Documents/MaeNotes/21 computer science/cs-year-4/20 modules/" | head
```
Expected: at least one module folder present and recently modified.

- [ ] **Step 5: Verify the old path is no longer being written to**

```bash
stat -c '%y' "/home/cadrianmae/Documents/Computer Science TU856/Year 4/20 modules/" | head
```
Expected: mtime not updated by the recent sync run (sync went to new path).

---

## Task 11: GitHub remote setup *(owned by Mae)*

GitHub repo creation + remote configuration is owned by Mae, not the migration agent. After the local (merged into `computer-science`) repo is committed (Task 9), Mae creates the GitHub repo (suggested name: (merged into `computer-science`), private) and wires the remote at her own pace.

Reference commands (for Mae's use, not for the agent):

```bash
gh repo create cadrianmae/cs-year-4 --private --description "Year 4 (Computer Science TU856)"
cd "/home/cadrianmae/Documents/MaeNotes/21 computer science/cs-year-4"
git remote add origin https://github.com/cadrianmae/cs-year-4.git
git push -u origin main
```

- [ ] **Step 1 (Mae): Create the GitHub repo at your own pace**

Not blocking for Phase 2b — local nested repo with one commit is sufficient to proceed.

- [ ] **Phase 2a success criteria**

Before moving to Phase 2b:
- ✅ `~/Documents/MaeNotes/21 computer science/cs-year-4/` mirrors the source Year 4 content
- ✅ Nested git repo initialised + first commit local
- ✅ Brightspace `modules/` syncs to the new path; one module verified
- ✅ Source CS vault `Year 4/` untouched (read-only guardrail held)
- ✅ Mae can open maenotes in Obsidian and use Year 4 content for college work
- ⏳ GitHub remote setup deferred to Mae (not blocking)

You are now in the **working state for college work**. Phase 2b can run when you have time/energy.

---

# Phase 2b: Years 1-3 + PKM Methods + CS triage

Years 1-3 are less active (archival). Each repeats the same migration pattern as Year 4 but with less verification overhead. Then root-level CS pollution gets triaged.

## Task 12: Migrate Year 1

- [ ] **Step 1: Copy + init**

```bash
mkdir -p "/home/cadrianmae/Documents/MaeNotes/21 computer science/cs-year-1"
cp -a "/home/cadrianmae/Documents/Computer Science TU856/Year 1/." \
      "/home/cadrianmae/Documents/MaeNotes/21 computer science/cs-year-1/"
cd "/home/cadrianmae/Documents/MaeNotes/21 computer science/cs-year-1"
git init -b main
```

- [ ] **Step 2: Add `.gitignore`**

Create `~/Documents/MaeNotes/21 computer science/cs-year-1/.gitignore`:
```
.smart-env/
.trash/
```
(Year 1 has no Brightspace `modules/` sync — confirm with `ls`. If present, add `20 modules/` to gitignore.)

- [ ] **Step 3: Verify counts**

```bash
SRC=$(find "/home/cadrianmae/Documents/Computer Science TU856/Year 1" -type f | wc -l)
DST=$(find "/home/cadrianmae/Documents/MaeNotes/21 computer science/cs-year-1" -type f | wc -l)
echo "src=$SRC dst=$DST"; [[ $SRC -eq $DST ]] && echo OK || echo MISMATCH
```

- [ ] **Step 4: Commit**

```bash
cd "/home/cadrianmae/Documents/MaeNotes/21 computer science/cs-year-1"
git add .
git commit -m "chore: initial import of cs-year-1 from CS TU856 vault"
```

- [ ] **Step 5 (Mae): GitHub remote setup deferred to you, at your own pace**

Suggested when you're ready: `gh repo create cadrianmae/cs-year-1 --private` then add remote + push. Not blocking the rest of the plan.

---

## Task 13: Migrate Year 2

- [ ] **Step 1: Copy + init**

```bash
mkdir -p "/home/cadrianmae/Documents/MaeNotes/21 computer science/cs-year-2"
cp -a "/home/cadrianmae/Documents/Computer Science TU856/Year 2/." \
      "/home/cadrianmae/Documents/MaeNotes/21 computer science/cs-year-2/"
cd "/home/cadrianmae/Documents/MaeNotes/21 computer science/cs-year-2"
git init -b main
```

- [ ] **Step 2: Add `.gitignore`** (same content as cs-year-1)

```bash
cat > "/home/cadrianmae/Documents/MaeNotes/21 computer science/cs-year-2/.gitignore" << 'EOF'
.smart-env/
.trash/
EOF
```

- [ ] **Step 3: Verify counts**

```bash
SRC=$(find "/home/cadrianmae/Documents/Computer Science TU856/Year 2" -type f | wc -l)
DST=$(find "/home/cadrianmae/Documents/MaeNotes/21 computer science/cs-year-2" -type f | wc -l)
echo "src=$SRC dst=$DST"; [[ $SRC -eq $DST ]] && echo OK || echo MISMATCH
```

- [ ] **Step 4: Commit (local only — push deferred to Mae)**

```bash
cd "/home/cadrianmae/Documents/MaeNotes/21 computer science/cs-year-2"
git add . && git commit -m "chore: initial import of cs-year-2 from CS TU856 vault"
```

GitHub remote (suggested name (merged into `computer-science`), private) created by Mae at her own pace.

---

## Task 14: Migrate Year 3

- [ ] **Step 1: Copy + init**

```bash
mkdir -p "/home/cadrianmae/Documents/MaeNotes/21 computer science/cs-year-3"
cp -a "/home/cadrianmae/Documents/Computer Science TU856/Year 3/." \
      "/home/cadrianmae/Documents/MaeNotes/21 computer science/cs-year-3/"
cd "/home/cadrianmae/Documents/MaeNotes/21 computer science/cs-year-3"
git init -b main
```

- [ ] **Step 2: Add `.gitignore`**

```bash
cat > "/home/cadrianmae/Documents/MaeNotes/21 computer science/cs-year-3/.gitignore" << 'EOF'
.smart-env/
.trash/
EOF
```

- [ ] **Step 3: Verify counts**

```bash
SRC=$(find "/home/cadrianmae/Documents/Computer Science TU856/Year 3" -type f | wc -l)
DST=$(find "/home/cadrianmae/Documents/MaeNotes/21 computer science/cs-year-3" -type f | wc -l)
echo "src=$SRC dst=$DST"; [[ $SRC -eq $DST ]] && echo OK || echo MISMATCH
```

- [ ] **Step 4: Commit (local only — push deferred to Mae)**

```bash
cd "/home/cadrianmae/Documents/MaeNotes/21 computer science/cs-year-3"
git add . && git commit -m "chore: initial import of cs-year-3 from CS TU856 vault"
```

GitHub remote (suggested name (merged into `computer-science`), private) created by Mae at her own pace.

---

## Task 15: Migrate PKM Methods → `60 library/vault-studies/`

**Files:**
- Source: `~/Documents/Computer Science TU856/PKM Methods/`
- Destination: `~/Documents/MaeNotes/60 library/vault-studies/`

- [ ] **Step 1: Copy contents into vault-studies**

```bash
cp -a "/home/cadrianmae/Documents/Computer Science TU856/PKM Methods/." \
      "/home/cadrianmae/Documents/MaeNotes/60 library/vault-studies/"
```

- [ ] **Step 2: Verify**

```bash
ls "/home/cadrianmae/Documents/MaeNotes/60 library/vault-studies/"
```
Expected: `Current Vault Implementation.md`, `Evergreen Notes.md`, `GTD.md`, `Johnny Decimal.md`, `MOCs and LYT.md`, `Note-Taking Methodologies.md`, `PARA.md`, `PKM Methods MOC.md`, `Zettelkasten.md`.

- [ ] **Step 3: Init nested repo**

```bash
cd "/home/cadrianmae/Documents/MaeNotes/60 library/vault-studies"
git init -b main
cat > .gitignore << 'EOF'
.smart-env/
.trash/
EOF
git add .
git commit -m "chore: initial import of vault-studies from CS vault PKM Methods/"
```

- [ ] **Step 4 (Mae): GitHub remote setup deferred**

Suggested when ready: `gh repo create cadrianmae/vault-studies --private`. Local repo with first commit is sufficient for the plan to proceed.

---

## Task 16: Triage CS vault root pollution

CS vault root has many top-level files (PDFs, audit docs, drawio files, zips) that don't belong in `Year 4/`. Each gets a target area.

- [ ] **Step 1: List the pollution**

```bash
cd "/home/cadrianmae/Documents/Computer Science TU856"
ls -la | grep -v '^d' | grep -v '^total' | awk '{print $NF}' | grep -v '^\.\.$\|^\.$\|^\.git\|^\.gitignore\|^\.gitattributes\|^CLAUDE\.md$' | sort
```
Expected: list of root-level files. Capture this list — Mae will assign each.

- [ ] **Step 2: Bulk-categorise — interactive triage**

For each root file, decide one of:
- `90 archive/cs-vault-root/` — historical, keep but don't surface
- `80 creative/` — e.g. `princess-bubblegum-cosplay-guide.md` (per spec §12)
- `30 projects/` — if it's project material
- Delete — if genuinely cruft (duplicate PDFs, old assignment exports)

Suggested defaults (per spec):
- `princess-bubblegum-cosplay-guide.md` → `80 creative/cosplay/`
- All `*.pdf`, `*.drawio`, `*.zip`, `*.docx`, `*.xlsx`, `*.csv`, `*.html` at CS root → `90 archive/cs-vault-root/`
- `audit-cmpu*.md` → `90 archive/cs-vault-root/audits/` (or delete if obsolete)
- `Computer Science TU856.md` → `90 archive/cs-vault-root/` (was vault homepage; superseded by maenotes README)

- [ ] **Step 3: Execute the triage**

Create destinations:
```bash
mkdir -p "/home/cadrianmae/Documents/MaeNotes/90 archive/cs-vault-root/audits"
mkdir -p "/home/cadrianmae/Documents/MaeNotes/80 creative/cosplay"
```

Move (example for the cosplay guide — repeat pattern per file):
```bash
# Cosplay guide
[[ -f "/home/cadrianmae/Documents/Computer Science TU856/princess-bubblegum-cosplay-guide.md" ]] && \
  cp -a "/home/cadrianmae/Documents/Computer Science TU856/princess-bubblegum-cosplay-guide.md" \
        "/home/cadrianmae/Documents/MaeNotes/80 creative/cosplay/"

# Bulk: PDFs to archive
cp -a "/home/cadrianmae/Documents/Computer Science TU856/"*.pdf \
      "/home/cadrianmae/Documents/MaeNotes/90 archive/cs-vault-root/" 2>/dev/null

# Bulk: drawio
cp -a "/home/cadrianmae/Documents/Computer Science TU856/"*.drawio \
      "/home/cadrianmae/Documents/MaeNotes/90 archive/cs-vault-root/" 2>/dev/null

# Bulk: zips, docx, xlsx, csv, html
for ext in zip docx xlsx csv html; do
  cp -a "/home/cadrianmae/Documents/Computer Science TU856/"*.$ext \
        "/home/cadrianmae/Documents/MaeNotes/90 archive/cs-vault-root/" 2>/dev/null
done

# audit-* markdown
cp -a "/home/cadrianmae/Documents/Computer Science TU856/audit-"*.md \
      "/home/cadrianmae/Documents/MaeNotes/90 archive/cs-vault-root/audits/" 2>/dev/null
```

- [ ] **Step 4: Verify nothing critical was missed**

```bash
ls "/home/cadrianmae/Documents/Computer Science TU856/" | grep -v '^Year [1-4]$\|^PKM Methods$\|^system$\|^attachments$\|^fleeting$\|^Extracurricular$\|^modules$\|^knowledge$\|^claude$\|^\.\|^CLAUDE\.md$\|^README\.md$' | head -50
```
Expected: each remaining unmigrated file gets a manual decision (move to `90 archive/cs-vault-root/` if unsure).

---

## Task 17: Migrate `system/`, `fleeting/`, `Extracurricular/`, `knowledge/`

- [ ] **Step 1: `system/` (the templates folder, plus configs/scripts/workflows) → archive**

`system/templates/` already migrated in Task 2. The rest of `system/` (configs, experiments, Keybinds.md, README.md, scripts, spacekeys.md, Style Guide.md, workflows, changelog.md, changelog.base) goes to `90 archive/cs-vault-root/system/`.

```bash
mkdir -p "/home/cadrianmae/Documents/MaeNotes/90 archive/cs-vault-root/system"
cp -a "/home/cadrianmae/Documents/Computer Science TU856/system/." \
      "/home/cadrianmae/Documents/MaeNotes/90 archive/cs-vault-root/system/"
# Don't double-copy templates — but this is fine, archive holds the snapshot
```

- [ ] **Step 2: `fleeting/` → `10 inbox/historical/fleeting/`**

These are historical fleeting captures from the old plugin workflow. Per spec §6.0a they remain searchable; just give them a home.

```bash
mkdir -p "/home/cadrianmae/Documents/MaeNotes/10 inbox/historical/fleeting"
cp -a "/home/cadrianmae/Documents/Computer Science TU856/fleeting/." \
      "/home/cadrianmae/Documents/MaeNotes/10 inbox/historical/fleeting/" 2>/dev/null || echo "no fleeting dir"
ls "/home/cadrianmae/Documents/MaeNotes/10 inbox/historical/fleeting/" | head
```

- [ ] **Step 3: `Extracurricular/` → triage**

Per spec §12: "Audit `Extracurricular/` for duplicates between vaults". Nexus migration (Phase 3) will dedupe later. For now, move into `80 creative/extracurricular-cs/`:

```bash
mkdir -p "/home/cadrianmae/Documents/MaeNotes/80 creative/extracurricular-cs"
cp -a "/home/cadrianmae/Documents/Computer Science TU856/Extracurricular/." \
      "/home/cadrianmae/Documents/MaeNotes/80 creative/extracurricular-cs/"
```

- [ ] **Step 4: Cross-year `knowledge/` → `60 library/literature/knowledge-cross-year/`**

The CS vault has a top-level `knowledge/` (cross-year knowledge base) per CS CLAUDE.md.

```bash
if [[ -d "/home/cadrianmae/Documents/Computer Science TU856/knowledge" ]]; then
  mkdir -p "/home/cadrianmae/Documents/MaeNotes/60 library/literature/knowledge-cross-year"
  cp -a "/home/cadrianmae/Documents/Computer Science TU856/knowledge/." \
        "/home/cadrianmae/Documents/MaeNotes/60 library/literature/knowledge-cross-year/"
fi
```

- [ ] **Step 5: `attachments/` → `90 archive/cs-vault-root/attachments/`**

```bash
if [[ -d "/home/cadrianmae/Documents/Computer Science TU856/attachments" ]]; then
  mkdir -p "/home/cadrianmae/Documents/MaeNotes/90 archive/cs-vault-root/attachments"
  cp -a "/home/cadrianmae/Documents/Computer Science TU856/attachments/." \
        "/home/cadrianmae/Documents/MaeNotes/90 archive/cs-vault-root/attachments/"
fi
```

- [ ] **Step 6: top-level `modules/` (module descriptors) → `90 archive/cs-vault-root/modules/`**

Per CS CLAUDE.md the top-level `modules/` has module descriptor files (separate from per-year `20 modules/` Brightspace sync).

```bash
if [[ -d "/home/cadrianmae/Documents/Computer Science TU856/modules" ]]; then
  mkdir -p "/home/cadrianmae/Documents/MaeNotes/90 archive/cs-vault-root/modules"
  cp -a "/home/cadrianmae/Documents/Computer Science TU856/modules/." \
        "/home/cadrianmae/Documents/MaeNotes/90 archive/cs-vault-root/modules/"
fi
```

- [ ] **Step 7: CS `CLAUDE.md` → archive (do NOT keep at maenotes root — vault has its own CLAUDE.md or README)**

```bash
mkdir -p "/home/cadrianmae/Documents/MaeNotes/90 archive/cs-vault-root"
cp -a "/home/cadrianmae/Documents/Computer Science TU856/CLAUDE.md" \
      "/home/cadrianmae/Documents/MaeNotes/90 archive/cs-vault-root/CLAUDE.md.cs-vault-original"
```

---

## Task 18: Phase 2b verification

- [ ] **Step 1: Verify all Year repos have a first commit**

```bash
for y in 1 2 3 4; do
  echo "=== cs-year-$y ==="
  cd "/home/cadrianmae/Documents/MaeNotes/21 computer science/cs-year-$y"
  git log --oneline -1
done
```
Expected: each year has at least one commit. (Remote configuration owned by Mae — checked separately by her.)

- [ ] **Step 2: Verify vault-studies repo**

```bash
cd "/home/cadrianmae/Documents/MaeNotes/60 library/vault-studies"
git log --oneline -1
```

- [ ] **Step 3: Source CS vault is untouched (read-only guardrail held)**

```bash
cd "/home/cadrianmae/Documents/Computer Science TU856"
git status
```
Expected: working tree shows no agent-introduced changes (Mae's own edits during the session are her own, but the migration agent must not have touched anything).

- [ ] **Step 4: Open maenotes in Obsidian and visually confirm**

In Obsidian:
- File explorer shows `21 computer science/cs-year-1`, (merged into `computer-science`), (merged into `computer-science`), (merged into `computer-science`)
- `60 library/vault-studies/` shows the PKM Methods notes
- `80 creative/cosplay/` and `90 archive/cs-vault-root/` populated
- `10 inbox/historical/fleeting/` populated (if old fleeting captures existed)
- Open Home — Studies dashboard — recent activity now shows year-N notes

- [ ] **Step 5: Wikilinks crossing repo boundaries — sanity spot-check**

In Obsidian, open any note in `cs-year-4/` that wikilinks to a Year 3 concept. Confirm the link resolves (Obsidian sees one tree across nested repos).

- [ ] **Step 6: Old CS vault is a candidate for renaming to `.old` — but not yet**

Do **not** rename the old CS vault to `.old` yet — that's Phase 4 (out of scope). Old vault remains intact as a one-semester rollback per spec §12 / §15.

- [ ] **Phase 2b success criteria**

- ✅ Unified `computer-science` repo initialised + first commit local
- ✅ `vault-studies` repo initialised + first commit local
- ✅ CS root pollution triaged (cosplay guide → Creative; PDFs/drawio/etc. → Archive)
- ✅ `system/`, `fleeting/`, `Extracurricular/`, top-level `knowledge/` and `modules/` migrated
- ✅ Source CS vault untouched (read-only guardrail held)
- ✅ Mae can navigate maenotes for cross-year reference
- ⏳ GitHub remote setup for all two repos owned by Mae (not blocking)

---

# Wrap-up

## What's done

- Phase 1: maenotes vault scaffolded, plugins configured, dashboards live, `qcap` ready
- Phase 2a: Year 4 migrated, Brightspace `modules/` repointed, ready for college work
- Phase 2b: Years 1-3 + PKM Methods migrated; CS root content triaged and homed

## What's deferred (per spec §12 / §16)

- **Phase 3**: Nexus vault migration (60+ root files triage, Dataview→Bases query migration, dedup with CS Extracurricular)
- **Phase 4**: Decommission — rename old vaults `.old`, read-only for one semester
- **Summer project**: Codeberg multi-remote migration + Year 1-4 cleanup-for-public-flip
- **VPS / Memos**: phone capture polish (fallback via Obsidian Mobile share-sheet always works)
- **Readwise overhaul**: sync target audit, template rewrite, taxonomy

## Next session pointers

When resuming:
- Start with `current-work` skill or `/context:receive` if handed off
- `~/docs/specs/2026-05-04-maenotes-vault-design.md` is the spec; this plan executes it
- Memory file: `project_maenotes_vault.md`
