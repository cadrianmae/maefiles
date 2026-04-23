#!/usr/bin/env bash
# maefiles — new-machine installer
#
# Usage (recommended):
#   bash <(curl -fsSL https://raw.githubusercontent.com/cadrianmae/maefiles/main/install.sh)
#
# Flags:
#   --show, --inspect   Print the script (bat if available, else less) and exit
#   --dry-run           Trace all commands without executing them
#   --verbose, -v       Add bash set -x on top of run() tracing
#   --no-confirm, -y    Skip the interactive "proceed" prompt
#   --class <name>      Set yadm class non-interactively (personal | work)
#   --ref <sha|tag>     Clone from a specific ref instead of main
#   --help, -h          Print this block and exit

set -euo pipefail

# Locate the script for self-display. Works for both `bash file.sh` and `bash <(curl …)`.
SCRIPT_PATH="${BASH_SOURCE[0]:-$0}"
REPO_URL="${MAEFILES_REPO_URL:-git@github.com:cadrianmae/maefiles.git}"
RAW_BASE="https://raw.githubusercontent.com/cadrianmae/maefiles"
REF="main"
CLASS=""
CONFIRM=1
DRY_RUN=0

# --- Argument parsing ----------------------------------------------------
show_help() {
  sed -n '2,/^$/p' "$SCRIPT_PATH" | sed 's/^# \{0,1\}//'
  exit 0
}

show_script() {
  if command -v bat >/dev/null 2>&1; then
    bat --language=bash --paging=always "$SCRIPT_PATH"
  elif command -v less >/dev/null 2>&1; then
    less "$SCRIPT_PATH"
  else
    cat "$SCRIPT_PATH"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --show|--inspect) show_script; exit 0 ;;
    --dry-run) DRY_RUN=1 ;;
    --verbose|-v) set -x ;;
    --no-confirm|-y) CONFIRM=0 ;;
    --class) CLASS="$2"; shift ;;
    --ref) REF="$2"; shift ;;
    --help|-h) show_help ;;
    *) echo "[ERROR] unknown flag: $1" >&2; exit 1 ;;
  esac
  shift
done

export DRY_RUN

# --- Locate runlib.sh ----------------------------------------------------
# When run locally, lib/runlib.sh sits alongside install.sh.
# When piped via curl/process-subst, fetch it.
RUNLIB=""
if [[ -f "$(dirname "$SCRIPT_PATH")/lib/runlib.sh" ]]; then
  RUNLIB="$(dirname "$SCRIPT_PATH")/lib/runlib.sh"
else
  RUNLIB="$(mktemp)"
  curl -fsSL "$RAW_BASE/$REF/lib/runlib.sh" -o "$RUNLIB"
fi
# shellcheck disable=SC1090
source "$RUNLIB"

# --- Preamble ------------------------------------------------------------
cat <<EOF

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  maefiles — new-machine installer
  ref:    $REF
  script: $SCRIPT_PATH
  sha256: $(sha256sum "$SCRIPT_PATH" 2>/dev/null | awk '{print $1}' || echo 'n/a')
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

This script will:
  [1] Detect package manager (dnf/apt/pacman/brew)
  [2] Install: git, gnupg2, pass, yadm, git-crypt
  [3] Install bw + bws CLIs from bitwarden.com and github.com
  [4] Install esh (shell template engine)
  [5] Verify GPG secret key exists (abort if missing)
  [6] yadm clone --no-bootstrap $REPO_URL
  [7] git-crypt unlock (requires trusted GPG key)
  [8] yadm bootstrap — seeds pass from Bitwarden

It will prompt for:
  - sudo password (once)
  - BWS access token (retrieved from bw vault, one master-password unlock)
  - machine class: personal | work (unless --class given)

EOF

if [[ $CONFIRM -eq 1 ]]; then
  read -rp "Review script before running? [Y/n] " review
  if [[ ! "$review" =~ ^[Nn]$ ]]; then
    show_script
  fi
  read -rp "Proceed? [y/N] " confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    info "Aborted."
    exit 0
  fi
fi

# --- 1. Detect package manager -------------------------------------------
step "1/8  detect package manager"
PM=$(detect_pm) || { error "no supported package manager found"; exit 1; }
info "using: $PM"

