# memory-notify Pre-Freeze Warning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the chatty `memory-notify` timer with a single escalating notification that warns before the machine thrash-locks, naming which application to close.

**Architecture:** A long-running bash service polls `/proc/meminfo` and `/proc/pressure/memory` at an adaptive rate (10 s calm, 1 s under pressure). All decision logic lives in pure functions in a sourceable library, so the state machine is tested directly with bats rather than through environment injection. The notification is a single bubble reused via `--replace-id`: it alerts on escalation only, but refreshes its body silently while critical so the numbers are never stale.

**Tech Stack:** bash, bats-core, systemd user units, libnotify (`notify-send`), noctalia 5.0.0 as the notification server.

Spec: `~/docs/specs/2026-08-02-memory-notify-prefreeze-design.md`

## Global Constraints

- Target box: 15.8 GB RAM + 16 GB swapfile, zswap on, zram masked.
- Notification server is noctalia 5.0.0 (spec 1.2). `--expire-time=0` is REQUIRED for a sticky bubble; `--urgency=critical` alone silently expires.
- `--replace-id` quiet-swaps on this server (verified visually 2026-08-02). Refreshes must also pass `--hint=string:suppress-sound:true`.
- ASCII only in all scripts and docs. Use `[OK]`, `[WARN]`, `[INFO]`, `[ERROR]` tags in LOG output, never emoji or arrows. NOT in notification text -- the notification icon (dialog-error / dialog-warning) carries severity there, so bracket markers are redundant (Mae, 2026-08-02).
- No floating-point arithmetic in the hot loop. PSI values are carried as integer centi-percent (`3.32` becomes `332`). Headroom is an integer percent.
- All comments explain WHY, not WHAT. Follow `~/.claude/rules/development/self-documenting-code.md`.
- Every script starts `#!/usr/bin/env bash` and `set -euo pipefail`, except the sourceable library which must NOT set shell options (it would leak into the caller and into bats).
- `shellcheck` must pass clean on every file before each commit.
- **Commits are currently blocked** by the yadm pre-commit hook (`yadm-audit` requires `pass`, which is not installed; see memory `project-yadm-precommit-blocked`). Do the `yadm add` in each commit step; if the commit is rejected, leave the work staged and continue. Do NOT use `--no-verify`.

## File Structure

| Path | Responsibility |
|---|---|
| `~/bin/lib/memory-notify/core.sh` | Pure functions: parsing, tier classification, state machine. No I/O, no globals. |
| `~/bin/lib/memory-notify/notify.sh` | Process naming, body rendering, `notify-send` wrapper. |
| `~/bin/memory-notify` | Main loop: reads `/proc`, calls core, calls notify, adaptive sleep. |
| `~/.config/systemd/user/memory-notify.service` | `Type=exec`, `Restart=always`, `WantedBy=graphical-session.target`. |
| `~/scripts/memory-notify/test_core.bats` | Tests for `core.sh`. |
| `~/scripts/memory-notify/test_notify.bats` | Tests for `notify.sh`. |
| `~/scripts/memory-notify/fixtures/` | Sample `/proc` file contents. |

The split exists so the state machine is testable without running a loop or
faking `/proc`. `core.sh` takes numbers as arguments and returns strings.

Deleted at the end: `~/.config/systemd/user/memory-notify.timer`.

---

### Task 1: Library scaffold and /proc parsers

**Files:**
- Create: `~/bin/lib/memory-notify/core.sh`
- Create: `~/scripts/memory-notify/test_core.bats`
- Create: `~/scripts/memory-notify/fixtures/meminfo.txt`
- Create: `~/scripts/memory-notify/fixtures/pressure_memory.txt`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `parse_meminfo <file>` echoes `memtotal_kb memavail_kb swaptotal_kb swapfree_kb`
  - `parse_psi_full_avg10 <file>` echoes integer centi-percent, or `0` if absent
  - `headroom_pct <memtotal> <memavail> <swaptotal> <swapfree>` echoes integer percent

- [ ] **Step 1: Create the fixtures**

`~/scripts/memory-notify/fixtures/meminfo.txt`:

