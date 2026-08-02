#!/usr/bin/env bash
# Pure decision logic for memory-notify. No I/O beyond reading files passed
# in by path, no shell options -- this file is sourced by both the service and
# the test suite, and `set -e` here would leak into bats. Only globals are the
# idempotent readonly threshold constants for tier classification.

# Echo: memtotal_kb memavail_kb swaptotal_kb swapfree_kb
parse_meminfo() {
    local file="$1"
    awk '
        /^MemTotal:/     { mt = $2 }
        /^MemAvailable:/ { ma = $2 }
        /^SwapTotal:/    { st = $2 }
        /^SwapFree:/     { sf = $2 }
        END              { print mt+0, ma+0, st+0, sf+0 }
    ' "$file"
}

# PSI is reported as a float ("2.99"). The hot loop compares it thousands of
# times, so it is carried as integer centi-percent to keep bash arithmetic
# usable and avoid spawning awk per comparison.
parse_psi_full_avg10() {
    local file="$1"
    # -1 is a sentinel for "no PSI signal", distinct from a genuine 0.00
    # reading. Callers gate escalation on this sign, so collapsing
    # "unreadable" into 0 here would silently disable every tier above ok.
    [[ -r "$file" ]] || { echo -1; return 0; }

    local value
    value=$(awk '/^full/ {
        for (i = 2; i <= NF; i++) {
            if ($i ~ /^avg10=/) {
                sub(/^avg10=/, "", $i)
                printf "%d", ($i * 100) + 0.5
                exit
            }
        }
    }' "$file")

    echo "${value:--1}"
}

# Combined RAM+swap headroom as an integer percent. This is the signal that
# actually predicts an OOM: RAM percent alone sits at 90% permanently on this
# machine and says nothing about how close the kernel is to giving up.
headroom_pct() {
    local memtotal="$1" memavail="$2" swaptotal="$3" swapfree="$4"
    local total=$(( memtotal + swaptotal ))
    (( total > 0 )) || { echo 0; return 0; }
    echo $(( ( (memavail + swapfree) * 100 ) / total ))
}

# Raw tier from the current reading alone. Both conditions must hold: low
# headroom says the kernel is nearly out of room, PSI says that shortage is
# actually costing the user time. Either on its own produces false alarms --
# high memory use is this machine's normal resting state.
if [[ -z "${MEMNOTIFY_TIER_WARN_HEADROOM:-}" ]]; then
    readonly MEMNOTIFY_TIER_WARN_HEADROOM=20
    readonly MEMNOTIFY_TIER_WARN_PSI=500
    readonly MEMNOTIFY_TIER_CRIT_HEADROOM=10
    readonly MEMNOTIFY_TIER_CRIT_PSI=1000
fi

classify_tier() {
    local headroom="$1" psi="$2"

    # A negative psi means "no PSI gate available" (see parse_psi_full_avg10),
    # not "PSI is zero". Falling back to headroom alone here is deliberate:
    # requiring a PSI signal that will never arrive would fail closed and
    # leave the user with no warning at all, which is the exact outcome this
    # tool exists to prevent. This path is more prone to false positives than
    # the gated one below -- high memory use alone is this machine's normal
    # resting state -- but that is the correct trade when the alternative is
    # silence.
    if (( psi < 0 )); then
        if (( headroom <= MEMNOTIFY_TIER_CRIT_HEADROOM )); then
            echo critical
        elif (( headroom <= MEMNOTIFY_TIER_WARN_HEADROOM )); then
            echo warning
        else
            echo ok
        fi
        return 0
    fi

    if (( headroom <= MEMNOTIFY_TIER_CRIT_HEADROOM && psi >= MEMNOTIFY_TIER_CRIT_PSI )); then
        echo critical
    elif (( headroom <= MEMNOTIFY_TIER_WARN_HEADROOM && psi >= MEMNOTIFY_TIER_WARN_PSI )); then
        echo warning
    else
        echo ok
    fi
}

# Recovery and escalation constants for the decide() state machine. Guarded
# the same way as the tier thresholds above so sourcing this file twice in
# one shell (service + test suite) does not trip "readonly variable".
if [[ -z "${MEMNOTIFY_NO_EPISODE:-}" ]]; then
    readonly MEMNOTIFY_RECOVER_HEADROOM=30
    readonly MEMNOTIFY_RECOVER_PSI=200
    readonly MEMNOTIFY_DEGRADE_STEP=5
    readonly MEMNOTIFY_NO_EPISODE=999
fi

# Rank tiers so they can be compared numerically. Tiers are sticky downward:
# once an episode starts, an improved reading must clear the recovery gate to
# end it. Without this a reading of 21% would silently reset to ok and the
# next dip to 20% would alert all over again -- the flapping this design
# exists to remove.
tier_rank() {
    case "$1" in
        critical) echo 2 ;;
        warning)  echo 1 ;;
        *)        echo 0 ;;
    esac
}

# Echo: <action> <new_tier> <new_watermark>
decide() {
    local prev_tier="$1" watermark="$2" headroom="$3" psi="$4"

    # Recovery is checked first and needs MORE headroom than onset required
    # (30 vs 20), so a machine hovering on the boundary cannot re-alert.
    # A psi of -1 (PSI unavailable) always satisfies "< MEMNOTIFY_RECOVER_PSI", so this
    # naturally degrades to a headroom-only recovery test in that case -- the
    # same fallback classify_tier uses, so onset and recovery stay coherent
    # with each other when PSI is missing.
    if (( headroom >= MEMNOTIFY_RECOVER_HEADROOM && psi < MEMNOTIFY_RECOVER_PSI )); then
        if [[ "$prev_tier" == "ok" ]]; then
            echo "none ok $MEMNOTIFY_NO_EPISODE"
        else
            echo "recovered ok $MEMNOTIFY_NO_EPISODE"
        fi
        return 0
    fi

    local raw_tier new_tier
    raw_tier=$(classify_tier "$headroom" "$psi")

    if (( $(tier_rank "$raw_tier") > $(tier_rank "$prev_tier") )); then
        new_tier="$raw_tier"
    else
        new_tier="$prev_tier"
    fi

    if [[ "$new_tier" == "ok" ]]; then
        echo "none ok $MEMNOTIFY_NO_EPISODE"
        return 0
    fi

    # Escalation always speaks.
    if (( $(tier_rank "$new_tier") > $(tier_rank "$prev_tier") )); then
        echo "alert $new_tier $headroom"
        return 0
    fi

    # Within a tier, speak only when measurably worse than the reading at the
    # last alert -- not the running low. The watermark only ever moves when
    # an alert fires (see below) or on recovery; it is passed through
    # unchanged on refresh/none. This guarantees the user is spoken to every
    # 5 real points of decline, independent of how poll timing happens to
    # land: under the old "lowest seen" scheme, a tick that landed mid-slide
    # would silently ratchet the bar down and could swallow the entire
    # decline from just-alerted down to critical with no further word.
    if (( headroom <= watermark - MEMNOTIFY_DEGRADE_STEP )); then
        echo "alert $new_tier $headroom"
        return 0
    fi

    # Critical keeps its bubble current; warning does not linger long enough
    # to go stale. Either way the watermark is unchanged -- it moves only on
    # alert or recovery.
    if [[ "$new_tier" == "critical" ]]; then
        echo "refresh critical $watermark"
    else
        echo "none $new_tier $watermark"
    fi
}
