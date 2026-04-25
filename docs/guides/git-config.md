# Git configuration

Personal `.gitconfig` plus a templating directory that initialises every new repo with a conventional-commit message template, sane ignore rules, and a soft-warn `commit-msg` hook.

## Layout

| File | Purpose |
|---|---|
| `~/.gitconfig` | Global config — user identity, GitHub credential helper (`gh`), GPG signing, init template dir |
| `~/.config/git/ignore` | Global ignore patterns applied to every repo |
| `~/.config/git/template/` | Template dir copied into `.git/` on `git init` (configured via `init.templateDir`) |
| `~/.config/git/template/commit-template.txt` | Conventional-commits scaffold opened on `git commit` (no `-m`) |
| `~/.config/git/template/hooks/commit-msg` | Soft validator — warns if the message doesn't match the conventional format |
| `~/.config/git/template/description` | Default repo description placeholder |

## `~/.gitconfig`

| Section | Setting | Notes |
|---|---|---|
| `[user]` | `name`, `email`, `signingkey` | Email uses GitHub's noreply alias for privacy |
| `[init]` | `defaultBranch = main` · `templateDir = ~/.config/git/template` | New repos start on `main`, get the template dir |
| `[commit]` | `template = …/commit-template.txt` · `gpgsign = true` | Sign every commit with the same GPG key gating `pass` and yadm-encrypt |
| `[credential "https://github.com"]` | `helper = !/usr/bin/gh auth git-credential` | Hand off auth to `gh` — no PATs in `~/.git-credentials` |
| `[credential "https://gist.github.com"]` | same | Same flow for gists |
| `[filter "lfs"]` | `clean` / `smudge` / `process` / `required = true` | Standard git-lfs filter |

## Commit template

```text
# <type>(<scope>): <subject> (max 50 chars)
# |<----  Using a Maximum Of 50 Characters  ---->|

# Explain why this change is being made
# |<----   Try To Limit Each Line to a Maximum Of 72 Characters   ---->|

# Provide links or keys to any relevant tickets, articles or resources
# Example: Fixes #23

# --- COMMIT END ---
# Type can be:
#    feat     (new feature)
#    fix      (bug fix)
#    refactor (refactoring code)
#    style    (formatting, missing semi colons, etc)
#    docs     (changes to documentation)
#    test     (adding or refactoring tests)
#    chore    (maintain)
```

The 50/72-character ruler matches GitHub's display constraints.

## `commit-msg` hook (soft validation)

Warns but does not block:

```bash
if ! echo "$commit_msg" | grep -qE "^(feat|fix|docs|style|refactor|test|chore)(\([a-z0-9-]+\))?:"; then
    echo "[WARNING] Non-conventional commit message"
    echo "Expected: <type>(scope): subject"
    echo "Example: feat(api): add endpoint"
fi
exit 0
```

Hard-block enforcement is opt-in per-repo via `pre-commit` (see `.pre-commit-config.yaml` in this repo for the full leak-scan + shellcheck pipeline).

## Activation

`init.templateDir` makes the template dir copy on every `git init`. **Existing** repos don't pick it up automatically — run:

```bash
cd path/to/existing/repo
git init   # idempotent; copies in missing template files
```

…or symlink the hook by hand:

```bash
ln -s ~/.config/git/template/hooks/commit-msg .git/hooks/commit-msg
```

## Related

- [Git aliases reference](../reference/git-aliases.md) — the oh-my-zsh `git` plugin alias set
- [GPG key recovery](../runbooks/gpg-key-recovery.md) — losing the signing key
- [ADR 003 — claude-config deferred](../decisions/003-claude-config-deferred.md) — separate-repo strategy