```
MemTotal:       16193536 kB
MemFree:          304128 kB
MemAvailable:    2210304 kB
Buffers:           28416 kB
Cached:          3588096 kB
SwapTotal:      16776188 kB
SwapFree:         277504 kB
```

`~/scripts/memory-notify/fixtures/pressure_memory.txt`:

```
some avg10=3.64 avg60=15.16 avg300=9.14 total=503254523
full avg10=2.99 avg60=12.98 avg300=8.21 total=478181271
```

- [ ] **Step 2: Write the failing tests**

`~/scripts/memory-notify/test_core.bats`:

```bash
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

@test "parse_psi_full_avg10 returns 0 when the file is missing" {
    run parse_psi_full_avg10 /nonexistent/pressure
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
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `bats ~/scripts/memory-notify/test_core.bats`
Expected: FAIL, `core.sh: No such file or directory`

- [ ] **Step 4: Write the implementation**

`~/bin/lib/memory-notify/core.sh`:

```bash
#!/usr/bin/env bash
# Pure decision logic for memory-notify. No I/O beyond reading files passed
# in by path, no globals, no shell options -- this file is sourced by both the
# service and the test suite, and `set -e` here would leak into bats.

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
    [[ -r "$file" ]] || { echo 0; return 0; }

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

    echo "${value:-0}"
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
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bats ~/scripts/memory-notify/test_core.bats`
Expected: 6 tests, all PASS

- [ ] **Step 6: Lint**

Run: `shellcheck ~/bin/lib/memory-notify/core.sh`
Expected: no output

- [ ] **Step 7: Commit**

```bash
cd ~
yadm add bin/lib/memory-notify/core.sh scripts/memory-notify/
yadm commit -m "memory-notify: add /proc parsers with tests"
```

---

### Task 2: Tier classification

**Files:**
- Modify: `~/bin/lib/memory-notify/core.sh`
- Modify: `~/scripts/memory-notify/test_core.bats`

**Interfaces:**
- Consumes: nothing from Task 1 at runtime.
- Produces: `classify_tier <headroom_pct> <psi_centi>` echoes `ok`, `warning`, or `critical`.

This is the RAW classification from current readings only. Stickiness and
hysteresis are Task 3's job -- keeping them separate is what makes both
testable.

- [ ] **Step 1: Write the failing tests**

Append to `~/scripts/memory-notify/test_core.bats`:

```bash
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats ~/scripts/memory-notify/test_core.bats`
Expected: 6 PASS, 8 FAIL with `classify_tier: command not found`

- [ ] **Step 3: Write the implementation**

Append to `~/bin/lib/memory-notify/core.sh`:

```bash
# Raw tier from the current reading alone. Both conditions must hold: low
# headroom says the kernel is nearly out of room, PSI says that shortage is
# actually costing the user time. Either on its own produces false alarms --
# high memory use is this machine's normal resting state.
readonly TIER_WARN_HEADROOM=20
readonly TIER_WARN_PSI=500
readonly TIER_CRIT_HEADROOM=10
readonly TIER_CRIT_PSI=1000

classify_tier() {
    local headroom="$1" psi="$2"

    if (( headroom <= TIER_CRIT_HEADROOM && psi >= TIER_CRIT_PSI )); then
        echo critical
    elif (( headroom <= TIER_WARN_HEADROOM && psi >= TIER_WARN_PSI )); then
        echo warning
    else
        echo ok
    fi
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bats ~/scripts/memory-notify/test_core.bats`
Expected: 14 tests, all PASS

- [ ] **Step 5: Commit**

```bash
cd ~
yadm add bin/lib/memory-notify/core.sh scripts/memory-notify/test_core.bats
yadm commit -m "memory-notify: add tier classification"
```

---

### Task 3: State machine

**Files:**
- Modify: `~/bin/lib/memory-notify/core.sh`
- Modify: `~/scripts/memory-notify/test_core.bats`

**Interfaces:**
- Consumes: `classify_tier` from Task 2.
- Produces: `decide <prev_tier> <watermark> <headroom> <psi>` echoes three
  space-separated fields: `<action> <new_tier> <new_watermark>` where action
  is one of `none`, `alert`, `refresh`, `recovered`.

This is the entire risk surface of the project. Every behaviour the user asked
for lives here: silent while sustained, speaks when worse, hysteresis on
recovery.

Watermark semantics: the LOWEST headroom seen during the current episode.
`999` means "no episode in progress".

- [ ] **Step 1: Write the failing tests**

Append to `~/scripts/memory-notify/test_core.bats`:

```bash
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
    run decide critical 9 5 1400
    [ "$output" = "refresh critical 5" ]
}

