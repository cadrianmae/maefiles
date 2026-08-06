#!/usr/bin/env bash
# Re-upload only the files `home-backup verify` reported missing.
#
# Pointing the CLI at the whole directory means it re-walks every file to
# decide what to skip, which for Games is 16,000 round trips before it reaches
# any real work. This copies just the missing files into a temporary tree that
# mirrors their layout, then uploads that tree with -d merge, so the remote
# structure is preserved and only the stragglers move.
#
#   retry-missing.sh Games
#   DRY_RUN=1 retry-missing.sh Games      show what would be sent, send nothing

set -uo pipefail

readonly PD="$HOME/.local/bin/proton-drive"
readonly REMOTE="/my-files/backup-2026-08-03"
readonly FAILURES="${XDG_STATE_HOME:-$HOME/.local/state}/home-backup/failures.tsv"
DRY_RUN="${DRY_RUN:-0}"

DIR="${1:-}"
[[ -n "$DIR" ]] || { echo "usage: ${0##*/} <PlainDir>   e.g. Games" >&2; exit 2; }
[[ -f "$FAILURES" ]] || { echo "no failures recorded at $FAILURES" >&2; exit 1; }

STAGE=$(mktemp -d "${TMPDIR:-/tmp}/retry-missing.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT

staged=0 skipped_link=0 skipped_gone=0
# sort -u because verify appends, so a file can be recorded by several runs.
while IFS=$'\t' read -r _ _ path _; do
    [[ "$path" == "$DIR/"* ]] || continue
    src="$HOME/$path"
    if [[ -L "$src" ]]; then
        skipped_link=$((skipped_link + 1)); continue     # dangling Wine devices etc
    fi
    if [[ ! -f "$src" || ! -s "$src" ]]; then
        skipped_gone=$((skipped_gone + 1)); continue     # absent, or zero bytes
    fi
    rel="${path#"$DIR"/}"
    mkdir -p "$STAGE/$(dirname "$rel")"
    cp -a "$src" "$STAGE/$rel" && staged=$((staged + 1))
done < <(sort -u "$FAILURES")

printf 'staged   %d file(s)\n' "$staged"
printf 'skipped  %d symlink(s), %d absent or empty\n' "$skipped_link" "$skipped_gone"
(( staged )) || { echo "nothing to send"; exit 0; }

printf 'bytes    %s\n\n' "$(du -sh "$STAGE" | cut -f1)"

if (( DRY_RUN )); then
    echo "[dry-run] would upload these trees into $REMOTE/$DIR:"
    find "$STAGE" -mindepth 1 -maxdepth 1 -printf '  %P\n'
    exit 0
fi

shopt -s dotglob
rc=0
for entry in "$STAGE"/*; do
    [[ -e "$entry" ]] || continue
    echo ">> ${entry##*/}"
    "$PD" filesystem upload -f skip -d merge "$entry" "$REMOTE/$DIR" || rc=1
done
exit "$rc"
