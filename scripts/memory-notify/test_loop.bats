#!/usr/bin/env bats
# End-to-end tests for the memory-notify service loop. Unlike test_core.bats
# and test_notify.bats (which test the sourced libraries in-process), these
# drive the actual executable as a subprocess against fixture /proc files,
# with notify-send replaced by a controllable stub on PATH. This is the only
# place a bug in the loop's own glue code (as opposed to core.sh/notify.sh)
# can be caught by a test rather than by inspection.

SCRIPT="$HOME/bin/memory-notify"
FIXTURES="$HOME/scripts/memory-notify/fixtures"
STUB_SRC="$FIXTURES/notify-send-stub"

setup() {
    WORKDIR="$(mktemp -d)"
    STUBDIR="$WORKDIR/bin"
    mkdir -p "$STUBDIR"
    cp "$STUB_SRC" "$STUBDIR/notify-send"
    chmod +x "$STUBDIR/notify-send"

    export NOTIFY_STUB_CONTROL="$WORKDIR/control"
    export NOTIFY_STUB_LOG="$WORKDIR/calls.log"
    : > "$NOTIFY_STUB_LOG"
    echo ok > "$NOTIFY_STUB_CONTROL"
}

teardown() {
    # Best-effort: kill anything left running under the test's PATH override.
    [[ -n "${LOOP_PID:-}" ]] && kill "$LOOP_PID" 2>/dev/null
    rm -rf "$WORKDIR"
}

@test "critical readings produce exactly one alert log line, not one per tick" {
    cp "$FIXTURES/meminfo_critical.txt" "$WORKDIR/meminfo"
    cp "$FIXTURES/pressure_critical.txt" "$WORKDIR/pressure"

    # `run` (not a bare command) so timeout's 124 doesn't abort the test
    # under bats' set -e-like semantics.
    run env PATH="$STUBDIR:$PATH" \
        MEMNOTIFY_MEMINFO="$WORKDIR/meminfo" \
        MEMNOTIFY_PRESSURE="$WORKDIR/pressure" \
        NOTIFY_STUB_CONTROL="$NOTIFY_STUB_CONTROL" \
        NOTIFY_STUB_LOG="$NOTIFY_STUB_LOG" \
        timeout 4 "$SCRIPT"

    # timeout kills a still-running loop with 124; anything else is a crash.
    [ "$status" -eq 124 ]

    alert_lines=$(printf '%s\n' "$output" | grep -c '^\[WARN\] critical headroom=' || true)
    [ "$alert_lines" -eq 1 ]
}

@test "healthy readings produce no alert at all" {
    cp "$FIXTURES/meminfo_healthy.txt" "$WORKDIR/meminfo"
    cp "$FIXTURES/pressure_healthy.txt" "$WORKDIR/pressure"

    run env PATH="$STUBDIR:$PATH" \
        MEMNOTIFY_MEMINFO="$WORKDIR/meminfo" \
        MEMNOTIFY_PRESSURE="$WORKDIR/pressure" \
        NOTIFY_STUB_CONTROL="$NOTIFY_STUB_CONTROL" \
        NOTIFY_STUB_LOG="$NOTIFY_STUB_LOG" \
        timeout 3 "$SCRIPT"

    [ "$status" -eq 124 ]
    ! printf '%s\n' "$output" | grep -q '^\[WARN\]'
    [ ! -s "$NOTIFY_STUB_LOG" ]
}