@test "decide: degradation measures from the watermark, not the last reading" {
    # Watermark 9, drifted to 6 (no alert), now 5 -- still not 5 below 9
    run decide critical 9 5 1400
    [ "$output" = "refresh critical 5" ]
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

@test "decide: re-arms after recovery so the next onset alerts" {
    run decide ok 999 18 600
    [ "$output" = "alert warning 18" ]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats ~/scripts/memory-notify/test_core.bats`
Expected: 14 PASS, 14 FAIL with `decide: command not found`

- [ ] **Step 3: Write the implementation**

Append to `~/bin/lib/memory-notify/core.sh`:

```bash
readonly RECOVER_HEADROOM=30
readonly RECOVER_PSI=200
readonly DEGRADE_STEP=5
readonly NO_EPISODE=999

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
    if (( headroom >= RECOVER_HEADROOM && psi < RECOVER_PSI )); then
        if [[ "$prev_tier" == "ok" ]]; then
            echo "none ok $NO_EPISODE"
        else
            echo "recovered ok $NO_EPISODE"
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
        echo "none ok $NO_EPISODE"
        return 0
    fi

    # Escalation always speaks.
    if (( $(tier_rank "$new_tier") > $(tier_rank "$prev_tier") )); then
        echo "alert $new_tier $headroom"
        return 0
    fi

    # Within a tier, speak only when measurably worse than the worst point of
    # this episode. Measuring from the watermark rather than the previous
    # reading stops a slow drift from alerting on every small step.
    if (( headroom <= watermark - DEGRADE_STEP )); then
        echo "alert $new_tier $headroom"
        return 0
    fi

    local new_watermark="$watermark"
    (( headroom < watermark )) && new_watermark="$headroom"

    # Critical keeps its bubble current; warning does not linger long enough
    # to go stale.
    if [[ "$new_tier" == "critical" ]]; then
        echo "refresh critical $new_watermark"
    else
        echo "none $new_tier $new_watermark"
    fi
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bats ~/scripts/memory-notify/test_core.bats`
Expected: 28 tests, all PASS

- [ ] **Step 5: Lint**

Run: `shellcheck ~/bin/lib/memory-notify/core.sh`
Expected: no output

- [ ] **Step 6: Commit**

```bash
cd ~
yadm add bin/lib/memory-notify/core.sh scripts/memory-notify/test_core.bats
yadm commit -m "memory-notify: add escalation state machine"
```

---

### Task 4: Naming the offending process

**Files:**
- Create: `~/bin/lib/memory-notify/notify.sh`
- Create: `~/scripts/memory-notify/test_notify.bats`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `friendly_name <comm> <cmdline>` echoes a human-recognisable label
  - `top_consumers <count>` echoes `<label> <rss_kb>` lines, biggest first

`ps` reports the Java process as `java`, which tells the user nothing. The
whole point of this notification is naming what to close, so generic runtimes
are resolved against their command line.

- [ ] **Step 1: Write the failing tests**

`~/scripts/memory-notify/test_notify.bats`:

```bash
#!/usr/bin/env bats

setup() {
    source "$HOME/bin/lib/memory-notify/notify.sh"
}

@test "friendly_name: a normal process keeps its own name" {
    run friendly_name vesktop "/app/bin/vesktop/vesktop.bin --type=zygote"
    [ "$output" = "vesktop" ]
}

@test "friendly_name: PrismLauncher java is resolved to the launcher" {
    run friendly_name java "/home/u/.local/share/PrismLauncher/java/java-runtime/bin/java -Xmx6G"
    [ "$output" = "java (PrismLauncher)" ]
}

@test "friendly_name: unrecognised java keeps the bare name" {
    run friendly_name java "/usr/bin/java -jar /opt/thing/app.jar"
    [ "$output" = "java" ]
}

@test "friendly_name: electron app resolved from its path" {
    run friendly_name electron "/usr/lib/electron/electron /opt/Obsidian/app.asar"
    [ "$output" = "electron (Obsidian)" ]
}

@test "friendly_name: python resolved from its script path" {
    run friendly_name python3 "/usr/bin/python3 /home/u/.config/speech-dispatcher/piper-daemon.py"
    [ "$output" = "python3 (piper-daemon)" ]
}

@test "friendly_name: empty cmdline does not crash" {
    run friendly_name java ""
    [ "$status" -eq 0 ]
    [ "$output" = "java" ]
}

@test "top_consumers returns the requested number of lines" {
    run top_consumers 3
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | wc -l)" -eq 3 ]
}

@test "top_consumers lines end in a numeric rss" {
    run top_consumers 1
    [[ "$output" =~ [0-9]+$ ]]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats ~/scripts/memory-notify/test_notify.bats`
Expected: FAIL, `notify.sh: No such file or directory`

- [ ] **Step 3: Write the implementation**

`~/bin/lib/memory-notify/notify.sh`:

```bash
#!/usr/bin/env bash
# Notification rendering for memory-notify. Sourced by the service and by the
# test suite, so no shell options are set here.

# Runtimes that tell the user nothing on their own. For these, the command
# line is searched for a recognisable application.
_is_generic_runtime() {
    case "$1" in
        java|electron|python3|python|node) return 0 ;;
        *) return 1 ;;
    esac
}

