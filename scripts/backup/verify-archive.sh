#!/usr/bin/env bash
# Download the archive from Proton and prove it restores.
#
# The archive was verified locally before upload (1,042,824 entries) and all 50
# parts are confirmed present at the right sizes. What has never been tested is
# the round trip: download, reassemble, decompress, read. Staging is deleted, so
# there is no local copy to compare against — the entry count is the proof.
#
# Resumable: parts already downloaded at the right size are skipped, so it can
# be interrupted and re-run freely.
#
#   verify-archive.sh              download then verify
#   verify-archive.sh --verify     skip download, verify what is on disk
#   verify-archive.sh --clean      delete the downloaded parts

set -uo pipefail

readonly PD="$HOME/.local/bin/proton-drive"
readonly REMOTE="/my-files/backup-2026-08-03"
readonly DEST="$HOME/restore-verify"
readonly EXPECTED_ENTRIES=1042824
# split -b 2G; every part but the last is exactly this.
readonly SPLIT_BYTES=2147483648
readonly LOG="${XDG_STATE_HOME:-$HOME/.local/state}/home-backup/verify-archive.log"

mkdir -p "$DEST" "$(dirname "$LOG")"
say() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "$LOG"; }

case "${1:-}" in
    --clean) rm -f "$DEST"/home.tar.zst.part-*; say "removed downloaded parts"; exit 0 ;;
esac

# --- what the remote holds ---------------------------------------------------
say "reading remote manifest"
manifest=$("$PD" filesystem list -t file --json "$REMOTE" 2>/dev/null \
    | jq -r '.[] | select(.name.ok)
                 | select(.name.value|startswith("home.tar.zst.part-"))
                 | "\(.name.value)\t\(.totalStorageSize)"' | sort)
n_remote=$(grep -c . <<< "$manifest")
[[ "$n_remote" -eq 50 ]] || { say "ERROR: expected 50 parts on remote, found $n_remote"; exit 1; }
say "remote has $n_remote parts"
# shellcheck disable=SC2154  # assigned just above; shellcheck loses it across the heredoc
last_part=$(awk -F'\t' '{print $1}' <<< "$manifest" | tail -1)

if [[ "${1:-}" != "--verify" ]]; then
    # --- space -----------------------------------------------------------------
    need=$(awk -F'\t' '{s+=$2} END{print int(s/1073741824)+5}' <<< "$manifest")
    free=$(df -BG --output=avail "$DEST" | tail -1 | tr -dc '0-9')
    say "need ~${need}G, have ${free}G free"
    (( free > need )) || { say "ERROR: not enough space"; exit 1; }

    # --- download ---------------------------------------------------------------
    i=0
    while IFS=$'\t' read -r name _size; do
        i=$((i + 1))
        local_file="$DEST/$name"
        if [[ -f "$local_file" ]]; then
            have=$(stat -c%s "$local_file")
            # split -b 2G means every part except the last is exactly that size.
            # Accepting any non-zero file keeps a part that was truncated by an
            # interrupted download — which then fails verification after 100G of
            # work, with nothing to point at the cause.
            if (( have != SPLIT_BYTES )) && [[ "$name" != "$last_part" ]]; then
                say "[$i/50] $name is short ($(numfmt --to=iec "$have")) — re-downloading"
                rm -f "$local_file"
            elif (( have > 0 )); then
                say "[$i/50] $name already present ($(numfmt --to=iec "$have"))"
                continue
            fi
        fi
        say "[$i/50] downloading $name"
        if ! "$PD" filesystem download "$REMOTE/$name" "$DEST" >>"$LOG" 2>&1; then
            say "[$i/50] FAILED $name — re-run to retry"
        fi
    done <<< "$manifest"
fi

# --- verify ------------------------------------------------------------------
parts=( "$DEST"/home.tar.zst.part-* )
have=0; [[ -e "${parts[0]}" ]] && have=${#parts[@]}
say "parts on disk: $have of 50"
(( have == 50 )) || { say "ERROR: incomplete, not verifying"; exit 1; }

say "reassembling and counting entries (this reads ~100G, several minutes)"
count=$(cat "$DEST"/home.tar.zst.part-* | zstd -d -c 2>/dev/null | tar -tf - 2>/dev/null | wc -l)
rc=$?

say "entries read: $count (expected $EXPECTED_ENTRIES)"
if (( count == EXPECTED_ENTRIES )); then
    say "RESULT: PASS — the archive restores intact"
    exit 0
fi
say "RESULT: FAIL — count mismatch (pipeline rc=$rc)"
say "A short count means a truncated or corrupt part. Delete the suspect part"
say "and re-run to re-download it."
exit 1
