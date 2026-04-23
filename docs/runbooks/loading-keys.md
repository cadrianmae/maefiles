# Runbook — loading API keys into your shell

Keys live in `pass`. They enter your shell on demand via three patterns,
ranked from ad-hoc to persistent.

## Pattern 1 — `env-key load` (ad-hoc, single shell)

```bash
env-key load api/anthropic        # → exports ANTHROPIC_API_KEY in current shell
env-key load api                  # → all pass entries under api/
env-key load 'api/*'              # → glob variant
env-key list                      # → show all pass entries + which are loaded
env-key clear api/anthropic       # → unset one
env-key clear                     # → unset all loaded via env-key
```

Convention: `pass show api/foo` → `FOO_API_KEY`.

Good for: one-off shell sessions where you need the keys briefly.

## Pattern 2 — `direnv` `.envrc` per project (auto-load on cd)

For any project directory that regularly needs keys, drop an `.envrc`:

```bash
# example: ~/Documents/my-project/.envrc
env-key load api/anthropic
env-key load api/mistral
```

Then `direnv allow` (one-time per machine). After that, every `cd` into
the directory loads the keys into your shell automatically; `cd` away
unsets them.

**Security model:** keys are only in env while you're *in the project
dir*. Leaving the dir clears them.

Good for: projects where you want keys always available, scoped to the
project's working tree.

### Checklist to set up direnv in a new project

```bash
cd ~/my-project
cat > .envrc <<'EOF'
env-key load api/anthropic
EOF
direnv allow .
```

Add `.envrc` to that project's `.gitignore` if the file contents reveal
which keys you use (minor info leakage).

## Pattern 3 — Auto-load at every shell start (opt-in)

Not enabled by default (per ADR design). If you want every shell to have
all keys, regardless of directory:

```bash
# 1. Generate the env template from the manifest
~/bin/render-env

# 2. Edit .zshrc, add near the bottom:
[ -f ~/.env ] && source ~/.env

# 3. Re-open shell to test
```

Trade-off:
- Every new shell runs `pass show` × N (cheap with cached gpg-agent; prompts
  pinentry once per 12 h cycle).
- Keys are always in env whenever any tool reads them (good for scripts,
  bad if you want scoping).

## Which pattern for what

| Workflow | Pattern |
|---|---|
| "I'm running one Claude Code session and need $ANTHROPIC_API_KEY once" | 1 (`env-key load`) |
| "This project always uses OpenAI and Mistral" | 2 (direnv `.envrc`) |
| "I want keys available in every shell, always" | 3 (auto-load) |

## gpg-agent caching — how often you get prompted

With `default-cache-ttl 43200` and `max-cache-ttl 43200` in
`~/.gnupg/gpg-agent.conf`:

- First `pass show` of the day (or after 12 h inactivity) → pinentry
  prompt via `pinentry-qt` (KDE dialog).
- All subsequent `pass show` calls for 12 h → instant, silent.
- Reboot → next `pass show` prompts again.

Applies to all three patterns above.

## Troubleshooting

### `pass show api/foo` fails silently

Agent is locked + pinentry can't pop a dialog (no graphical session, or
`pinentry-qt` isn't installed). Test with `echo 'test' | gpg --clearsign`
to see the pinentry error.

### `env-key load api/foo` prints "pass entry not found"

- Check `pass ls` actually shows `api/foo`
- Check zsh doesn't have `$path` shadowing (we fixed this in env-key's
  local var name; shouldn't happen now)

### Direnv doesn't load `.envrc`

- Did you run `direnv allow .` after creating/modifying the file?
- Is the direnv hook loaded in your shell? Check `.zshrc` for
  `eval "$(direnv hook zsh)"` — it's there on line ~156.

### I want to see which keys are currently loaded

```bash
env-key list
```

`*` prefix marks loaded-in-this-shell entries.