# "java" is useless when the user needs to know it is Minecraft. Resolve
# generic runtimes to something recognisable, falling back to the raw name
# rather than guessing wrongly.
friendly_name() {
    local comm="$1" cmdline="$2"

    _is_generic_runtime "$comm" || { echo "$comm"; return 0; }
    [[ -n "$cmdline" ]] || { echo "$comm"; return 0; }

    local app=""

    # Launcher-style layouts put the application name in a path component.
    if [[ "$cmdline" =~ PrismLauncher ]]; then
        app="PrismLauncher"
    elif [[ "$cmdline" =~ /opt/([A-Za-z0-9_-]+)/ ]]; then
        app="${BASH_REMATCH[1]}"
    elif [[ "$cmdline" =~ ([A-Za-z0-9_-]+)\.py([[:space:]]|$) ]]; then
        app="${BASH_REMATCH[1]##*/}"
    fi

    if [[ -n "$app" ]]; then
        echo "$comm ($app)"
    else
        echo "$comm"
    fi
}

# Echo "<label> <rss_kb>" for the biggest processes, largest first.
top_consumers() {
    local count="${1:-3}"
    ps -eo rss=,comm=,args= --sort=-rss 2>/dev/null \
        | head -n "$count" \
        | while read -r rss comm args; do
            printf '%s %s\n' "$(friendly_name "$comm" "$args")" "$rss"
        done
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bats ~/scripts/memory-notify/test_notify.bats`
Expected: 8 tests, all PASS

- [ ] **Step 5: Commit**

```bash
cd ~
yadm add bin/lib/memory-notify/notify.sh scripts/memory-notify/test_notify.bats
yadm commit -m "memory-notify: resolve generic runtimes to app names"
```

---

### Task 5: Rendering and sending the notification

**Files:**
- Modify: `~/bin/lib/memory-notify/notify.sh`
- Modify: `~/scripts/memory-notify/test_notify.bats`

**Interfaces:**
- Consumes: `top_consumers` from Task 4.
- Produces:
  - `render_body <tier> <headroom> <psi> <usable_gb>` echoes the notification body
  - `send_notification <tier> <mode> <replace_id> <body>` echoes the new
    notification id, or nothing on failure. `mode` is `alert` or `refresh`.

- [ ] **Step 1: Write the failing tests**

Append to `~/scripts/memory-notify/test_notify.bats`:

```bash
@test "render_body: critical body names the biggest consumer" {
    run render_body critical 7 1298 1.2
    [[ "$output" =~ "Usable memory" ]]
    [[ "$output" =~ "7%" ]]
    [[ "$output" =~ "12.98%" ]]
}

@test "render_body: warning body is a single compact line set" {
    run render_body warning 18 600 2.8
    [[ "$output" =~ "18%" ]]
    [[ "$output" =~ "6.00%" ]]
}

@test "render_body: psi centi-percent is rendered with two decimals" {
    run render_body warning 18 5 2.8
    [[ "$output" =~ "0.05%" ]]
}

@test "send_notification: alert mode does not suppress sound" {
    run build_notify_args critical alert 0
    [[ ! "$output" =~ "suppress-sound" ]]
}

@test "send_notification: refresh mode suppresses sound" {
    run build_notify_args critical refresh 42
    [[ "$output" =~ "suppress-sound:true" ]]
}

@test "build_notify_args: critical is sticky via explicit expire-time=0" {
    # urgency=critical alone silently expires on noctalia 5.0.0
    run build_notify_args critical alert 0
    [[ "$output" =~ "--expire-time=0" ]]
}

@test "build_notify_args: warning expires after 10 seconds" {
    run build_notify_args warning alert 0
    [[ "$output" =~ "--expire-time=10000" ]]
}

@test "build_notify_args: a known id becomes a replace-id" {
    run build_notify_args critical refresh 42
    [[ "$output" =~ "--replace-id=42" ]]
}

@test "build_notify_args: id 0 means a new bubble, no replace-id" {
    run build_notify_args critical alert 0
    [[ ! "$output" =~ "replace-id" ]]
}

@test "send_notification echoes nothing when the daemon is unavailable" {
    # The service normally starts before noctalia is ready, so a failed send
    # must be distinguishable from a successful one. Empty output means the
    # caller has to retry rather than consider the alert delivered.
    local stub="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$stub"
    printf '#!/bin/sh\nexit 1\n' > "$stub/notify-send"
    chmod +x "$stub/notify-send"

    PATH="$stub:$PATH" run send_notification critical alert 0 "body text"
    [ "$output" = "" ]
}

@test "send_notification echoes the id when the daemon accepts it" {
    local stub="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$stub"
    printf '#!/bin/sh\necho 77\n' > "$stub/notify-send"
    chmod +x "$stub/notify-send"

    PATH="$stub:$PATH" run send_notification critical alert 0 "body text"
    [ "$output" = "77" ]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats ~/scripts/memory-notify/test_notify.bats`
Expected: 8 PASS, 9 FAIL with `render_body: command not found`

- [ ] **Step 3: Write the implementation**

Append to `~/bin/lib/memory-notify/notify.sh`:

```bash
readonly NOTIFY_APP_NAME="Memory Notify"

# PSI is carried as centi-percent internally; humans want the decimal back.
_psi_human() {
    printf '%d.%02d' $(( $1 / 100 )) $(( $1 % 100 ))
}

render_body() {
    local tier="$1" headroom="$2" psi="$3" usable_gb="$4"
    local psi_human
    psi_human="$(_psi_human "$psi")"

    if [[ "$tier" == "warning" ]]; then
        printf 'Usable: %sGB (%s%%)   stall: %s%%\n' \
            "$usable_gb" "$headroom" "$psi_human"
        printf 'Biggest: %s\n' "$(top_consumers 1 | _format_consumer)"
        return 0
    fi

    printf 'Usable memory:  %sGB (%s%%)\n' "$usable_gb" "$headroom"
    printf 'Stalled:        %s%% of last 10s\n\n' "$psi_human"
    top_consumers 3 | _format_consumer
}

# "label 9756772" becomes "label   9.3GB"
_format_consumer() {
    while read -r line; do
        local rss="${line##* }"
        local label="${line% *}"
        awk -v l="$label" -v r="$rss" \
            'BEGIN { printf "%-28s %.1fGB\n", l, r / 1048576 }'
    done
}

# Assembled separately from the send so the flag logic is testable without a
# notification server. Echoes the argument list, one per line.
build_notify_args() {
    local tier="$1" mode="$2" replace_id="$3"

    printf -- '--app-name=%s\n' "$NOTIFY_APP_NAME"

    if [[ "$tier" == "critical" ]]; then
        printf -- '--urgency=critical\n'
        printf -- '--icon=dialog-error\n'
        # REQUIRED: noctalia 5.0.0 expires critical notifications without this,
        # despite the freedesktop spec saying they should persist.
        printf -- '--expire-time=0\n'
    else
        printf -- '--urgency=normal\n'
        printf -- '--icon=dialog-warning\n'
        printf -- '--expire-time=10000\n'
    fi

    (( replace_id > 0 )) && printf -- '--replace-id=%s\n' "$replace_id"

    # A refresh only rewrites the body; it must not re-alert the user.
    [[ "$mode" == "refresh" ]] && printf -- '--hint=string:suppress-sound:true\n'

    return 0
}

# Echoes the new notification id, or nothing if the send failed. Callers MUST
# treat empty output as failure and retry -- this service usually starts before
# the notification daemon is ready, so the first send of a session can fail.
send_notification() {
    local tier="$1" mode="$2" replace_id="$3" body="$4"
    local title args=()

    if [[ "$tier" == "critical" ]]; then
        title="Close something now"
    else
        title="Memory getting tight"
    fi

    mapfile -t args < <(build_notify_args "$tier" "$mode" "$replace_id")
    notify-send -p "${args[@]}" "$title" "$body" 2>/dev/null || true
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bats ~/scripts/memory-notify/test_notify.bats`
Expected: 17 tests, all PASS

- [ ] **Step 5: Lint**

Run: `shellcheck ~/bin/lib/memory-notify/notify.sh`
Expected: no output

- [ ] **Step 6: Commit**

```bash
cd ~
yadm add bin/lib/memory-notify/notify.sh scripts/memory-notify/test_notify.bats
yadm commit -m "memory-notify: add notification rendering and send"
```

---

### Task 6: Main loop with adaptive rate

**Files:**
- Modify: `~/bin/memory-notify` (full rewrite; the current prototype and
  its `.bak` remain untouched on disk)

**Interfaces:**
- Consumes: `parse_meminfo`, `parse_psi_full_avg10`, `headroom_pct`, `decide`
  from `core.sh`; `render_body`, `send_notification` from `notify.sh`.
- Produces: the executable service entry point.

State is held in shell variables, not `/tmp` files. The old design needed
files because each timer firing was a fresh process; a long-running loop does
not, which removes four state files and a whole class of staleness bugs.

- [ ] **Step 1: Write the implementation**

`~/bin/memory-notify`:

```bash
#!/usr/bin/env bash
# Pre-freeze memory warning. Runs as a systemd user service.
#
# Warns before the machine thrash-locks and the OOM killer starts taking
# processes down, naming which application to close. Replaces a 60s timer
# that alerted on RAM percent -- a value that sits at 90% permanently here and
# so fired constantly while still being too slow to catch an actual ramp.
#
# See ~/docs/specs/2026-08-02-memory-notify-prefreeze-design.md

set -euo pipefail

source "$HOME/bin/lib/memory-notify/core.sh"
source "$HOME/bin/lib/memory-notify/notify.sh"

readonly MEMINFO=/proc/meminfo
readonly PRESSURE=/proc/pressure/memory

# Poll faster than the alert thresholds, so a transition is already being
# sampled at 1-2s rather than discovered up to 10s late.
readonly RATE_CALM=10
readonly RATE_WATCH=2
readonly RATE_DANGER=1
readonly WATCH_HEADROOM=25
readonly DANGER_HEADROOM=15

readonly REFRESH_INTERVAL=5

tier=ok
watermark=999
notif_id=0
last_refresh=0
pending_alert=""

log() { printf '[%s] %s\n' "$1" "$2"; }

[[ -r "$PRESSURE" ]] || log INFO "no PSI at $PRESSURE, using headroom only"

close_notification() {
    (( notif_id > 0 )) || return 0
    gdbus call --session \
        --dest org.freedesktop.Notifications \
        --object-path /org/freedesktop/Notifications \
        --method org.freedesktop.Notifications.CloseNotification \
        "$notif_id" >/dev/null 2>&1 || true
    notif_id=0
}

while :; do
    read -r memtotal memavail swaptotal swapfree < <(parse_meminfo "$MEMINFO") || true

    # A transient parse failure must not change state or crash the service.
    # `read` succeeds even on empty input, so validate the value rather than
    # trusting the exit status.
    if [[ ! "${memtotal:-0}" =~ ^[0-9]+$ ]] || (( memtotal == 0 )); then
        log ERROR "could not parse $MEMINFO, skipping tick"
        sleep "$RATE_CALM"
        continue
    fi

    headroom=$(headroom_pct "$memtotal" "$memavail" "$swaptotal" "$swapfree")
    psi=$(parse_psi_full_avg10 "$PRESSURE")

    read -r action new_tier new_watermark < <(decide "$tier" "$watermark" "$headroom" "$psi")
    tier="$new_tier"
    watermark="$new_watermark"

    # A failed send must not consume the transition: this service usually
    # starts before the notification daemon, so the first alert of a session
    # would otherwise be lost silently.
    [[ -n "$pending_alert" ]] && action="alert"

    case "$action" in
        alert)
            usable_gb=$(awk -v k=$(( memavail + swapfree )) \
                'BEGIN { printf "%.1f", k / 1048576 }')
            body=$(render_body "$tier" "$headroom" "$psi" "$usable_gb")
            new_id=$(send_notification "$tier" alert "$notif_id" "$body")
            if [[ -n "$new_id" ]]; then
                notif_id="$new_id"
                pending_alert=""
                last_refresh=$(date +%s)
                log WARN "$tier headroom=${headroom}% psi=${psi}"
            else
                pending_alert=1
                log ERROR "notify-send failed, will retry"
            fi
            ;;
        refresh)
            now=$(date +%s)
            if (( now - last_refresh >= REFRESH_INTERVAL )); then
                usable_gb=$(awk -v k=$(( memavail + swapfree )) \
                    'BEGIN { printf "%.1f", k / 1048576 }')
                body=$(render_body "$tier" "$headroom" "$psi" "$usable_gb")
                new_id=$(send_notification "$tier" refresh "$notif_id" "$body")
                [[ -n "$new_id" ]] && notif_id="$new_id"
                last_refresh="$now"
            fi
            ;;
        recovered)
            close_notification
            log INFO "recovered headroom=${headroom}%"
            ;;
    esac

    if   (( headroom <= DANGER_HEADROOM )); then sleep "$RATE_DANGER"
    elif (( headroom <= WATCH_HEADROOM  )); then sleep "$RATE_WATCH"
    else                                         sleep "$RATE_CALM"
    fi