@test "REGRESSION: a pending alert from a finished episode must not fire once healthy" {
    # Reproduces the CRITICAL finding: start critical with the notification
    # daemon down (send fails -> pending_alert set), then recover to a
    # healthy reading while the daemon comes back up. A stale pending_alert
    # must not be allowed to fire on a tier that has already recovered to ok.
    cp "$FIXTURES/meminfo_critical.txt" "$WORKDIR/meminfo"
    cp "$FIXTURES/pressure_critical.txt" "$WORKDIR/pressure"
    echo fail > "$NOTIFY_STUB_CONTROL"

    PATH="$STUBDIR:$PATH" \
        MEMNOTIFY_MEMINFO="$WORKDIR/meminfo" \
        MEMNOTIFY_PRESSURE="$WORKDIR/pressure" \
        timeout 6 "$SCRIPT" > "$WORKDIR/out.log" 2>&1 &
    LOOP_PID=$!

    # RATE_DANGER=1s while critical; give it time to tick, hit the failed
    # send, and set pending_alert.
    sleep 2
    grep -q '\[ERROR\] notify-send failed, will retry' "$WORKDIR/out.log"

    # Recover: swap in the healthy fixture and bring the "daemon" back up,
    # mid-run, in the same process that holds the stale pending_alert.
    cp "$FIXTURES/meminfo_healthy.txt" "$WORKDIR/meminfo"
    cp "$FIXTURES/pressure_healthy.txt" "$WORKDIR/pressure"
    echo ok > "$NOTIFY_STUB_CONTROL"

    sleep 2
    kill "$LOOP_PID" 2>/dev/null || true
    wait "$LOOP_PID" 2>/dev/null || true

    # The recovery must be logged...
    grep -q '\[INFO\] recovered headroom=' "$WORKDIR/out.log"

    # ...and no alert-shaped notification may have gone out once healthy.
    # "Memory getting tight" is the title send_notification uses for any
    # non-critical tier, including the bogus "ok" tier the bug sends it with.
    ! grep -q 'Memory getting tight' "$NOTIFY_STUB_LOG"
    ! grep -qE '^\[WARN\] ok headroom=' "$WORKDIR/out.log"
}

@test "REGRESSION: missing PSI must not suppress a critical alert" {
    # Reproduces the fail-closed finding: with PSI stuck at a sentinel that
    # AND-gates every tier above ok, critical headroom alone could never
    # alert. MEMNOTIFY_PRESSURE points at a path that never exists, so
    # parse_psi_full_avg10 must fall back to headroom-only classification.
    cp "$FIXTURES/meminfo_critical.txt" "$WORKDIR/meminfo"

    run env PATH="$STUBDIR:$PATH" \
        MEMNOTIFY_MEMINFO="$WORKDIR/meminfo" \
        MEMNOTIFY_PRESSURE="$WORKDIR/nonexistent-pressure" \
        NOTIFY_STUB_CONTROL="$NOTIFY_STUB_CONTROL" \
        NOTIFY_STUB_LOG="$NOTIFY_STUB_LOG" \
        timeout 4 "$SCRIPT"

    [ "$status" -eq 124 ]

    alert_lines=$(printf '%s\n' "$output" | grep -c '^\[WARN\] critical headroom=' || true)
    [ "$alert_lines" -ge 1 ]
}

@test "replace-id passes back the previous notification id, not a fixed one" {
    # The stub now issues incrementing ids (see fixtures/notify-send-stub) so
    # a --replace-id regression -- always 0, or the id just issued instead of
    # the one being replaced -- would be caught here rather than passing
    # silently against a fixed stub id.
    cp "$FIXTURES/meminfo_critical.txt" "$WORKDIR/meminfo"
    cp "$FIXTURES/pressure_critical.txt" "$WORKDIR/pressure"

    PATH="$STUBDIR:$PATH" \
        MEMNOTIFY_MEMINFO="$WORKDIR/meminfo" \
        MEMNOTIFY_PRESSURE="$WORKDIR/pressure" \
        timeout 7 "$SCRIPT" > "$WORKDIR/out.log" 2>&1 &
    LOOP_PID=$!

    # RATE_DANGER=1s while critical and REFRESH_INTERVAL=5s: give it long
    # enough for the initial alert plus at least one refresh.
    sleep 6
    kill "$LOOP_PID" 2>/dev/null || true
    wait "$LOOP_PID" 2>/dev/null || true

    # The first call is the alert; notif_id is still 0 at that point, so it
    # must not carry --replace-id at all.
    first_call=$(grep -m1 '^CALL' "$NOTIFY_STUB_LOG")
    ! grep -q -- '--replace-id=' <<< "$first_call"

    # A later refresh must carry --replace-id=1 -- the id the stub handed
    # back for that first call -- proving the loop threads the previous id
    # through rather than reusing a stale or fixed value.
    grep -q -- '--replace-id=1' "$NOTIFY_STUB_LOG"
}
