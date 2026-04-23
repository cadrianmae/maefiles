# Recovery

Scenarios and how to recover.

## Lost GPG key (whole key, all backups)

**Impact:** cannot decrypt pass store; cannot decrypt git-crypt-scoped files; cannot re-wrap `yadm encrypt` archive.

**Recovery:**

1. Generate new GPG key on a surviving machine
2. From each surviving machine, re-encrypt pass store to the new key:
   ```bash
   pass init <old-key-id> <new-key-id>   # re-encrypts everything
   ```
3. From a surviving trusted machine: `yadm git-crypt add-gpg-user <new-key-id>` + commit + push
4. Old key is now useless; revoke on keyservers if it was ever published

If **no surviving machine**: the encrypted files in the repo are unrecoverable. Re-bootstrap from BWS (still accessible with master password) on a new machine with new GPG key.

## Lost BWS access token (single machine)

**Impact:** that specific machine can't resync from BWS.

**Recovery:**

1. Revoke the old token in BWS web UI
2. Generate new token for the same machine account
3. Update the bw vault item `BWS Access Token - <hostname>` with new value
4. Re-run `yadm bootstrap`

## Compromised machine (laptop stolen)

**Impact:** pass + GPG agent cache could be used until screen-lock; BWS access token on-disk if cached in plaintext env var.

**Recovery:**

1. **Immediately**: revoke the machine account in BWS web UI (kills the access token)
2. Remove the GPG public key from git-crypt scope on all repos:
   ```bash
   yadm git-crypt rm-gpg-user <stolen-key-id>    # if supported, else re-init
   ```
3. Re-encrypt pass store on all surviving machines to remove the stolen key's access
4. Rotate every secret in BWS (per `rotate-secret.md`) — assume they're all compromised

## Broken yadm repo (local corruption)

**Impact:** can't commit or apply templates.

**Recovery:**

```bash
mv ~/.local/share/yadm/repo.git ~/.local/share/yadm/repo.git.broken
yadm clone --no-bootstrap git@github.com:cadrianmae/maefiles.git
# yadm refuses due to existing files — resolve by accepting local versions:
yadm status
yadm add -u
yadm commit -m "reconcile after local corruption"
```

## Forgotten BWS master password

**Impact:** can't log into BWS at all. BWS has no password recovery.

If you still have pass locally: every secret is still in pass, and access tokens in your personal vault still work. You can keep running until tokens expire or rotate.

Long-term: recreate the Secrets Manager project from scratch using values exported from pass.

## Emergency plaintext export

If you need to move keys off this setup in a hurry:

```bash
for p in $(pass ls | tail -n +2 | awk '{print $NF}' | tr -d '└├─'); do
  echo "$p = $(pass show "$p")"
done > /tmp/secrets-export.txt
```

Move the file to a safe place, then `shred -u /tmp/secrets-export.txt`.
