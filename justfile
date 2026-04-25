# maefiles — top-level task runner.
# Run `just` (no args) for the menu.

set shell := ["bash", "-eu", "-c"]

# Default: show available recipes.
default:
    @just --list --unsorted

# Serve docs locally with live reload (http://127.0.0.1:8000).
docs-serve:
    mkdocs serve

# Build the static site into .site/ (strict — fails on warnings).
docs-build:
    mkdocs build --strict

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
