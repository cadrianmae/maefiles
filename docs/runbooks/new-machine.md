# New machine bootstrap

On a fresh Linux box (Fedora, Ubuntu, Arch, or macOS), run:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/cadrianmae/maefiles/main/install.sh)
```

## Prerequisites on the new machine

1. **GPG secret key** — must already exist. Either:
   - Generate fresh: `gpg --full-generate-key` (choose ed25519)
   - Import existing: transfer via `gpg --export-secret-keys | ssh new-machine gpg --import` (never email)
2. **Machine is authorised to decrypt git-crypt scope** — from a trusted existing machine, once per new machine:
   ```bash
   yadm git-crypt add-gpg-user <new-key-id>
   yadm commit -m "authorise <new-machine-name>"
   yadm push
   ```
3. **BWS machine account + access token** — create one per machine in the Secrets Manager web UI. Store the token in your personal bw vault as item named `BWS Access Token - <hostname>` (hostname short name, e.g. `laptop-personal`).

## What the installer does

See `install.sh --show`.

Briefly:
1. Install prerequisites (`git gnupg pass yadm git-crypt unzip curl jq`)
2. Install `bw` + `bws` CLIs + `esh`
3. Verify GPG secret key present
4. `yadm clone --no-bootstrap`
5. `yadm git-crypt unlock`
6. `yadm bootstrap` — seeds pass from BWS, renders `.env`, decrypts archive, sets class

## Interactive prompts

- `sudo` password (once, for package install)
- `bw unlock` master password (once, to retrieve BWS token)
- Machine class: `personal` | `work`

## Verify

After install, open a new terminal, then:

```bash
pass ls                            # expect: api/{anthropic,mistral,openai,todoist}
source ~/.env && env | grep ANTHROPIC_API_KEY | head -c 40
~/bin/yadm-audit
~/bin/yadm-verify-encryption
```

## Troubleshooting

- **`git-crypt unlock failed`** — new key isn't authorised yet. From a trusted machine, run the `yadm git-crypt add-gpg-user` command in prerequisites.
- **`BWS Access Token - <hostname> not found`** — the item in your personal bw vault must exactly match the hostname-short output of `hostname -s` on the new machine. Rename or create.
- **`bws secret list` returns empty** — the machine account doesn't have read access to the `maefiles` project in BWS. Grant it in the web UI.
