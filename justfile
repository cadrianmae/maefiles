# maefiles — top-level task runner.
# Run `just` (no args) for the menu.

set shell := ["bash", "-eu", "-c"]

# Default: show available recipes.
default:
    @just --list --unsorted

_yadm_repo := env_var('HOME') + '/.local/share/yadm/repo.git'
_build_wt  := env_var('HOME') + '/.cache/maefiles-build'

# Serve docs locally with live reload (http://127.0.0.1:7700).
# Port 7700 chosen to sit near Sol (7777) in the personal-infra range,
# clear of common dev defaults (3000/4200/5000/5173/8000/8080/8888).
# Note: mkdocs serve falls back to build-date for "Last update" since the
# plugin can't see yadm's repo from $HOME. Accurate dates only on `docs-build`.
docs-serve:
    mkdocs serve --dev-addr 127.0.0.1:7700

# Serve the static built site (.site/) with live-reload via live-server.
# Use this when you want to preview the production build with real
# git-revision dates rendered. Run `just docs-build` first.
docs-preview:
    npx --yes live-server --host=127.0.0.1 --port=7700 --no-browser ~/.site

# Build the static site into .site/ (strict — fails on warnings).
# Spawns a throwaway git worktree so the revision-date plugin can read
# real commit history (yadm's repo isn't reachable from $HOME directly).
docs-build:
    #!/usr/bin/env bash
    set -euo pipefail
    rm -rf "{{_build_wt}}"
    git --git-dir="{{_yadm_repo}}" --work-tree="$HOME" \
        -c filter.git-crypt.smudge=cat \
        -c filter.git-crypt.clean=cat \
        -c filter.git-crypt.required=false \
        worktree add --detach "{{_build_wt}}" >/dev/null
    trap 'git --git-dir="{{_yadm_repo}}" worktree remove --force "{{_build_wt}}" >/dev/null 2>&1 || true' EXIT
    # Overlay any working-tree edits (uncommitted) onto the worktree so
    # `just docs-build` reflects what you see, not just what's committed.
    yadm diff --name-only HEAD -- mkdocs.yml docs/ 2>/dev/null | while read -r f; do
        [[ -f "$HOME/$f" ]] && cp "$HOME/$f" "{{_build_wt}}/$f"
    done
    cd "{{_build_wt}}"
    mkdocs build --strict --site-dir "$HOME/.site"

# Scaffold a new ADR. Usage: just new-adr "title here"
new-adr title:
    ~/bin/new-adr "{{title}}"

# Scaffold a new runbook. Usage: just new-runbook "verb noun"
new-runbook title:
    ~/bin/new-runbook "{{title}}"

# Audit secrets manifest ↔ pass alignment.
audit:
    ~/bin/yadm-audit

# Check secret freshness against TTLs.
staleness:
    ~/bin/yadm-check-staleness

# Verify git-crypt scope covers everything sensitive.
verify-encryption:
    ~/bin/yadm-verify-encryption

# All health checks in sequence.
health: audit staleness verify-encryption
