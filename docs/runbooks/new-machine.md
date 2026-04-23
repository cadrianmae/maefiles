# New machine bootstrap

On a fresh Linux box (Fedora, Ubuntu, Arch, or macOS), the ordered flow:

1. Generate SSH keypair + add to GitHub
2. Generate GPG keypair (or import existing) + authorise with git-crypt
3. Populate `pass` via Bitwarden Secrets Manager
4. Run `install.sh`

Total: ~15 minutes.

## Quick install (after prereqs below)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/cadrianmae/maefiles/main/install.sh)
```

> **Note:** the `maefiles` repo is private. If you haven't already set
> up SSH access to GitHub on this machine, the `yadm clone` step inside
> `install.sh` will fail. See Prereq 1 below.

## Prereq 1 — SSH keypair + GitHub

Per [ADR 004](../decisions/004-per-machine-ssh-keys.md), each machine
generates its own SSH key rather than sharing a GPG-encrypted archive.

```bash
# Generate a fresh ed25519 keypair on this machine
ssh-keygen -t ed25519 -C "$(hostname -s)@$(date +%Y-%m-%d)"
# Accept the default path (~/.ssh/id_ed25519), optionally set a passphrase

# Show the public key — copy this
cat ~/.ssh/id_ed25519.pub

# Add it to GitHub:
# https://github.com/settings/ssh/new
# Title: <hostname>  (e.g. "cadrianmae-desktop")
# Key: paste the contents of id_ed25519.pub

# Test
ssh -T git@github.com   # expect "Hi cadrianmae! ..."
```

## Prereq 2 — GPG secret key + git-crypt authorisation

```bash
# Option A — generate fresh on this machine (preferred per ADR 004)
gpg --full-generate-key
# → Choose ed25519; set name + email; set passphrase

# Option B — import from paperkey/USB backup (see gpg-key-recovery.md)
# ...

# Get this machine's new key fingerprint
gpg --list-secret-keys --keyid-format long
```

Then from a **trusted existing machine** that already has git-crypt
unlocked (your laptop):

```bash
yadm git-crypt add-gpg-user <new-machine-fingerprint>
yadm commit -m "authorise <new-machine-short-name>"
yadm push
```

This adds a wrapped copy of the git-crypt key for the new machine's GPG
key, pushed to GitHub.

## Prereq 3 — BWS machine account + access token

In the Bitwarden Secrets Manager web UI
(`https://vault.bitwarden.com/#/sm`):

1. Create a machine account: `<hostname>-<class>` (e.g.
   `cadrianmae-personal`, `maeslab-personal`)
2. Grant it read access to the `maefiles` project
3. Generate an access token — you'll see the token value once; copy it
4. In your personal bw vault (password manager), create a Login item:
   - Name: `BWS Access Token - <hostname>-<class>` (exact match required
     — bootstrap greps for this)
   - Password field: the access token value
5. `bw sync` on your primary machine

## Run the installer

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/cadrianmae/maefiles/main/install.sh)
```

> **If `curl` 404s**: the raw URL requires GitHub auth for private repos.
> Authenticate first: `gh auth login`, then use `gh auth setup-git` to
> configure credentials. Or `yadm clone git@github.com:cadrianmae/maefiles.git`
> manually after `ssh -T git@github.com` succeeds.

## What the installer does

See `install.sh --show` for the current content.

Step summary (may evolve):
1. Detect package manager (dnf/apt/pacman/brew)
2. Install prerequisites (`git gnupg pass yadm git-crypt unzip curl jq`)
3. Install `bw` + `bws` CLIs + `esh`
4. Verify GPG secret key exists (warn-only in `--dry-run`)
5. `yadm clone --no-bootstrap`
6. `yadm git-crypt unlock`
7. `yadm bootstrap` — seeds pass from BWS; no `.env` auto-load (on-demand model)

## Interactive prompts during install

- `sudo` password (once, for package install)
- `bw unlock` master password (once, to retrieve BWS access token)
- Machine class: `personal` | `work`

## Verify

After install, open a new terminal, then:

```bash
pass ls                            # expect: api/{anthropic,mistral,openai,todoist}
env-key load api/anthropic         # should work: gpg-agent unlocks once
~/bin/yadm-audit                   # manifest ↔ pass aligned
~/bin/yadm-verify-encryption       # no plaintext secrets in tracked files
systemctl --user list-timers yadm-secrets-check.timer   # next fire scheduled
```

## Troubleshooting

- **`git-crypt unlock failed`** — this machine's GPG key isn't authorised
  yet. From a trusted machine: Prereq 2 second-half (`yadm git-crypt
  add-gpg-user`). Re-run installer after pushing.
- **`BWS Access Token - <...>` not found in bw vault** — the item name
  must exactly match `BWS Access Token - $(hostname -s)-$CLASS`. Rename
  or create.
- **`bws secret list` returns empty** — the machine account doesn't have
  read access to the `maefiles` project. Grant it in the web UI.
- **`yadm clone` fails with SSH error** — you haven't added this
  machine's SSH public key to GitHub yet (Prereq 1).
- **raw.githubusercontent.com returns 404** — the repo is private;
  authenticate via `gh auth login` first, or clone the repo directly
  via `git@github.com:` instead of fetching via curl.

## Follow-up on first login after bootstrap

Add `env-key load api/...` to project `.envrc` files (direnv) for any
project that regularly needs API keys. See `loading-keys.md` for the
three loading patterns (ad-hoc / direnv / always-load).
