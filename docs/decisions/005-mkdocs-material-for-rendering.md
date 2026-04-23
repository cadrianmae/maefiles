# ADR 005 — MkDocs + Material for docs rendering

- **Status:** planned (execution deferred to post-Phase-4 soak)
- **Date:** 2026-04-23

## Context

`~/docs/` has grown to 11 files across architecture, ADRs, and runbooks.
GitHub renders each markdown file individually but gives weak
cross-doc experience: no search, no nav tree, no rendered mermaid
diagrams in preview, no templates when starting a new doc.

Requirements from brainstorming:

| Requirement | Priority |
|---|---|
| Full-text search across docs | yes |
| Mermaid + syntax-highlighted code blocks | yes |
| Auto nav / cross-linking / ToC | yes |
| ADR & runbook scaffolding templates | yes |
| Site lives **inside** maefiles | yes |
| Local-only now; grow to shareable/public later | yes |

## Decision

**Use MkDocs + Material theme.** It covers every requirement above
with a single `mkdocs.yml` + existing `docs/` structure. Stays local
via `mkdocs serve`; deployable to GH Pages later with one Action.

## Alternatives considered

- **mdBook** — good for linear "book" reading; weaker search; no native
  mermaid without a preprocessor
- **Docusaurus** — overkill for personal dotfiles; React/Node stack
- **Quartz** (Obsidian → site) — rejected because docs stay inside
  maefiles, not the Obsidian vault
- **Custom viewer** (extend our `markdown-tabs` tool) — no search; we'd
  reinvent what MkDocs already does

## Implementation plan (deferred)

1. Add `mkdocs.yml` at `~/` (in the yadm tree) configuring:
   - Theme: Material
   - Plugins: `awesome-pages`, `search` (built-in), `mermaid2` or
     `pymdownx.superfences` with mermaid custom-fence
   - Extensions: `pymdownx.highlight`, `pymdownx.inlinehilite`,
     `pymdownx.snippets`, `toc`, `tables`, `admonition`
   - Navigation: auto-derive from directory structure
   - Exclude `docs/secret/**` (git-crypted; not renderable)
2. `bin/new-adr` — given a title, create
   `docs/decisions/NNN-kebab-title.md` with status/date/sections
3. `bin/new-runbook` — same for `docs/runbooks/`
4. `Makefile` at `~/` with `docs-serve`, `docs-build`, `docs-new-adr`
5. (Deferred deferral) GH Action: `mkdocs-deploy.yml` — runs on push,
   pushes to `gh-pages` branch. Initially disabled.

## Dependencies

- `mkdocs` + `mkdocs-material` + extras — install via `pip install
  --user` (no sudo, no system-wide pollution)
- Should add these to the install.sh flow as optional `--with-docs`
  flag OR as a separate `~/bin/setup-docs` install step

## Consequences

### Advantages

- Renders the existing docs as-is — no restructuring required
- Search + mermaid + nav solved together in one tool
- `mkdocs serve` gives a local dev loop (~500ms incremental)
- Migration path to public hosting is one GH Action away

### Disadvantages

- Python dependency (mkdocs stack ~50 MB with plugins)
- Another tool to learn, though the config is well-documented
- Can't render `docs/secret/**` (git-crypted); acceptable — secret
  docs shouldn't be in the site anyway

## Timing

Execute after Phase 4 soak completes (the 24h hands-off window for the
yadm migration). Approximate effort: 30-60 min for initial config +
templates.

## Related

- ADR 001: yadm choice (frames the whole repo)
- Backlog: `project_documentation_tools` memory (preliminary research)
