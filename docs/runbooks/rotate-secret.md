# Rotate a secret

End-to-end: generate a new API key, update Bitwarden Secrets Manager, propagate to every machine.

## Flow

```
1. Generate new key at the upstream provider (e.g. Anthropic console)
2. Update BWS secret value via web UI or bws CLI
3. Every machine's next `yadm-refresh-secrets` pulls the new value
4. Old key revoked at upstream provider
```

## Step-by-step

### 1. Generate new key

Go to the upstream provider's dashboard. Generate a new key. Do not revoke the old one yet.

### 2. Update BWS

Via web UI (vault.bitwarden.com → Secrets Manager → maefiles project → edit secret), paste new value.

Or via CLI (needs a machine account with write access — usually only your laptop):

```bash
export BWS_ACCESS_TOKEN=$(bw get password "BWS Access Token - $(hostname -s)")
SECRET_ID=$(bws secret list --output json | jq -r '.[] | select(.key=="anthropic-api-key") | .id')
bws secret edit "$SECRET_ID" --value "sk-ant-..."
```

### 3. Propagate to machines

On each machine:

```bash
yadm-refresh-secrets --only api/anthropic
```

Or let the daily systemd timer catch it (within 30 days by default — faster if you set a shorter TTL in the manifest).

### 4. Revoke at upstream

Only after confirming all machines have the new value (check with `pass show api/anthropic` matches BWS). Then revoke the old key at the provider's dashboard.

## If in doubt — force refresh everything

```bash
yadm-refresh-secrets --all
```
