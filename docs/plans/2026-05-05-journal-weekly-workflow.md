# Journal + Weekly Notes Workflow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Set up `40 self/journal/` (wellness journal) and `40 self/periodic/weekly/` (combined daily-substitute + retro/plan + academic weekly) workflows; migrate existing `16 logs/` content; consolidate weekly templates.

**Architecture:** Filesystem operations + template files. Two new folders, one new + two deleted templates, ~6 existing files moved, three Index files created/updated. All inside MaeNotes vault; touches `21 computer science/` git repo for the migration commit.

**Tech Stack:** Bash, Templater (Obsidian plugin) syntax for template files. No code/tests in the engineering sense — verification is filesystem state + `git status`.

**Spec:** [`~/docs/specs/2026-05-05-journal-weekly-workflow.md`](../specs/2026-05-05-journal-weekly-workflow.md)

**Hard guardrails:**
1. `21 computer science/` is a git repo — migration commits land there
2. Source vaults `Computer Science TU856/` and `The Nexus Vault/` remain read-only (we don't touch them)
3. Earlier-created scaffolding (`40 self/weekly-reviews/`, `40 self/journal/Index.md`) needs cleanup since those were created during a "jumped ahead" mistake — they don't fully align with the final design

---

## Task 1: Cleanup pre-emptive scaffolding

**Files:**
- Delete: `40 self/weekly-reviews/` (replaced by `40 self/periodic/weekly/`)
- Keep but later-overwrite: `40 self/journal/Index.md`
- Keep: `40 self/journal/` folder

- [ ] **Step 1: Verify pre-emptive scaffolding state**

```bash
ls "/home/cadrianmae/Documents/MaeNotes/40 self/" 2>&1
ls "/home/cadrianmae/Documents/MaeNotes/40 self/journal/" 2>&1
ls "/home/cadrianmae/Documents/MaeNotes/40 self/weekly-reviews/" 2>&1
```

Expected: `journal/` and `weekly-reviews/` exist; both have only an Index.md (no real content).

- [ ] **Step 2: Confirm no real content lost by deletion**

```bash
find "/home/cadrianmae/Documents/MaeNotes/40 self/weekly-reviews/" -type f -not -name "Index.md" 2>&1
```

Expected: empty output (no real entries; the only file is the Index.md placeholder).

- [ ] **Step 3: Delete `40 self/weekly-reviews/`**

```bash
rm -rf "/home/cadrianmae/Documents/MaeNotes/40 self/weekly-reviews"
```

- [ ] **Step 4: Verify**

```bash
[[ ! -d "/home/cadrianmae/Documents/MaeNotes/40 self/weekly-reviews" ]] && echo "✓ removed" || echo "✗ still exists"
```

Expected: `✓ removed`.

---

## Task 2: Pre-migration inspection of existing weekly logs

**Files:**
- Read-only inspection: `21 computer science/cs-year-{1,2,3,4}/16 logs/`

- [ ] **Step 1: List files per year**

```bash
for n in 1 2 3 4; do
  echo "=== cs-year-$n/16 logs/ ==="
  if [[ -d "/home/cadrianmae/Documents/MaeNotes/21 computer science/cs-year-$n/16 logs" ]]; then
    ls "/home/cadrianmae/Documents/MaeNotes/21 computer science/cs-year-$n/16 logs/"
  else
    echo "  (no 16 logs/ folder)"
  fi
done
```

Expected output: list of `.md` files per year. Year 4 confirmed using `<YYYY-WNN>.md` format. Other years TBD.

- [ ] **Step 2: Spot-check filename format for non-Y4 years**

For each year that has files, sample one filename. If matching `<YYYY-WNN>.md` (e.g., `2026-W19.md`), no rename needed. If matching anything else, note the format for Task 4.

```bash
for n in 1 2 3 4; do
  d="/home/cadrianmae/Documents/MaeNotes/21 computer science/cs-year-$n/16 logs"
  [[ -d "$d" ]] && echo "year-$n sample: $(ls "$d" | head -1)"
done
```

Record format per year inline before moving to Task 4.

---

## Task 3: Create journal template

**Files:**
- Create: `00 meta/templates/journal.md`

- [ ] **Step 1: Write template**

```bash
cat > "/home/cadrianmae/Documents/MaeNotes/00 meta/templates/journal.md" << 'EOF'
---
type: journal
date: <% tp.date.now("YYYY-MM-DD") %>
mood: 
energy: 
triggers: []
tags: [journal, wellness]
---
# <% tp.file.title %>


EOF
```

- [ ] **Step 2: Verify**

```bash
cat "/home/cadrianmae/Documents/MaeNotes/00 meta/templates/journal.md"
```

Expected: matches the template above exactly.

---

## Task 4: Create unified weekly template

**Files:**
- Create: `00 meta/templates/weekly.md`

- [ ] **Step 1: Write template**

```bash
cat > "/home/cadrianmae/Documents/MaeNotes/00 meta/templates/weekly.md" << 'EOF'
---
academic week: <% tp.date.now("WW") %>-<% tp.date.now("YYYY") %>
date: <% moment().isoWeekday(1).format("YYYY-MM-DD") %>
end date: <% moment().isoWeekday(7).format("YYYY-MM-DD") %>
tags: [weekly]
---

# Week <% tp.date.now("WW") %>

## Monday <% moment().isoWeekday(1).format("YYYY-MM-DD") %>

## Tuesday <% moment().isoWeekday(2).format("YYYY-MM-DD") %>

## Wednesday <% moment().isoWeekday(3).format("YYYY-MM-DD") %>

## Thursday <% moment().isoWeekday(4).format("YYYY-MM-DD") %>

## Friday <% moment().isoWeekday(5).format("YYYY-MM-DD") %>

## Saturday <% moment().isoWeekday(6).format("YYYY-MM-DD") %>

## Sunday <% moment().isoWeekday(7).format("YYYY-MM-DD") %>

---

## Weekly Summary

*Key accomplishments, what went well, what to carry forward*

---

## Weekly Checklist

### [[CMPU XXXX <Module>|<Module>]]
- [ ] <class/lab/meeting>

### Additional
- [ ]

---

## Retro

### Carrying forward
- 

### Letting go
- 

---

## Next week

- 
EOF
```

- [ ] **Step 2: Verify**

```bash
head -10 "/home/cadrianmae/Documents/MaeNotes/00 meta/templates/weekly.md"
wc -l "/home/cadrianmae/Documents/MaeNotes/00 meta/templates/weekly.md"
```

Expected: file exists with proper frontmatter; ~50 lines.

---

## Task 5: Delete old weekly templates

**Files:**
- Delete: `00 meta/templates/weekly-review.md`
- Delete: `00 meta/templates/review/weekly.md`
- Delete: `00 meta/templates/review/` if empty after

- [ ] **Step 1: Confirm both old templates exist**

```bash
ls "/home/cadrianmae/Documents/MaeNotes/00 meta/templates/weekly-review.md"
ls "/home/cadrianmae/Documents/MaeNotes/00 meta/templates/review/weekly.md"
```

Both should exist.

- [ ] **Step 2: Delete**

```bash
rm "/home/cadrianmae/Documents/MaeNotes/00 meta/templates/weekly-review.md"
rm "/home/cadrianmae/Documents/MaeNotes/00 meta/templates/review/weekly.md"
```

- [ ] **Step 3: Cleanup empty review/ if present**

```bash
ls "/home/cadrianmae/Documents/MaeNotes/00 meta/templates/review/" 2>&1
# If only Daily.md remains, leave review/ alone. If empty, rmdir.
rmdir "/home/cadrianmae/Documents/MaeNotes/00 meta/templates/review" 2>/dev/null || echo "  review/ kept (still has files)"
```

- [ ] **Step 4: Verify only new combined template exists**

```bash
ls "/home/cadrianmae/Documents/MaeNotes/00 meta/templates/" | grep -i week
```

Expected: only `weekly.md`.

---

## Task 6: Create new periodic folder structure + Index files

**Files:**
- Create: `40 self/periodic/`
- Create: `40 self/periodic/weekly/`
- Create: `40 self/periodic/Index.md`
- Create: `40 self/periodic/weekly/Index.md`
- Overwrite: `40 self/journal/Index.md` (refresh with final design)

- [ ] **Step 1: Create folders**

```bash
mkdir -p "/home/cadrianmae/Documents/MaeNotes/40 self/periodic/weekly"
```

- [ ] **Step 2: Write `40 self/periodic/Index.md`**

```bash
cat > "/home/cadrianmae/Documents/MaeNotes/40 self/periodic/Index.md" << 'EOF'
---
type: folder-index
date created: 2026-05-05
tags: [moc]
---

# Periodic notes

Opt-in periodic reflection. No plugin enforces creation; templates exist for when you want one.

## Subfolders

- `weekly/` — Combined daily-substitute + retro + plan + academic week summary. ISO week filename `<YYYY-WNN>.md`.

## Future

- `monthly/`, `yearly/` — currently no template, no folder. Create when use case emerges.
EOF
```

- [ ] **Step 3: Write `40 self/periodic/weekly/Index.md`**

```bash
cat > "/home/cadrianmae/Documents/MaeNotes/40 self/periodic/weekly/Index.md" << 'EOF'
---
type: folder-index
date created: 2026-05-05
tags: [moc]
---

# Weekly notes

One file per ISO week. Combines:

- **Per-day timestamped notes** (Mon–Sun) — replaces what daily notes would otherwise be (insufficient writing volume for daily files)
- **Weekly Summary** — what happened, accomplishments
- **Weekly Checklist** — module-grouped tasks (academic week summary, replaces `cs-year-N/16 logs/`)
- **Retro** — carrying forward / letting go (life weekly review)
- **Next week** — plan for the coming week

## Convention

- **Filename:** `<YYYY-WNN>.md` (ISO week — e.g. `2026-W18.md`)
- **Template:** `00 meta/templates/weekly.md`
- **Cadence:** opt-in. Open at start of week to draft checklist (copy from prior week, edit). Add throughout. Close at end with Retro + Next week.

## How to make one

1. Cmd palette → **Templater: Insert template** → `weekly`
2. Save as `<current ISO week>.md`
3. Manually paste/update Weekly Checklist (copy from prior week, edit)

## Recent weeks

```base
filters:
  and:
    - file.inFolder("40 self/periodic/weekly")
views:
  - type: table
    name: Recent
    order:
      - file.name
      - file.mtime
    sort:
      - property: file.name
        direction: DESC
    limit: 20
```
EOF
```

- [ ] **Step 4: Overwrite `40 self/journal/Index.md` with refreshed content**

```bash
cat > "/home/cadrianmae/Documents/MaeNotes/40 self/journal/Index.md" << 'EOF'
---
type: folder-index
date created: 2026-05-05
tags: [moc]
---

# Journal

Wellness journal. Event/mood-triggered, considered (paragraph–essay length), revisited periodically for pattern-finding. Distinct from:

- **Quick captures** (`qcap` → `10 inbox/`) — fleeting thoughts, no narrative
- **Weekly notes** (`40 self/periodic/weekly/`) — structured per-week document

## Convention

- **Filename:** `<YYYY-MM-DD> <Title>.md` (date-prefix sortable + title scannable)
- **Template:** `00 meta/templates/journal.md`
- **Frontmatter:** `mood`, `energy`, `triggers: []`, `tags: [journal, wellness, ...]`
- **Body:** paragraph or essay; freeform inline `#tags`
- **Folder:** flat (no year/mood subfolders unless visually crowded)

## Privacy

Standard `40 self/` privacy — never flips public, but searchable + AI-indexed for pattern-finding.

## How to make one

1. Cmd palette → **Templater: Insert template** → `journal`
2. Save as `<YYYY-MM-DD> <Title>.md`
3. Fill in mood/energy/triggers in frontmatter; write body

## Recent entries

```base
filters:
  and:
    - file.inFolder("40 self/journal")
views:
  - type: list
    name: Recent
    sort:
      - property: file.mtime
        direction: DESC
    limit: 20
```
EOF
```

- [ ] **Step 5: Verify all three Index files exist with correct content**

```bash
for f in "/home/cadrianmae/Documents/MaeNotes/40 self/periodic/Index.md" \
         "/home/cadrianmae/Documents/MaeNotes/40 self/periodic/weekly/Index.md" \
         "/home/cadrianmae/Documents/MaeNotes/40 self/journal/Index.md"; do
  echo "--- $f ---"
  head -3 "$f"
done
```

Expected: each has the proper frontmatter starting with `---`, `type: folder-index`.

---

## Task 7: Migrate existing 16 logs/ content

**Files:**
- Source: `21 computer science/cs-year-{1,2,3,4}/16 logs/*.md`
- Destination: `40 self/periodic/weekly/<YYYY-WNN>.md`

- [ ] **Step 1: Move existing weekly logs**

```bash
cd "/home/cadrianmae/Documents/MaeNotes"
for n in 1 2 3 4; do
  src="21 computer science/cs-year-$n/16 logs"
  if [[ -d "$src" ]]; then
    moved=0
    for f in "$src"/*.md; do
      [[ -f "$f" ]] || continue
      base=$(basename "$f")
      # If filename matches YYYY-WNN.md pattern, move as-is
      if [[ "$base" =~ ^[0-9]{4}-W[0-9]{2}\.md$ ]]; then
        dest="40 self/periodic/weekly/$base"
        if [[ -e "$dest" ]]; then
          echo "  ⚠ collision: $base — manually resolve"
        else
          mv "$f" "$dest"
          ((moved++))
        fi
      else
        echo "  ⚠ non-ISO format in cs-year-$n: $base — needs manual rename"
      fi
    done
    echo "cs-year-$n: $moved file(s) moved"
  fi
done
```

- [ ] **Step 2: Resolve any flagged collisions or non-ISO filenames manually**

If Step 1 reported collisions (same week-N file in multiple years) or non-ISO formats, address each before continuing. Add year-suffix to disambiguate (e.g., `2024-W12.md` vs `2025-W12.md`) — but since filenames already include `YYYY`, true collisions are unlikely.

- [ ] **Step 3: Verify destination has all migrated files**

```bash
ls "/home/cadrianmae/Documents/MaeNotes/40 self/periodic/weekly/" | grep -E "^[0-9]{4}-W[0-9]{2}\.md$" | wc -l
```

Expected: matches sum of files moved per Task 2 inspection.

- [ ] **Step 4: Verify source `16 logs/` folders are empty (or contain only stragglers)**

```bash
for n in 1 2 3 4; do
  d="/home/cadrianmae/Documents/MaeNotes/21 computer science/cs-year-$n/16 logs"
  [[ -d "$d" ]] && echo "cs-year-$n/16 logs/ remaining: $(find "$d" -type f | wc -l) files"
done
```

Expected: 0 files in each (or stragglers explicitly noted in Step 2).

- [ ] **Step 5: Remove empty `16 logs/` folders**

```bash
for n in 1 2 3 4; do
  d="/home/cadrianmae/Documents/MaeNotes/21 computer science/cs-year-$n/16 logs"
  [[ -d "$d" ]] && rmdir "$d" 2>/dev/null && echo "  ✓ removed cs-year-$n/16 logs/"
done
```

If `rmdir` fails for a year, it has remaining content — leave it.

---

## Task 8: Update `21 computer science/cs-year-N/Index.md` files

**Files:**
- Modify: `21 computer science/cs-year-1/Index.md` (if exists)
- Modify: `21 computer science/cs-year-2/Index.md` (if exists)
- Modify: `21 computer science/cs-year-3/Index.md` (if exists)
- Modify: `21 computer science/cs-year-4/Index.md` (if exists)

Note: per-year Index.md files weren't seeded in earlier work — only the parent `21 computer science/Index.md` exists. So this task may be a no-op.

- [ ] **Step 1: Check whether per-year Index files exist**

```bash
for n in 1 2 3 4; do
  ls "/home/cadrianmae/Documents/MaeNotes/21 computer science/cs-year-$n/Index.md" 2>&1
done
```

If none exist: skip the rest of this task. The parent `21 computer science/Index.md` will be updated in Task 9 instead.

- [ ] **Step 2 (if any per-year Index exists): Add pointer**

For each existing per-year Index.md, append (or insert after the brief):

```markdown

## Weekly notes

Academic weekly logs moved to `40 self/periodic/weekly/` (combined with life weekly review). See [[40 self/periodic/weekly/Index|periodic/weekly]].
```

---

## Task 9: Update `21 computer science/Index.md` to point at new weekly location

**Files:**
- Modify: `21 computer science/Index.md`

- [ ] **Step 1: Append weekly-notes pointer to the existing Index**

```bash
python3 << 'EOF'
from pathlib import Path
p = Path("/home/cadrianmae/Documents/MaeNotes/21 computer science/Index.md")
src = p.read_text()
appendix = """

## Weekly notes (relocated)

Academic weekly logs (formerly `cs-year-N/16 logs/`) merged into the combined weekly template at [[40 self/periodic/weekly/Index|40 self/periodic/weekly/]]. One file per ISO week, life + academic combined.
"""
if "Weekly notes (relocated)" not in src:
    p.write_text(src + appendix)
    print("  ✓ pointer added")
else:
    print("  noop: pointer already present")
EOF
```

- [ ] **Step 2: Verify**

```bash
tail -10 "/home/cadrianmae/Documents/MaeNotes/21 computer science/Index.md"
```

Expected: appendix visible.

---

## Task 10: Update Vault Playbook periodic-notes section

**Files:**
- Modify: `40 self/playbook/Vault Playbook.md`

- [ ] **Step 1: Find existing periodic section**

```bash
grep -n "Periodic notes" "/home/cadrianmae/Documents/MaeNotes/40 self/playbook/Vault Playbook.md"
```

Expected: line number of `## Periodic notes (decision: weekly yes, daily no)` heading.

- [ ] **Step 2: Replace the section table to reflect final paths**

The current table references `40 self/weekly-reviews/` (now deleted) and academic logs in `cs-year-N/16 logs/` (now migrated). Update to:

| Want | Do this | Lives at |
|---|---|---|
| Quick thought | `qcap "thought"` | `10 inbox/<YYYY-MM-DD-HHMM>.md` |
| **Weekly note** (combined daily-substitute + retro + plan + academic) | Cmd palette → "Templater: Insert template" → `weekly`. Save as `<YYYY-WNN>.md` | `40 self/periodic/weekly/` |
| **Journal entry** (wellness, event/mood triggered) | Cmd palette → "Templater: Insert template" → `journal`. Save as `<YYYY-MM-DD> <Title>.md` | `40 self/journal/` |
| One-off daily log (rare) | Cmd palette → "Templater: Insert template" → `daily-log` | wherever you create it |
| Monthly / yearly review | No template — write freeform | `40 self/journal/` (or future `40 self/periodic/{monthly,yearly}/`) |
| Install Periodic Notes plugin | **Don't** — explicitly rejected |

Use the Edit tool to replace the existing table block (lines from "## Periodic notes" through the closing `### Distinguishing the three reflection modes` section).

- [ ] **Step 3: Update the "Distinguishing" subsection**

After the table, replace the existing distinguishing list with:

- **`10 inbox/<timestamp>.md`** (qcap) — fleeting, raw, in-the-moment
- **`40 self/journal/<YYYY-MM-DD> <Title>.md`** — wellness, considered, event/mood-triggered
- **`40 self/periodic/weekly/<YYYY-WNN>.md`** — combined weekly: daily-substitute + retro + plan + academic checklist

- [ ] **Step 4: Verify**

```bash
grep -A 2 "Periodic notes" "/home/cadrianmae/Documents/MaeNotes/40 self/playbook/Vault Playbook.md" | head -10
```

Expected: section heading present, no references to `weekly-reviews/` or `cs-year-N/16 logs/`.

---

## Task 11: Commit migration in 21 computer science/ git repo

**Files:**
- Modify (already moved): `21 computer science/cs-year-N/16 logs/*` (deletions)
- Modify: `21 computer science/Index.md`
- Modify (if applicable): `21 computer science/cs-year-N/Index.md`

- [ ] **Step 1: Stage + commit the migration**

```bash
cd "/home/cadrianmae/Documents/MaeNotes/21 computer science"
git add -A
git status --short | head
git commit -m "chore: relocate weekly academic logs to 40 self/periodic/weekly/

Per spec ~/docs/specs/2026-05-05-journal-weekly-workflow.md, weekly
academic logs now combine with life weekly review in a single combined
weekly template at 40 self/periodic/weekly/<YYYY-WNN>.md.

Existing 16 logs/ content for cs-year-{1,2,3,4} migrated to that
location. Empty 16 logs/ folders removed. Index.md updated with
pointer to new weekly location."
```

- [ ] **Step 2: Verify commit**

```bash
cd "/home/cadrianmae/Documents/MaeNotes/21 computer science"
git log --oneline -1
git status
```

Expected: new commit; working tree clean.

---

## Task 12: Final verification

- [ ] **Step 1: All target files exist**

```bash
for f in "00 meta/templates/journal.md" \
         "00 meta/templates/weekly.md" \
         "40 self/journal/Index.md" \
         "40 self/periodic/Index.md" \
         "40 self/periodic/weekly/Index.md"; do
  full="/home/cadrianmae/Documents/MaeNotes/$f"
  [[ -f "$full" ]] && echo "  ✓ $f" || echo "  ✗ MISSING: $f"
done
```

Expected: all 5 ✓.

- [ ] **Step 2: Old templates removed**

```bash
for f in "00 meta/templates/weekly-review.md" "00 meta/templates/review/weekly.md"; do
  full="/home/cadrianmae/Documents/MaeNotes/$f"
  [[ ! -f "$full" ]] && echo "  ✓ deleted: $f" || echo "  ✗ STILL EXISTS: $f"
done
```

Expected: both ✓ deleted.

- [ ] **Step 3: Pre-emptive scaffolding cleaned**

```bash
[[ ! -d "/home/cadrianmae/Documents/MaeNotes/40 self/weekly-reviews" ]] && echo "  ✓ weekly-reviews/ removed" || echo "  ✗ STILL EXISTS"
```

Expected: `✓ weekly-reviews/ removed`.

- [ ] **Step 4: Migration count check**

```bash
mig=$(find "/home/cadrianmae/Documents/MaeNotes/40 self/periodic/weekly/" -name "*.md" -not -name "Index.md" | wc -l)
echo "  files in periodic/weekly/: $mig (excluding Index.md)"
remaining=$(find "/home/cadrianmae/Documents/MaeNotes/21 computer science/cs-year-"*/16\ logs/ -name "*.md" 2>/dev/null | wc -l)
echo "  files remaining in 16 logs/: $remaining"
```

Expected: `mig` matches the source count from Task 2; `remaining` is 0.

- [ ] **Step 5: Vault Playbook references final paths**

```bash
grep -E "weekly-reviews|16 logs" "/home/cadrianmae/Documents/MaeNotes/40 self/playbook/Vault Playbook.md"
```

Expected: empty (no stale references).

- [ ] **Step 6: Per-spec success criteria check**

Walk the success criteria from spec §7:
- [x] Journal template exists at `00 meta/templates/journal.md`
- [x] Weekly template exists at `00 meta/templates/weekly.md`
- [x] Existing academic weekly logs migrated
- [x] `cs-year-N/16 logs/` folders empty/removed
- [x] Old weekly templates deleted
- [x] Two new Index files exist (`periodic/Index.md`, `periodic/weekly/Index.md`)
- [x] Vault Playbook updated

---

## Wrap-up

**What's done after this plan executes:**
- Two opt-in workflows live: `40 self/journal/` (wellness) + `40 self/periodic/weekly/` (combined weekly)
- One unified weekly template replaces two old ones
- Existing academic weekly logs relocated to combined weekly home
- Vault Playbook reflects the new locations
- `21 computer science/` repo has migration commit

**What's deferred (out of spec scope):**
- Monthly / yearly templates (no use case yet)
- Mood-pattern Bases dashboards (need entry volume first)
- Templater script for auto-generating weekly checklist (manual approach is fine)
- Voice memo / paper journal transcription (continues parallel, not migrated)