done
```

- [ ] **Step 2: Lint**

Run: `shellcheck ~/bin/memory-notify`
Expected: no output

- [ ] **Step 3: Smoke-test the loop by hand for 15 seconds**

Run: `timeout 15 ~/bin/memory-notify; echo "exit=$?"`
Expected: exit 124 (timeout killed it), no error output, no notification on a
healthy machine.

- [ ] **Step 4: Verify it survives a missing PSI file**

Run: `PRESSURE=/nonexistent timeout 5 bash -c 'source ~/bin/lib/memory-notify/core.sh; parse_psi_full_avg10 /nonexistent'`
Expected: `0`

- [ ] **Step 5: Commit**

```bash
cd ~
yadm add bin/memory-notify
yadm commit -m "memory-notify: replace timer script with adaptive loop"
```

---

### Task 7: systemd cutover

**Files:**
- Create: `~/.config/systemd/user/memory-notify.service` (replaces existing)
- Delete: `~/.config/systemd/user/memory-notify.timer`

**Interfaces:**
- Consumes: `~/bin/memory-notify` from Task 6.
- Produces: a running service.

- [ ] **Step 1: Replace the service unit**

`~/.config/systemd/user/memory-notify.service`:

```ini
[Unit]
Description=Pre-freeze memory warning
Documentation=file://%h/docs/specs/2026-08-02-memory-notify-prefreeze-design.md

