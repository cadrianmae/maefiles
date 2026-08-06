#!/usr/bin/env bash
# Capture local work living inside third-party clones as applyable patches.
#
# Those repos get re-cloned rather than restored — git-slim shallowed 30 of
# them, so a fresh clone is strictly better than the backed-up copy. But that
# would discard the notes, drafts and specs written inside them. A patch keeps
# the upstream pristine and carries the work on top.
#
# Two sources, because `git diff` alone sees neither:
#   - modified tracked files      -> git diff HEAD
#   - untracked files             -> git diff --no-index against /dev/null
#
# Deletions are skipped. They are almost entirely git-slim artefacts, not
# intentional removals, and one repo alone has 2,850 of them.
#
#   save-thirdparty-patches.sh [outdir]

set -uo pipefail

readonly GITROOT="$HOME/git"
OUT="${1:-$HOME/reinstall-kit/2026-08-03/third-party-patches}"

mkdir -p "$OUT"
rm -f "$OUT"/*.patch

total=0 repos=0

while IFS= read -r gitdir; do
    repo="${gitdir%/.git}"
    rel="${repo#"$GITROOT"/}"
    case "$rel" in *cadrianmae*) continue ;; esac

    # Modified tracked files only; deletions and mode changes are dropped.
    modified=$(git -C "$repo" diff --name-only --diff-filter=M HEAD 2>/dev/null)
    untracked=$(git -C "$repo" ls-files --others --exclude-standard 2>/dev/null)
    [[ -n "$modified$untracked" ]] || continue

    patch="$OUT/$(printf '%s' "$rel" | tr '/' '_').patch"
    {
        printf '# repo:   %s\n' "$rel"
        printf '# origin: %s\n' "$(git -C "$repo" remote get-url origin 2>/dev/null)"
        printf '# branch: %s\n' "$(git -C "$repo" rev-parse --abbrev-ref HEAD 2>/dev/null)"
        printf '# apply:  git apply <this file>\n#\n'

        if [[ -n "$modified" ]]; then
            # Read into an array so a filename containing a space survives.
            mapfile -t mod_files <<< "$modified"
            git -C "$repo" diff --binary --diff-filter=M HEAD -- "${mod_files[@]}" 2>/dev/null
        fi
        # --no-index exits 1 when files differ, which is the normal case here.
        while IFS= read -r f; do
            [[ -n "$f" ]] || continue
            ( cd "$repo" && git diff --binary --no-index /dev/null "$f" 2>/dev/null )
        done <<< "$untracked"
    } > "$patch"

    n_mod=$(grep -c . <<< "${modified:-}")
    n_unt=$(grep -c . <<< "${untracked:-}")
    printf '%-52s %2s modified  %2s untracked  %s\n' \
        "$rel" "$n_mod" "$n_unt" "$(du -h "$patch" | cut -f1)"
    repos=$((repos + 1))
    total=$((total + n_mod + n_unt))
done < <(find "$GITROOT" -maxdepth 5 -type d -name .git 2>/dev/null | sort)

printf '\n%d file(s) captured across %d repo(s), %s total\n' \
    "$total" "$repos" "$(du -sh "$OUT" | cut -f1)"
printf 'patches in %s\n' "$OUT"
