# Runbook — GPG key recovery

What to do before AND after a GPG key loss. This runbook has two halves:

- **Prevent** (do this first — today, if you haven't already)
- **Recover** (when disaster strikes)

Current key ID on this machine: `C8ABE62412652B9E` (check with
`gpg --list-secret-keys --keyid-format long`).

## What a GPG key loss means

The key protects four things:

| Asset | Protected by the key? | Recoverable without the key? |
|---|---|---|
| `pass` store entries | Yes (GPG-encrypted files) | ✅ Re-seed from BWS with a new key |
| `maefiles` git-crypt scope (`docs/secret/manifest.yaml`) | Yes (git-crypt wraps AES with GPG) | ⚠️ Regenerate from BWS + memory (5 min) |
| `claude-config` local repo | No encryption; just local disk | 🆘 Gone if no remote + no backup |
| git commit signing | Yes | ✅ Continue without signatures |

The real risk is **claude-config** (currently local-only per ADR 003).
Everything else has a cloud-side source of truth (BWS, GitHub).

---

# Prevent

## 1. Paperkey printout (do this today)

Converts the secret key to a printable text format. Store the paper
printout somewhere physically safe.

```bash
sudo dnf install paperkey
gpg --export-secret-keys C8ABE62412652B9E | paperkey --output /tmp/gpg-paperkey.txt
```

Print the file, then shred:

```bash
shred -u /tmp/gpg-paperkey.txt
```

Also export + print/QR the public key (needed alongside paperkey):

```bash
gpg --export --armor C8ABE62412652B9E > /tmp/gpg-public.asc
# Print or generate a QR code
shred -u /tmp/gpg-public.asc
```

To restore: retype (or OCR) paperkey text, then:

```bash
gpg --import gpg-public.asc
paperkey --pubring gpg-public.asc \
         --secrets gpg-paperkey.txt \
         --output gpg-secret-recovered.gpg
gpg --import gpg-secret-recovered.gpg
```

## 2. Encrypted USB backup

Belt + braces.

```bash
gpg --export-secret-keys --armor C8ABE62412652B9E > /tmp/gpg-secret.asc
gpg --export --armor C8ABE62412652B9E > /tmp/gpg-public.asc
gpg --export-ownertrust > /tmp/gpg-trust.txt

tar cJf /tmp/gpg-backup.tar.xz /tmp/gpg-{secret,public,trust}.{asc,txt} 2>/dev/null
gpg --symmetric --cipher-algo AES256 \
  --output /tmp/gpg-backup.tar.xz.gpg /tmp/gpg-backup.tar.xz

# Move the encrypted tarball to a LUKS USB and shred leftovers
shred -u /tmp/gpg-backup.tar.xz /tmp/gpg-{secret,public,trust}.{asc,txt}
```

## 3. Revocation certificate

Generate once, store separately. Lets you signal a compromised key
even if you've lost it.

```bash
gpg --output /tmp/gpg-revoc.asc --gen-revoke C8ABE62412652B9E
# Print it AND/OR store on the USB
shred -u /tmp/gpg-revoc.asc
```

## 4. Hardware token (optional)

A Yubikey holds the key on the device; drive failure can't touch it.
€50 + ~1h setup. Overkill for personal dotfiles.

---

# Recover

Scenario: your drive is dead OR `~/.gnupg/` is corrupted OR you deleted
the key by accident.

## 1. Restore the GPG secret key

### Option A — from paperkey

```bash
sudo dnf install paperkey gnupg2
```

Retype the paperkey output into a text file:

```bash
vim recovered-paperkey.txt   # paste in the printout contents
gpg --import gpg-public.asc
paperkey --pubring gpg-public.asc \
         --secrets recovered-paperkey.txt \
         --output gpg-secret-recovered.gpg
gpg --import gpg-secret-recovered.gpg
gpg --list-secret-keys   # confirm: C8ABE62412652B9E should appear
```

### Option B — from encrypted USB backup

```bash
gpg --decrypt /run/media/<you>/usb/gpg-backup.tar.xz.gpg \
  | tar xJf - -C /tmp
gpg --import /tmp/gpg-secret.asc
gpg --import-ownertrust /tmp/gpg-trust.txt
shred -u /tmp/gpg-*
```

## 2. Recover `pass` store

```bash
pass init C8ABE62412652B9E
bash ~/.config/yadm/bootstrap --all   # re-seeds all manifest entries from BWS
pass ls   # confirm entries
```

## 3. Recover `maefiles` git-crypt access

If key is restored:

```bash
yadm clone https://github.com/cadrianmae/maefiles.git
yadm git-crypt unlock
```

If key is **permanently** lost (no backup, no recovery):

```bash
yadm clone https://github.com/cadrianmae/maefiles.git
yadm git-crypt init
yadm git-crypt add-gpg-user <new-key-id>

# Regenerate docs/secret/manifest.yaml from BWS UI + memory
$EDITOR ~/docs/secret/manifest.yaml
yadm add ~/docs/secret/manifest.yaml
yadm commit -m "regenerate manifest after key loss"
yadm push
```

## 4. Recover `claude-config`

Local-only repo (per ADR 003). If drive is gone + no backup: rebuild
from scratch. Write new versions of `CLAUDE.md`, `memory.md`, `rules/*`.

**Prevention**: publish claude-config (per runbook
`publish-claude-config.md`) so GitHub has a copy.

## 5. Revoke the old key publicly

If you'd previously published the key (keyservers, GitHub), signal it
shouldn't be trusted anymore:

```bash
gpg --import gpg-revoc.asc
gpg --keyserver keys.openpgp.org --send-keys C8ABE62412652B9E
```

If you DON'T have the revoc cert, you can't revoke. Lesson: generate
the revoc cert now (before you need it).

## 6. Add new key where needed

Upload new public key to: GitHub account settings → SSH + GPG keys,
your email signing setup, Git providers, keyservers.

---

# Checklist — am I protected right now?

- [ ] Paperkey printout stored physically separate from laptop
- [ ] Encrypted USB backup with secret key + ownertrust
- [ ] Revocation cert generated + stored separately
- [ ] claude-config published to private GitHub repo (ADR 003 follow-up)
- [ ] Passphrase for USB tarball memorised or stored with paperkey

If you have the first three ticked, a drive failure is a ~1-hour
inconvenience, not a catastrophe.