case "$PM" in
  dnf)    PM_INSTALL="sudo dnf install -y" ;;
  apt)    PM_INSTALL="sudo apt-get install -y" ;;
  pacman) PM_INSTALL="sudo pacman -S --noconfirm" ;;
  brew)   PM_INSTALL="brew install" ;;
esac

# --- 2. Install core prereqs --------------------------------------------
step "2/8  install prerequisites"
# shellcheck disable=SC2086
run $PM_INSTALL git gnupg2 pass yadm git-crypt unzip curl jq

# --- 3. Install bw + bws CLIs -------------------------------------------
step "3/8  install bw + bws CLIs"
mkdir -p "$HOME/.local/bin"

if ! command -v bw >/dev/null; then
  run curl -fsSL -o /tmp/bw.zip "https://bitwarden.com/download/?app=cli&platform=linux"
  run unzip -o /tmp/bw.zip -d /tmp/bw-install
  run chmod +x /tmp/bw-install/bw
  run mv /tmp/bw-install/bw "$HOME/.local/bin/bw"
  run rm -rf /tmp/bw.zip /tmp/bw-install
else
  info "bw already present: $(bw --version)"
fi

if ! command -v bws >/dev/null; then
  BWS_TAG="bws-v2.0.0"
  BWS_URL="https://github.com/bitwarden/sdk-sm/releases/download/$BWS_TAG/bws-x86_64-unknown-linux-gnu-${BWS_TAG#bws-v}.zip"
  run curl -fsSL -o /tmp/bws.zip "$BWS_URL"
  run unzip -o /tmp/bws.zip -d /tmp/bws-install
  run chmod +x /tmp/bws-install/bws
  run mv /tmp/bws-install/bws "$HOME/.local/bin/bws"
  run rm -rf /tmp/bws.zip /tmp/bws-install
else
  info "bws already present: $(bws --version)"
fi

# --- 4. Install esh -----------------------------------------------------
step "4/8  install esh (template engine)"
if ! command -v esh >/dev/null; then
  run curl -fsSL -o "$HOME/.local/bin/esh" \
    "https://raw.githubusercontent.com/jirutka/esh/master/esh"
  run chmod +x "$HOME/.local/bin/esh"
else
  info "esh already present"
fi

# --- 5. GPG key check ---------------------------------------------------
step "5/8  verify GPG secret key"
if ! gpg --list-secret-keys --with-colons 2>/dev/null | grep -q '^sec:'; then
  if [[ $DRY_RUN -eq 1 ]]; then
    warn "No GPG secret key — dry-run continues (would abort in a real install)"
  else
    error "No GPG secret key found."
    error "Generate one:  gpg --full-generate-key  (ed25519)"
    error "Or import:     gpg --import <file>"
    error "Then re-run this installer."
    exit 1
  fi
else
  info "GPG key present: $(gpg --list-secret-keys --keyid-format long | awk '/^sec/{print $2; exit}')"
fi

# --- 6. Clone -----------------------------------------------------------
step "6/8  clone maefiles via yadm"
if [[ -d "$HOME/.local/share/yadm/repo.git" ]]; then
  warn "yadm repo already exists at ~/.local/share/yadm/repo.git"
  warn "skipping clone; use 'yadm pull' if you want to update."
else
  run yadm clone --no-bootstrap --branch "$REF" "$REPO_URL"
fi

# --- 7. git-crypt unlock ------------------------------------------------
step "7/8  git-crypt unlock"
cd "$HOME"
if ! run yadm git-crypt unlock; then
  error "git-crypt unlock failed."
  error "Your GPG key isn't trusted by this repo yet."
  error "From a trusted machine:  yadm git-crypt add-gpg-user <your-key-id>"
  error "Commit the update, push, then re-run this installer."
  exit 1
fi

# --- 8. Bootstrap -------------------------------------------------------
step "8/8  run yadm bootstrap"
if [[ -n "$CLASS" ]]; then
  run yadm config local.class "$CLASS"
fi
run yadm bootstrap

ok "maefiles installed."
info "Open a new shell to pick up everything."
