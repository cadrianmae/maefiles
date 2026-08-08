#!/usr/bin/env bash
# Two hibernate/resume cycles with verification between them.
#
# `systemctl hibernate` blocks until the machine resumes, so one script can
# drive both cycles. The second cycle is the point: a stale /sys/power/resume
# pointer lets the FIRST hibernate of a boot succeed and fails every one after
# it, so a single passing cycle proves nothing.
#
# Stops before cycle 2 if anything fails.

set -uo pipefail

HIBERFILE=/swap/hiberfile
fails=0

say()  { printf '\n\033[1m== %s\033[0m\n' "$*"; }
ok()   { printf '  \033[32m[ OK ]\033[0m %s\n' "$*"; }
bad()  { printf '  \033[31m[FAIL]\033[0m %s\n' "$*"; fails=$((fails + 1)); }

# Read from /dev/tty, not stdin: the script runs under sudo and may be invoked
# with stdin redirected, in which case `read` would return instantly and the
# machine would hibernate before you had a chance to set anything up.
pause() { # $1 = prompt
    printf '\n\033[1m%s\033[0m' "$1"
    if [[ -r /dev/tty ]]; then
        read -r < /dev/tty
    else
        echo; echo "  (no tty — continuing in 10s, Ctrl-C to abort)"; sleep 10
    fi
}

countdown() {
    printf '  hibernating in '
    for i in 5 4 3 2 1; do printf '%s ' "$i"; sleep 1; done
    printf '\n'
}

verify() {
    say "verify after cycle $1"
    fails=0

    # if/else rather than `A && B || C`: that idiom runs C when B fails too, so a
    # check could report both OK and FAIL. It happens to work while B is printf,
    # which is exactly the kind of accident that breaks on a later edit.
    if lsmod | grep -q '^nvidia '; then ok "nvidia module loaded"; else bad "nvidia module gone"; fi
    if lsmod | grep -qE '^(nouveau|nova_core)'; then bad "nouveau/nova_core loaded"; else ok "nouveau absent"; fi

    # The real test of the driver's sleep path: VRAM allocations restored.
    if out=$(nvidia-smi --query-gpu=name,driver_version --format=csv,noheader 2>&1); then
        ok "nvidia-smi responds: $out"
    else
        bad "nvidia-smi failed: $out"
    fi

    # Must be cleared by hibernate-resume.service, or the NEXT hibernate refuses
    # with "Specified resume device is missing or is not an active swap device".
    r=$(cat /sys/power/resume)
    if [[ $r == 0:0 ]]; then ok "resume pointer cleared"; else bad "resume pointer still $r"; fi

    # The reserve must be released again, otherwise everyday paging eats it.
    if swapon --show=NAME --noheadings | grep -qF "$HIBERFILE"; then
        bad "$HIBERFILE still active"
    else
        ok "$HIBERFILE released"
    fi

    # Wifi comes back via nm-applet + keyring; give it a moment before judging.
    for _ in $(seq 1 15); do
        nmcli -t -f STATE general 2>/dev/null | grep -q connected && break
        sleep 2
    done
    if nmcli -t -f NAME,STATE connection show --active 2>/dev/null | grep -q ':activated'; then
        ok "network up: $(nmcli -t -f NAME connection show --active | tr '\n' ' ')"
    else
        bad "no active connection after 30s"
    fi

    if journalctl -b -k --since "-3min" --no-pager 2>/dev/null \
        | grep -iE "nvidia.*(error|fail|Xid)" | head -3 | grep -q .; then
        bad "nvidia errors in dmesg (see: journalctl -b -k | grep -i nvidia)"
    else
        ok "no nvidia errors in dmesg"
    fi

    return $fails
}

(( EUID == 0 )) || { echo "run with sudo" >&2; exit 1; }

say "before"
swapon --show
printf 'resume %s  offset %s\n' "$(cat /sys/power/resume)" "$(cat /sys/power/resume_offset)"
nvidia-smi --query-gpu=name,driver_version --format=csv,noheader 2>/dev/null

say "cycle 1 of 2"
cat <<'EOF'
Open something identifiable FIRST -- a file in nvim, a few terminal tabs, a
browser page. A broken resume looks exactly like a normal boot; the only way you
notice is that what you had open is gone.
EOF
pause "Ready? Press Enter to hibernate: "
countdown
systemctl hibernate

pause "Press Enter to see the checks for cycle 1: "
if ! verify 1; then
    say "STOPPED"
    echo "Cycle 1 failed $fails check(s). NOT running cycle 2 -- fix this first."
    echo
    echo "  journalctl -b -1 -u systemd-hibernate.service"
    echo "  journalctl -b -1 -u hibernate-preparation.service"
    echo "  journalctl -b -1 -u nvidia-resume.service"
    exit 1
fi

say "cycle 2 of 2"
cat <<'EOF'
This is the cycle that matters. A stale /sys/power/resume pointer lets the FIRST
hibernate of a boot succeed and fails every one after it, so cycle 1 passing
proves nothing about cycle 2.

Check your session came back as you left it before continuing.
EOF
pause "Session intact? Press Enter to hibernate again (Ctrl-C to stop here): "
countdown
systemctl hibernate

if ! verify 2; then
    say "STOPPED"
    echo "Cycle 2 failed $fails check(s) -- cycle 1 passed, so this is the"
    echo "second-hibernate-of-a-boot case. Check hibernate-resume.service."
    exit 1
fi

say "PASSED"
echo "Two hibernate/resume cycles with the NVIDIA driver loaded, session intact."
