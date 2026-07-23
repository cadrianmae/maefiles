# Journal + Weekly Notes Workflow

- **Author:** cadrianmae
- **Date:** 2026-05-05
- **Status:** Design approved
- **Related:**
  - `~/docs/specs/2026-05-04-maenotes-vault-design.md` — parent vault design (anti-ritual ethos, "stream is the artifact")
  - `~/Documents/MaeNotes/40 self/playbook/Vault Playbook.md` — reference workflows

## 1. Context

MaeNotes vault has a rejection-by-design of daily/weekly/monthly/yearly periodic-note rituals (spec §6.0). The vault uses `qcap` → `10 inbox/<YYYY-MM-DD-HHMM>.md` per-thought captures as the journal substitute.

After running the vault for a few days, two distinct reflection workflows surfaced that don't fit the per-thought-capture model:

1. **Wellness journal** — event/mood-triggered, considered, paragraph-to-essay length writing
2. **Weekly notes** — combined daily-substitute + retro/plan + academic week summary, replacing the old `cs-year-N/16 logs/` academic logs

Both opt-in to structure (folder + filename convention + template) without re-introducing periodic-notes plugins.

## 2. Decisions

### 2.1 Journal

| Decision | Choice | Rationale |
|---|---|---|
| Folder | `40 self/journal/` (flat) | Wellness content fits 40 self/; flat avoids per-year/per-mood maintenance |
| Filename | `<YYYY-MM-DD> <Title>.md` | Date-prefix for chronological browsing + title for scannability |
| Frontmatter | `mood`, `energy`, `triggers: []`, `tags: [journal, wellness, ...]` | Enables Bases pattern-finding; supports user's "revisit for patterns" use case |
| Body | Free paragraph/essay; freeform inline `#tags` | Matches considered-writing intent (paragraph to essay length) |
| Privacy | Standard (40 self/ private-by-default per spec §3.1) | No extra encryption — keeps Copilot semantic search functional |
| Folder org as content grows | Flat indefinitely; revisit only if visually crowded | Spec ethos: don't pre-optimize organization |

### 2.2 Weekly notes

| Decision | Choice | Rationale |
|---|---|---|
| Folder | `40 self/periodic/weekly/` | Room to add `40 self/periodic/{monthly,yearly}/` later if/when needed |
| Filename | `<YYYY-WNN>.md` (ISO week, e.g. `2026-W18.md`) | Sortable, unambiguous, plugin-compatible |
| Replaces | `cs-year-{1..4}/16 logs/` weekly academic logs | One file per week now combines academic + life |
| Combines | Per-day timestamped notes + Weekly Summary + Module Checklist + Retro + Next week plan | Encompasses what would otherwise be daily notes (low writing volume), retro, plan, and academic log |
| Checklist source | Manual (copy-paste from prior week, edit as schedule changes) | Avoids Templater script maintenance; transparent; weekly retro pattern means user opens last week's anyway |

### 2.3 Migration

Move all existing `21 computer science/cs-year-{1,2,3,4}/16 logs/*.md` content into `40 self/periodic/weekly/`.

**Pre-migration inspection required:** verify each year's filenames. cs-year-4 confirmed using `<YYYY-WNN>.md` format. Year 1-3 may use older formats — rename to ISO week format on migration if needed.

After migration: leave `16 logs/` folders empty (or `rmdir` if Folder Notes plugin doesn't require them). Update `21 computer science/cs-year-N/Index.md` files to point at `40 self/periodic/weekly/` for academic weekly logs.

### 2.4 Template reconciliation

Two existing weekly templates merge into one new combined template:

| Old template | Fate |
|---|---|
| `00 meta/templates/weekly-review.md` (life retro: carrying / letting go) | **Merged into new combined template, then deleted** |
| `00 meta/templates/review/weekly.md` (academic per-day with Mon-Sun structure) | **Merged into new combined template, then deleted** |

New unified template at `00 meta/templates/weekly.md`.

## 3. Templates

### 3.1 Journal template

`00 meta/templates/journal.md`:

```markdown
---
type: journal
date: <% tp.date.now("YYYY-MM-DD") %>
mood: 
energy: 
triggers: []
tags: [journal, wellness]
---
# <% tp.file.title %>


```

Usage: Templater → Insert template → `journal`. Save as `<YYYY-MM-DD> <Title>.md` in `40 self/journal/`. (Date pre-fills from Templater; user types title manually.)

### 3.2 Weekly template

`00 meta/templates/weekly.md`:

```markdown
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
```

Usage: Templater → Insert template → `weekly`. Save as `<YYYY-WNN>.md` in `40 self/periodic/weekly/`. Manually paste/update Weekly Checklist by copying from prior week.

## 4. Index files

### `40 self/journal/Index.md`

Brief + recent-entries Bases query. Already exists.

### `40 self/periodic/weekly/Index.md`

Brief + recent-weeks Bases table. To create.

### `40 self/periodic/Index.md`

Light parent index pointing to weekly/ subfolder; placeholder for monthly/yearly if added later. To create.

## 5. Anti-rituals (still hold)

- Daily Notes core plugin: stays **off**
- Periodic Notes community plugin: stays **uninstalled**
- Weekly notes are **opt-in** (user creates when ready, not on schedule)
- Journal entries are **event/mood triggered**, not periodic
- Existing `16 logs/` content migrates **once**; new entries always to `40 self/periodic/weekly/` going forward

## 6. Out of scope

- Monthly / yearly templates (defer until use case emerges)
- Mood-pattern Bases dashboards (defer; build when there's enough data to spot patterns)
- Templater script for auto-generating weekly checklist from current modules (manual is fine; revisit if pain emerges)
- Journal-mood-by-month visualizations
- Journal entry promotion workflows (e.g., turning a journal entry into a permanent self-knowledge note)
- Voice memo / paper journal transcription into vault (paper + voice continue parallel; not migrating)

## 7. Success criteria

- Journal entry can be created with one Templater invocation + manual title; lands in `40 self/journal/`
- Weekly note can be created with one Templater invocation; lands in `40 self/periodic/weekly/`
- Existing academic weekly logs from cs-year-{1..4} all relocated to `40 self/periodic/weekly/`
- `cs-year-N/16 logs/` folders are empty (or removed)
- Old weekly templates deleted; only new combined `weekly.md` template remains
- Two new Index files exist (`periodic/Index.md`, `periodic/weekly/Index.md`)
- Vault Playbook updated to reflect new locations + workflows
