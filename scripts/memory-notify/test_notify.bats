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
    run friendly_name java "/usr/bin/java -jar /srv/apps/legacy.jar"
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

@test "friendly_name: java under /opt is named for its directory" {
    run friendly_name java "/usr/bin/java -jar /opt/thing/app.jar"
    [ "$output" = "java (thing)" ]
}

@test "friendly_name: a -D flag path does not beat the real jar" {
    run friendly_name java "-Djava.library.path=/opt/decoy -jar /opt/real/app.jar"
    [ "$output" = "java (real)" ]
}

@test "friendly_name: a python script wins over an /opt path in a flag" {
    run friendly_name python3 "/usr/bin/python3 -Xfoo=/opt/decoy /home/u/tools/runner.py"
    [ "$output" = "python3 (runner)" ]
}

@test "friendly_name: empty comm does not crash" {
    run friendly_name "" "/usr/bin/java -jar /opt/thing/app.jar"
    [ "$status" -eq 0 ]
}

@test "top_consumers returns nonzero when ps is unavailable" {
    local stub="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$stub"
    printf '#!/bin/sh\nexit 1\n' > "$stub/ps"
    chmod +x "$stub/ps"
    PATH="$stub:$PATH" run top_consumers 3
    [ "$status" -ne 0 ]
}

@test "friendly_name: the interpreter's own /opt path does not win" {
    run friendly_name java "/opt/jdk/bin/java -jar /opt/real/app.jar"
    [ "$output" = "java (real)" ]
}

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

@test "render_body critical shows a marker when the process list is unavailable" {
    local stub="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$stub"
    printf '#!/bin/sh\nexit 1\n' > "$stub/ps"
    chmod +x "$stub/ps"
    PATH="$stub:$PATH" run render_body critical 7 1298 1.2
    [ "$status" -eq 0 ]
    [[ "$output" =~ "process list unavailable" ]]
    [[ "$output" =~ "Usable memory" ]]
}

@test "render_body warning never leaves Biggest dangling" {
    local stub="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$stub"
    printf '#!/bin/sh\nexit 1\n' > "$stub/ps"
    chmod +x "$stub/ps"
    PATH="$stub:$PATH" run render_body warning 18 600 2.8
    [ "$status" -eq 0 ]
    [[ ! "$output" =~ "Biggest: "$ ]]
    [[ "$output" =~ "unavailable" ]]
}
