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
    else
        # Tokenize cmdline to avoid false positives from flag values and to
        # match against the intended path (e.g., jar file) rather than flag
        # decoration like -Djava.library.path=/opt/wrong. First non-flag token
        # that matches a pattern wins. Skip the interpreter's own path (which
        # would be the first token, e.g., /opt/jdk/bin/java) since that is
        # never the application the user should close.
        # Word splitting is intentional here.
        local token
        for token in $cmdline; do
            [[ "$token" == -* ]] && continue
            # The interpreter's own path is never the application to close --
            # /opt/jdk/bin/java would otherwise be named "jdk" instead of the jar.
            [[ -n "$comm" && "${token##*/}" == "$comm" ]] && continue
            if [[ "$token" =~ /opt/([A-Za-z0-9_-]+)/ ]]; then
                app="${BASH_REMATCH[1]}"; break
            fi
            if [[ "$token" =~ ([A-Za-z0-9_-]+)\.py$ ]]; then
                app="${BASH_REMATCH[1]##*/}"; break
            fi
        done
    fi

    if [[ -n "$app" ]]; then
        echo "$comm ($app)"
    else
        echo "$comm"
    fi
}

# Echo "<label> <rss_kb>" for the biggest processes, largest first.
# Returns 1 if ps fails or produces no output; 0 on success.
top_consumers() {
    local count="${1:-3}"
    local ps_out

    # Capture ps output first so we can distinguish a query failure (broken ps,
    # insufficient permissions) from an empty result (no processes). A memory
    # warning tool must not silently report "nothing is using memory" when the
    # query itself failed.
    if ! ps_out=$(ps -eo rss=,comm=,args= --sort=-rss 2>/dev/null) || [[ -z "$ps_out" ]]; then
        return 1
    fi

    printf '%s\n' "$ps_out" | head -n "$count" | while read -r rss comm args; do
        printf '%s %s\n' "$(friendly_name "$comm" "$args")" "$rss"
    done
}

# Idempotency guard: safe to source this file multiple times.
if [[ -z "${NOTIFY_APP_NAME:-}" ]]; then
    readonly NOTIFY_APP_NAME="Memory Notify"
fi

# PSI is carried as centi-percent internally; humans want the decimal back.
_psi_human() {
    printf '%d.%02d' $(( $1 / 100 )) $(( $1 % 100 ))
}

render_body() {
    local tier="$1" headroom="$2" psi="$3" usable_gb="$4"
    local psi_human consumers
    psi_human="$(_psi_human "$psi")"

    if [[ "$tier" == "warning" ]]; then
        printf 'Usable: %sGB (%s%%)   stall: %s%%\n' \
            "$usable_gb" "$headroom" "$psi_human"
        if consumers=$(top_consumers 1) && [[ -n "$consumers" ]]; then
            printf 'Biggest: %s\n' "$(printf '%s\n' "$consumers" | _format_consumer)"
        else
            printf 'Biggest: unavailable\n'
        fi
        return 0
    fi

    printf 'Usable memory:  %sGB (%s%%)\n' "$usable_gb" "$headroom"
    printf 'Stalled:        %s%% of last 10s\n\n' "$psi_human"
    # Consumers block: failure in ps results in an unavailable marker, not silent
    # data loss. render_body must return 0 always (not propagate exit status) because
    # the caller uses set -e with command substitution; a nonzero would abort the
    # entire service, turning a degraded notification into a dead watchdog.
    if consumers=$(top_consumers 3) && [[ -n "$consumers" ]]; then
        printf '%s\n' "$consumers" | _format_consumer
    else
        printf 'process list unavailable\n'
    fi
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
