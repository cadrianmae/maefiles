# Runbook — publish claude-config to private GitHub repo

Executes the PII cleanup + push for `~/.claude/.git`, then wires it into
yadm as a submodule. Until this runbook completes, `~/.claude/.git`
stays local-only (see [ADR 003](../decisions/003-claude-config-deferred.md)).

## Pre-flight

```bash
# Confirm we're in the deferred state (no remote yet)
cd ~/.claude && git remote -v
# expected: (empty)

# Check current PII footprint
~/bin/pii-scan ~/.claude/CLAUDE.md ~/.claude/memory.md ~/.claude/rules/
```

## Step 1 — Add missing identifiers to BWS + pass

Pending secrets to add to Bitwarden Secrets Manager's `maefiles` project:

| BWS secret name | env var | pass path | Source |
|---|---|---|---|
| `student-id` | `STUDENT_ID` | `academic/student-id` | your student card |
| `name-full` | `MAE_NAME_FULL` | `identity/name-full` | legal name |
| `name-first` | `MAE_NAME_FIRST` | `identity/name-first` | first name |

Add these to `~/docs/secret/manifest.yaml` with `ttl: never`.

Run `~/.config/yadm/bootstrap --only=academic/*` + `--only=identity/*`
to seed them.

## Step 2 — Template the PII-heavy files

Convert each file with PII into `##template.esh` alongside:

```
CLAUDE.md           →  CLAUDE.md##template.esh
rules/academic.md   →  rules/academic.md##template.esh
```

Replace literal identifiers with esh variables that read from `pass`:

- `<your-student-number>` → `<%= pass show academic/student-id %>`
- `<your-legal-name>` → `<%= pass show identity/name-full %>`
- `<your-first-name>` (as a standalone first-name use) → `<%= pass show identity/name-first %>`

Careful: your first name appears in many places as part of prose/context,
not as an identifier. Only template occurrences that are structurally an
identifier (headers, "Name: ..." fields, example CLI signatures).

### Decision point — neurodivergence rules

`rules/neurodivergence.md` and `rules/me/neurodivergence.md` contain
medical prose that can't be scrubbed without losing meaning. Three
options:

1. **Keep in repo, accept privacy via access control.** Private repo +
   2FA is the mitigation. Realistic for single-user threat model.
2. **Move to a separate git-crypted sub-scope** in claude-config.
   Works, but reintroduces the SNDL concern ADR 003 was trying to
   avoid.
3. **Move out of git entirely.** Keep these on local disk only, sync
   manually between machines.

Default: **option 1**. Document the exception here.

## Step 3 — Post-alt hook for claude-config templates

Currently `post_alt` renders `.env##template.esh` via `bin/render-env`.
Claude-config templates live inside the submodule, so we need a
submodule-aware render step:

1. Extend `bin/render-env` to accept a `--root` flag (or add a new
   `bin/render-claude` wrapper).
2. Update `.config/yadm/hooks/post_alt` to call the new renderer for
   any `##template.esh` files under `~/.claude/`.
3. Ensure rendered outputs are `.gitignore`'d in claude-config so the
   templates stay the source of truth.

## Step 4 — Re-verify PII-free

```bash
# After templating, confirm no more PII matches in committed files
cd ~/.claude
git add -A
~/bin/pii-scan --staged

# Should report: no matches
```

## Step 5 — Create private GitHub repo + push

```bash
cd ~/.claude
gh repo create cadrianmae/claude-config \
  --private \
  --description "Mae's personal Claude Code config" \
  --source=. \
  --remote=origin \
  --push
```

## Step 6 — Convert to yadm submodule

```bash
cd ~

# Remove the ignore rule for .claude/
sed -i '/^\.claude\/$/d' ~/.gitignore
# (Also remove the comment block explaining the ignore, lines 21-24 of .gitignore)

# Add as submodule
yadm submodule add https://github.com/cadrianmae/claude-config .claude

# Configure low-cognitive-load mode (branch tracking, merge update)
# Edit ~/.gitmodules:
#   [submodule ".claude"]
#     path = .claude
#     url = https://github.com/cadrianmae/claude-config
#     branch = main
#     update = merge

yadm add .gitmodules .gitignore .claude
yadm commit -m "feat(claude): convert claude-config from local-only to yadm submodule"
yadm push
```

## Step 7 — Supersede ADR 003

Create `docs/decisions/004-claude-config-submodule.md`:

- Mark ADR 003 as superseded
- Document the now-live submodule setup
- Cross-reference this runbook

## Verification

```bash
# On this machine: nothing should have changed functionally
ls ~/.claude/CLAUDE.md            # still there
source ~/.zshrc                   # still loads
cat ~/.claude/rules/academic.md   # rendered from template

# On a fresh machine simulation
yadm clone <url>
yadm submodule update --init --remote
# claude-config materialises at ~/.claude with latest main
```

## Rollback

If anything breaks during step 6:

```bash
cd ~
yadm submodule deinit -f .claude
yadm rm -f .claude
# Restore the .gitignore line
echo '.claude/' >> ~/.gitignore
yadm commit -m "revert claude-config submodule"
```

`~/.claude/.git` (local repo) is untouched by the rollback.
