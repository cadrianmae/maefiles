#!/usr/bin/env bats

setup() {
    FIXTURES="$BATS_TEST_DIRNAME/fixtures"
    source "$HOME/bin/lib/memory-notify/core.sh"
}

@test "parse_meminfo extracts the four fields in kB" {
    run parse_meminfo "$FIXTURES/meminfo.txt"
    [ "$status" -eq 0 ]
    [ "$output" = "16193536 2210304 16776188 277504" ]
}

@test "parse_psi_full_avg10 returns centi-percent from the full line" {
    run parse_psi_full_avg10 "$FIXTURES/pressure_memory.txt"
    [ "$output" = "299" ]
}

@test "parse_psi_full_avg10 returns -1 (unavailable) when the file is missing" {
    run parse_psi_full_avg10 /nonexistent/pressure
    [ "$status" -eq 0 ]
    [ "$output" = "-1" ]
}

@test "parse_psi_full_avg10 distinguishes a genuine 0.00 reading from unavailable" {
    run parse_psi_full_avg10 "$FIXTURES/pressure_zero.txt"
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
}

@test "headroom_pct floors to an integer percent" {
    # (2210304 + 277504) / (16193536 + 16776188) = 7.54%
    run headroom_pct 16193536 2210304 16776188 277504
    [ "$output" = "7" ]
}

@test "headroom_pct handles a machine with no swap" {
    # 4000000 / 16000000 = 25%
    run headroom_pct 16000000 4000000 0 0
    [ "$output" = "25" ]
}

@test "headroom_pct returns 0 rather than dividing by zero" {
    run headroom_pct 0 0 0 0
    [ "$output" = "0" ]
}

@test "parse_meminfo handles meminfo with no SwapTotal or SwapFree lines" {
    run parse_meminfo "$FIXTURES/meminfo_noswap.txt"
    [ "$status" -eq 0 ]
    [ "$output" = "16193536 2210304 0 0" ]
}

@test "parse_meminfo handles an empty file" {
    run parse_meminfo "$FIXTURES/meminfo_empty.txt"
    [ "$status" -eq 0 ]
    [ "$output" = "0 0 0 0" ]
}

@test "parse_psi_full_avg10 returns -1 (unavailable) when only the some line is present" {
    # No `full` line means no avg10 field to parse -- unavailable, not zero.
    run parse_psi_full_avg10 "$FIXTURES/pressure_some_only.txt"
    [ "$status" -eq 0 ]
    [ "$output" = "-1" ]
}

@test "classify_tier: healthy machine is ok" {
    run classify_tier 60 10
    [ "$output" = "ok" ]
}

@test "classify_tier: low headroom without stalling is still ok" {
    # PSI is the gate: high memory use with no stalling is not an emergency
    run classify_tier 8 100
    [ "$output" = "ok" ]
}

@test "classify_tier: stalling with plenty of headroom is still ok" {
    run classify_tier 55 1500
    [ "$output" = "ok" ]
}

@test "classify_tier: warning needs headroom<=20 and psi>=5" {
    run classify_tier 20 500
    [ "$output" = "warning" ]
}

@test "classify_tier: just above the warning boundary is ok" {
    run classify_tier 21 500
    [ "$output" = "ok" ]
}

@test "classify_tier: critical needs headroom<=10 and psi>=10" {
    run classify_tier 10 1000
    [ "$output" = "critical" ]
}

@test "classify_tier: low headroom with mild stalling is only warning" {
    run classify_tier 7 600
    [ "$output" = "warning" ]
}

@test "classify_tier: the 2026-08-02 pre-freeze reading is critical" {
    # 7% headroom, full avg10 12.98 -- roughly 14 min before the freeze
    run classify_tier 7 1298
    [ "$output" = "critical" ]
}

@test "classify_tier: psi unavailable (-1) falls back to headroom-only critical" {
    run classify_tier 8 -1
    [ "$output" = "critical" ]
}

@test "classify_tier: psi unavailable (-1) falls back to headroom-only warning" {
    run classify_tier 18 -1
    [ "$output" = "warning" ]
}

@test "classify_tier: psi unavailable (-1) falls back to headroom-only ok" {
    run classify_tier 50 -1
    [ "$output" = "ok" ]
}

@test "decide: ok stays silent" {
    run decide ok 999 60 10
    [ "$output" = "none ok 999" ]
}

@test "decide: ok to warning alerts once" {
    run decide ok 999 18 600
    [ "$output" = "alert warning 18" ]
}

@test "decide: sustained warning is silent" {
    run decide warning 18 18 600
    [ "$output" = "none warning 18" ]
}

@test "decide: warning to critical alerts" {
    run decide warning 18 9 1100
    [ "$output" = "alert critical 9" ]
}

@test "decide: sustained critical asks for a refresh, not an alert" {
    run decide critical 9 9 1100
    [ "$output" = "refresh critical 9" ]
}

@test "decide: critical improving slightly is sticky and silent" {
    # 12% would classify as ok, but tiers never fall back except via recovery
    run decide critical 9 12 400
    [ "$output" = "refresh critical 9" ]
}

@test "decide: 5-point degradation re-alerts and moves the watermark" {
    run decide critical 9 4 1400
    [ "$output" = "alert critical 4" ]
}

@test "decide: 4-point degradation is below the step and stays silent" {
    # Watermark is the last ALERT (9), not the last reading -- it does not
    # move on this refresh, so the returned watermark is still 9.
    run decide critical 9 5 1400
    [ "$output" = "refresh critical 9" ]
}

@test "decide: watermark does not ratchet down on a non-alerting tick" {
    # Different reading (6, not 5) from the previous test, proving the
    # watermark held at 9 rather than having silently tracked the last
    # reading it was fed.
    run decide critical 9 6 1400
    [ "$output" = "refresh critical 9" ]
}

@test "decide: within-warning degradation re-alerts" {
    run decide warning 18 13 600
    [ "$output" = "alert warning 13" ]
}

@test "decide: sudden ok to critical spike alerts immediately" {
    run decide ok 999 5 1500
    [ "$output" = "alert critical 5" ]
}

@test "decide: recovery needs headroom>=30 and psi<2" {
    run decide critical 4 35 100
    [ "$output" = "recovered ok 999" ]
}

@test "decide: 25 percent does not recover -- hysteresis holds" {
    run decide critical 4 25 100
    [ "$output" = "refresh critical 4" ]
}

@test "decide: high headroom but still stalling does not recover" {
    run decide critical 4 35 800
    [ "$output" = "refresh critical 4" ]
}

@test "decide: warning recovers to ok cleanly" {
    run decide warning 18 40 50
    [ "$output" = "recovered ok 999" ]
}