# graphical-session.target rather than niri.service: unlike the bar, a memory
# warning is not desktop-specific and should work under Plasma too. It needs
# only a notification daemon.
PartOf=graphical-session.target
After=graphical-session.target

StartLimitIntervalSec=300
StartLimitBurst=5

[Service]
Type=exec
ExecStart=%h/bin/memory-notify

# The loop should never exit; if it does, that is a bug worth recovering from.
Restart=always
RestartSec=5

Slice=session.slice

[Install]
WantedBy=graphical-session.target
```

- [ ] **Step 2: Remove the obsolete timer**

```bash
systemctl --user disable --now memory-notify.timer 2>/dev/null || true
rm -f ~/.config/systemd/user/memory-notify.timer
systemctl --user daemon-reload
```

- [ ] **Step 3: Start the service**

```bash
systemctl --user enable --now memory-notify.service
systemctl --user is-active memory-notify.service
```

Expected: `active`

- [ ] **Step 4: Verify it is running in the right slice and not spinning**

```bash
systemctl --user show memory-notify.service -p Slice -p NRestarts
sleep 30
systemctl --user show memory-notify.service -p NRestarts
```

Expected: `Slice=session.slice`, and `NRestarts=0` both times.

- [ ] **Step 5: Check the log is quiet on a healthy machine**

Run: `journalctl --user -u memory-notify.service --since "2 min ago" --no-pager`
Expected: at most the one `[INFO]` line if PSI were missing; no WARN or ERROR.

- [ ] **Step 6: Commit**

```bash
cd ~
yadm add .config/systemd/user/memory-notify.service
yadm rm --cached .config/systemd/user/memory-notify.timer 2>/dev/null || true
yadm commit -m "memory-notify: replace timer unit with long-running service"
```

---

### Task 8: Live verification and cleanup

**Files:**
- Delete: `~/bin/memory-notify.bak`
- Modify: `~/docs/specs/2026-08-02-memory-notify-prefreeze-design.md` (status line)

**Interfaces:**
- Consumes: the running service from Task 7.
- Produces: evidence the thing works end to end.

- [ ] **Step 1: Confirm stress-ng is available**

Run: `command -v stress-ng || sudo dnf install -y stress-ng`

- [ ] **Step 2: Save all work before ballooning memory**

This step is manual and deliberate. Close or save anything unsaved. The
balloon is capped, but the machine will get slow.

- [ ] **Step 3: Run the contained balloon while watching the log**

```bash
journalctl --user -u memory-notify.service -f &
systemd-run --user --scope -p MemoryMax=6G \
    stress-ng --vm 1 --vm-bytes 5G --timeout 60s
