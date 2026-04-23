# shellcheck shell=bash
# shellcheck disable=SC2059
# Shared run helpers for install.sh and .config/yadm/bootstrap.
# Source this: source "$(dirname "$0")/runlib.sh"
#
# SC2059 is globally suppressed because every printf in this file embeds
# terminal colour variables in the format string — that's the whole point.

BLUE='\033[0;36m'
GRAY='\033[0;90m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

DRY_RUN="${DRY_RUN:-0}"
VERBOSE="${VERBOSE:-0}"

step() {
  printf "\n${GRAY}── %s ──${NC}\n" "$*"
}

info() {
  printf "${GRAY}[INFO]${NC} %s\n" "$*"
}

warn() {
  printf "${YELLOW}[WARN]${NC} %s\n" "$*" >&2
}

error() {
  printf "${RED}[ERROR]${NC} %s\n" "$*" >&2
}

ok() {
  printf "${GREEN}[OK]${NC} %s\n" "$*"
}

# run <cmd> [args...]
# Print command, execute it (unless dry-run), report status.
run() {
  printf "${BLUE}\$ %s${NC}\n" "$*"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf "${GRAY}  [dry-run]${NC}\n"
    return 0
  fi
  if "$@"; then
    return 0
  fi
  local rc=$?
  printf "${RED}  [FAIL exit=%d]${NC}\n" "$rc"
  return "$rc"
}

# require <cmd>  — abort with friendly message if missing
require() {
  if ! command -v "$1" >/dev/null 2>&1; then
    error "missing required command: $1"
    return 1
  fi
}

# detect_pm  → echoes one of: dnf apt pacman brew (or empty + nonzero)
detect_pm() {
  for pm in dnf apt pacman brew; do
    if command -v "$pm" >/dev/null 2>&1; then
      echo "$pm"
      return 0
    fi
  done
  return 1
}
