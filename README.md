# maefiles

Personal `$HOME` configuration for `cadrianmae` on Fedora 43 — managed by [yadm](https://yadm.io), with secrets backed by Bitwarden Secrets Manager + `pass`, and per-file encryption via `git-crypt`.

## Browse the docs

The full documentation site renders from `docs/` via [MkDocs + Material](https://squidfunk.github.io/mkdocs-material/):

```bash
just docs-serve   # http://127.0.0.1:7700
```

| Section | Contents |
|---|---|
| [Architecture](docs/architecture.md) | Three-layer secret flow, encryption boundaries |
| [ADRs](docs/decisions/) | Decision records — yadm, BWS, git-crypt scope, MkDocs choice, footguns |
| [Runbooks](docs/runbooks/) | New machine, rotate secret, recovery, GPG key recovery, Fedora upgrade |
| [Guides](docs/guides/) | Shell, KDE Plasma, Niri, pomodoro timer, memory management |
| [Reference](docs/reference/) | CLI tools, git aliases, env vars, file locations |
| [Specs](docs/specs/) | Original brainstorm artefacts (visual summary, full design spec) |

## Quick starts

- **New machine:** clone with yadm, run the bootstrap. See [docs/runbooks/new-machine.md](docs/runbooks/new-machine.md).
- **Day-to-day commands:** `just` for the menu (`docs-serve`, `audit`, `staleness`, `verify-encryption`, `health`, `new-adr`, `new-runbook`).
- **Cleanup queue:** files queued for "revisit later" decisions live in `docs/cleanup/queue.yaml`; query with `cleanup-review`.

## Repo conventions

- ADRs: `docs/decisions/NNN-kebab-title.md`
- Runbooks: `docs/runbooks/<verb>-<noun>.md`
- Anything under `docs/secret/**` is git-crypted and excluded from the rendered site

## Related

- `~/.claude/` is in its own (currently local-only) repo per [ADR 003](docs/decisions/003-claude-config-deferred.md).
- The neovim config lives at `~/.config/nvim/` as a tracked submodule.