```

Expected: headroom falls, the log shows a `[WARN]` line, and a notification
appears naming `stress-ng` as the biggest consumer. Reaching CRITICAL is not
expected -- a capped 5 GB balloon will not push a 15.8 GB machine below 10%
headroom. The tier logic itself is covered by Task 3.

- [ ] **Step 4: Confirm recovery closes the bubble**

After the balloon exits, wait 30 s.
Expected: an `[INFO] recovered` line, and the notification disappears.

- [ ] **Step 5: Confirm sustained pressure does not spam**

Count WARN lines from the run: `journalctl --user -u memory-notify.service --since "5 min ago" | grep -c WARN`
Expected: 1 or 2, not one per second. This is the entire point of the redesign.

- [ ] **Step 6: Remove the old prototype backup**

```bash
rm -f ~/bin/memory-notify.bak
```

- [ ] **Step 7: Mark the spec implemented**

Change the spec's `Status:` line to `Implemented 2026-08-02`.

- [ ] **Step 8: Commit**

```bash
cd ~
yadm add docs/specs/2026-08-02-memory-notify-prefreeze-design.md
yadm commit -m "memory-notify: mark spec implemented after live verification"
```

---

## Deferred

Not in this plan, tracked in the spec's "Out of scope":

- Project B: noctalia bar system monitors and right-side declutter (own spec)
- `earlyoom` backstop
- Lowering `oom_score_adj` for niri and noctalia (needs root)
- Approach C: bash plus a C `poll()` helper for sub-second PSI triggers
