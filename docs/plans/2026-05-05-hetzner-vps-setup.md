# Hetzner VPS Setup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Provision a Hetzner CAX11 VPS running Memos, with Tailscale providing private-network HTTPS access. All infrastructure-as-code lives in `~/homeops/`.

**Architecture:** Hybrid bootstrap — cloud-init handles OS hardening at provisioning time; a shell script handles Docker stack deployment after first SSH login. Single-service setup; Caddy deferred until Phase 2.

**Tech Stack:** Hetzner Cloud, Debian 12, Docker Compose v2, Tailscale, Memos. Plan execution: bash, ssh, git, Hetzner web console, Tailscale admin console.

**Spec:** [`~/docs/specs/2026-05-05-hetzner-vps-setup.md`](../specs/2026-05-05-hetzner-vps-setup.md)

**Hard guardrails:**
1. Hetzner provisioning **costs money** (~€3.79/mo). Server creation is Mae's explicit click in the UI.
2. Tailscale auth flows are **interactive** (browser-based) — Mae performs them.
3. SSH key generation lives on Mae's laptop; private keys never leave it.
4. The remote VPS shell script execution is Mae's command — I write the script, she runs it.

---

## Phase A: Local artifact creation

These tasks build everything that will live in `~/homeops/`. All can be done as FS operations on Mae's laptop. No remote actions.

## Task 1: Initialise `~/homeops/` repo

**Files:**
- Create: `~/homeops/` (directory)
- Create: `~/homeops/README.md`
- Create: `~/homeops/.gitignore`

- [ ] **Step 1: Create directory structure**

```bash
mkdir -p ~/homeops/{cloud-init,bootstrap,stacks/memos,docs/runbooks,docs/decisions}
cd ~/homeops
git init -b main
```

- [ ] **Step 2: Write README**

```bash
cat > ~/homeops/README.md << 'EOF'
# homeops

Infrastructure-as-code for Mae's self-hosted services.

## Layout

| Path | What |
|---|---|
| `cloud-init/` | Hetzner provisioning-time config (User Data) |
| `bootstrap/` | Post-SSH installation scripts |
| `stacks/<service>/` | Per-service Docker Compose files |
| `docs/runbooks/` | Step-by-step operational guides |
| `docs/decisions/` | ADRs explaining architectural choices |

## Current servers

| Hostname | Provider | Spec | OS | Services |
|---|---|---|---|---|
| `mae-vps` | Hetzner Cloud | CAX11 / Helsinki | Debian 12 | Memos |

## How to operate

- New server: see `docs/runbooks/provision-vps.md`
- New service: see `docs/runbooks/add-service.md`
- Restore from snapshot: see `docs/runbooks/recover-from-snapshot.md`

## Volumes

Service data lives at `/srv/<service>/` on the VPS — never in this repo. Backed up via Hetzner snapshots.
EOF
```

- [ ] **Step 3: Write .gitignore**

```bash
cat > ~/homeops/.gitignore << 'EOF'
# Secrets — never commit
*.env
*.secret
*.key
*.pem

# OS / editor cruft
.DS_Store
*.swp
*~
EOF
```

- [ ] **Step 4: First commit**

```bash
cd ~/homeops
git add .
git commit -m "chore: initial homeops repo

Skeleton for self-hosted infra. First server: mae-vps (Hetzner CAX11).
Spec: ~/docs/specs/2026-05-05-hetzner-vps-setup.md"
```

- [ ] **Step 5: Create + push to GitHub (Mae's hands)**

```bash
gh repo create cadrianmae/homeops --private --description "Self-hosted infrastructure-as-code"
git remote add origin https://github.com/cadrianmae/homeops.git
git push -u origin main
```

Verification: `gh repo view cadrianmae/homeops` shows the new private repo.

---

## Task 2: Generate dedicated VPS SSH key

**Files:**
- Create: `~/.ssh/mae-vps` (private key)
- Create: `~/.ssh/mae-vps.pub` (public key)

- [ ] **Step 1: Generate key (Mae's hands)**

```bash
ssh-keygen -t ed25519 -f ~/.ssh/mae-vps -C "mae-vps@$(hostname)" -N ""
```

The `-N ""` flag uses an empty passphrase. If you prefer a passphrase, drop `-N ""` and enter one when prompted (you'll need it on each SSH connection unless using ssh-agent).

- [ ] **Step 2: Verify both files exist**

```bash
ls -la ~/.ssh/mae-vps ~/.ssh/mae-vps.pub
```

Expected: `mae-vps` is `-rw-------`, `mae-vps.pub` is `-rw-r--r--`.

- [ ] **Step 3: Show the public key (you'll paste into Hetzner UI in Task 6)**

```bash
cat ~/.ssh/mae-vps.pub
```

Copy this line — it'll go into Hetzner's SSH Keys page next.

---

## Task 3: Write cloud-init config

**Files:**
- Create: `~/homeops/cloud-init/mae-vps.yaml`

- [ ] **Step 1: Write cloud-init YAML**

```bash
cat > ~/homeops/cloud-init/mae-vps.yaml << 'EOF'
#cloud-config
# Hetzner CAX11 / Debian 12 / hostname mae-vps
# This runs once on first boot.

hostname: mae-vps
fqdn: mae-vps.local
manage_etc_hosts: true

users:
  - name: mae
    groups: [sudo]
    sudo: "ALL=(ALL) NOPASSWD:ALL"
    shell: /bin/bash
    lock_passwd: true
    ssh_authorized_keys:
      - REPLACE_WITH_YOUR_PUBLIC_KEY

# Disable root SSH login + password auth — key-only access for `mae` user
ssh_pwauth: false
disable_root: true

# Baseline packages
package_update: true
package_upgrade: true
packages:
  - curl
  - ufw
  - git
  - gnupg
  - ca-certificates
  - unattended-upgrades

# Auto security upgrades
write_files:
  - path: /etc/apt/apt.conf.d/20auto-upgrades
    content: |
      APT::Periodic::Update-Package-Lists "1";
      APT::Periodic::Unattended-Upgrade "1";
    permissions: '0644'

# Firewall: allow SSH + Tailscale, deny everything else
runcmd:
  - ufw default deny incoming
  - ufw default allow outgoing
  - ufw allow 22/tcp
  - ufw allow in on tailscale0
  - ufw --force enable
  - systemctl enable --now unattended-upgrades

# Final reboot to apply kernel updates if any
power_state:
  delay: 'now'
  mode: reboot
  message: 'Reboot after cloud-init'
  condition: True
EOF
```

- [ ] **Step 2: Substitute the real public key into the YAML**

```bash
PUBKEY=$(cat ~/.ssh/mae-vps.pub)
sed -i "s|REPLACE_WITH_YOUR_PUBLIC_KEY|$PUBKEY|" ~/homeops/cloud-init/mae-vps.yaml
```

Verify:
```bash
grep "ssh_authorized_keys" -A 1 ~/homeops/cloud-init/mae-vps.yaml
```

Expected: shows `ssh_authorized_keys:` followed by your actual `ssh-ed25519 ...` line, no `REPLACE_` placeholder.

- [ ] **Step 3: Commit**

```bash
cd ~/homeops
git add cloud-init/mae-vps.yaml
git commit -m "feat: add cloud-init for mae-vps provisioning

Hardens Debian 12 baseline: non-root user mae, key-only SSH, ufw with
SSH+Tailscale only, unattended security upgrades."
```

---

## Task 4: Write bootstrap script

**Files:**
- Create: `~/homeops/bootstrap/01-stack.sh`

- [ ] **Step 1: Write the bootstrap script**

```bash
cat > ~/homeops/bootstrap/01-stack.sh << 'EOF'
#!/usr/bin/env bash
# 01-stack.sh — runs on mae-vps after first SSH.
# Installs Docker, Tailscale, deploys Memos via tailscale serve.
set -euo pipefail

echo "[01-stack] Installing Docker..."
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "[01-stack] Adding mae to docker group..."
sudo usermod -aG docker mae
echo "[01-stack] (You'll need to logout/login for docker group to take effect, or use sudo for this session.)"

echo "[01-stack] Installing Tailscale..."
curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.noarmor.gpg | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg > /dev/null
curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.tailscale-keyring.list | sudo tee /etc/apt/sources.list.d/tailscale.list
sudo apt-get update
sudo apt-get install -y tailscale

echo "[01-stack] Joining Tailscale (interactive — opens browser auth URL)..."
sudo tailscale up --hostname=mae-vps

echo "[01-stack] Creating /srv/memos data volume..."
sudo mkdir -p /srv/memos
sudo chown -R 1000:1000 /srv/memos

echo "[01-stack] Deploying Memos via docker compose..."
cd ~/homeops/stacks/memos
sudo docker compose up -d

echo "[01-stack] Waiting 10 seconds for Memos to start..."
sleep 10

echo "[01-stack] Configuring tailscale serve to expose Memos..."
sudo tailscale serve --bg https://localhost:5230

echo ""
echo "[01-stack] Done!"
echo ""
echo "Memos should now be reachable from any Tailscale-connected device at:"
sudo tailscale serve status | grep -i https || true
echo ""
echo "Open it on your phone (with Tailscale on) and sign up the first user — they become admin."
EOF
chmod +x ~/homeops/bootstrap/01-stack.sh
```

- [ ] **Step 2: Verify script syntax**

```bash
bash -n ~/homeops/bootstrap/01-stack.sh && echo "syntax OK"
```

Expected: `syntax OK`.

- [ ] **Step 3: Commit**

```bash
cd ~/homeops
git add bootstrap/01-stack.sh
git commit -m "feat: add post-SSH bootstrap script

Installs Docker + Tailscale, joins tailnet, deploys Memos compose stack,
configures tailscale serve for Memos HTTPS via Tailscale."
```

---

## Task 5: Write Memos docker-compose.yml

**Files:**
- Create: `~/homeops/stacks/memos/docker-compose.yml`
- Create: `~/homeops/stacks/memos/README.md`

- [ ] **Step 1: Write compose file**

```bash
cat > ~/homeops/stacks/memos/docker-compose.yml << 'EOF'
services:
  memos:
    image: neosmemo/memos:stable
    container_name: memos
    restart: unless-stopped
    ports:
      # Bind to localhost only — exposed externally via tailscale serve
      - "127.0.0.1:5230:5230"
    volumes:
      - /srv/memos:/var/opt/memos
EOF
```

- [ ] **Step 2: Write per-service README**

```bash
cat > ~/homeops/stacks/memos/README.md << 'EOF'
# Memos

Self-hosted note-taking / capture app, FleetingNotes-equivalent.

- **Image:** `neosmemo/memos:stable` (multi-arch — works on ARM)
- **Port:** 5230 (bound to localhost only)
- **Data volume:** `/srv/memos` on host
- **Public access:** via `tailscale serve` (Tailscale-only HTTPS)
- **Repo:** https://github.com/usememos/memos

## Operations

- Update to latest stable: `cd ~/homeops/stacks/memos && docker compose pull && docker compose up -d`
- Logs: `docker compose logs -f memos`
- Backup data: snapshot via Hetzner UI (covers `/srv/memos/`)
- Reset: `docker compose down && sudo rm -rf /srv/memos/*` (destructive!)

## Roles

First user to sign up becomes admin. Subsequent signups are restricted unless admin enables open registration in Memos settings.
EOF
```

- [ ] **Step 3: Commit**

```bash
cd ~/homeops
git add stacks/memos/
git commit -m "feat: add Memos docker-compose stack

Port bound to localhost (Tailscale serve handles external access).
Data persisted at /srv/memos."
```

---

## Task 6: Write runbooks

**Files:**
- Create: `~/homeops/docs/runbooks/provision-vps.md`
- Create: `~/homeops/docs/runbooks/add-service.md`
- Create: `~/homeops/docs/runbooks/recover-from-snapshot.md`

- [ ] **Step 1: Write provision-vps runbook**

```bash
cat > ~/homeops/docs/runbooks/provision-vps.md << 'EOF'
# Provision a fresh Hetzner VPS

End-to-end: from "no server" to "Memos accessible from phone."

## Prerequisites

- Hetzner Cloud account with default project
- Tailscale account with at least 2 devices already in tailnet (laptop + phone)
- SSH keypair `~/.ssh/mae-vps[.pub]` exists locally
- `~/homeops/` repo cloned + on `main`

## Steps

### 1. Add SSH key to Hetzner project

Hetzner Cloud Console → Security → SSH Keys → "Add SSH key"

- Name: `mae-vps`
- Paste contents of `~/.ssh/mae-vps.pub`

### 2. Create Hetzner Cloud Firewall

Hetzner Cloud Console → Firewalls → "Create Firewall"

- Name: `mae-vps-fw`
- Inbound rules:
  - SSH: TCP port 22 from `<your-home-public-ip>/32` (find via https://ifconfig.me)
  - Tailscale: UDP port 41641 from `0.0.0.0/0`
- Outbound rules: allow all (default)

### 3. Provision the server

Hetzner Cloud Console → Servers → "Add Server"

- **Location:** Helsinki (hel1)
- **Image:** Debian 12
- **Type:** Shared vCPU → Arm64 → CAX11
- **Networking:** Public IPv4 + IPv6 (default)
- **SSH key:** select `mae-vps`
- **Firewalls:** select `mae-vps-fw`
- **Cloud config (User data):** paste contents of `~/homeops/cloud-init/mae-vps.yaml`
- **Name:** `mae-vps`
- Click "Create & Buy now"

Wait ~60 seconds for first boot + cloud-init.

### 4. First SSH

```bash
ssh -i ~/.ssh/mae-vps mae@<vps-public-ip>
```

If permission denied, cloud-init may still be running — wait 60 more seconds and retry.

### 5. Verify cloud-init succeeded

```bash
sudo tail -50 /var/log/cloud-init-output.log
sudo tail -20 /var/log/cloud-init.log
sudo ufw status
```

Expected:
- cloud-init log ends with "finished at ..." (no errors)
- ufw shows: status active, port 22 allowed, default deny

### 6. Run bootstrap

```bash
git clone https://github.com/cadrianmae/homeops.git ~/homeops
bash ~/homeops/bootstrap/01-stack.sh
```

When prompted by `tailscale up`, click the auth URL in your laptop browser to add this VPS to your tailnet.

After bootstrap completes, the script prints the Tailscale URL for Memos.

### 7. Verify Memos from phone

On phone (with Tailscale on):
- Open `https://mae-vps.<your-tailnet>.ts.net` in browser
- Sign up first user — that user is admin
- Tap browser menu → "Install app" / "Add to Home Screen" — installs as PWA

### 8. Disable open registration (post-first-user)

In Memos web UI:
- Settings → System → toggle off "Allow user signup"

This prevents accidental account creation by anyone who reaches Memos via your tailnet.
EOF
```

- [ ] **Step 2: Write add-service runbook**

```bash
cat > ~/homeops/docs/runbooks/add-service.md << 'EOF'
# Add a new service to mae-vps

Pattern for stacking new Docker services onto the existing VPS.

## Steps

### 1. Plan the service

- Pick a docker image with multi-arch support (linux/amd64 + linux/arm64) — VPS is ARM
- Decide volume path: `/srv/<service-name>/`
- Decide internal port (don't conflict with existing — see `docker compose ps`)

### 2. Add to homeops repo (locally)

```bash
mkdir -p ~/homeops/stacks/<service-name>
```

Create `docker-compose.yml`:

```yaml
services:
  <service-name>:
    image: <image>:<tag>
    container_name: <service-name>
    restart: unless-stopped
    ports:
      - "127.0.0.1:<port>:<port>"
    volumes:
      - /srv/<service-name>:/var/opt/<service-name>
```

Create `README.md` documenting purpose, image, port, data path.

### 3. Commit + push

```bash
cd ~/homeops
git add stacks/<service-name>/
git commit -m "feat: add <service-name> stack"
git push
```

### 4. Deploy on VPS

```bash
ssh mae@mae-vps
cd ~/homeops && git pull
sudo mkdir -p /srv/<service-name> && sudo chown 1000:1000 /srv/<service-name>
cd stacks/<service-name>
docker compose up -d
```

### 5. Expose via Tailscale

```bash
sudo tailscale serve --bg --https=<external-port> http://localhost:<port>
```

If you've reached 2+ services, consider migrating to Caddy reverse proxy — see `docs/decisions/002-no-caddy-yet.md` for the trigger conditions.
EOF
```

- [ ] **Step 3: Write recover-from-snapshot runbook**

```bash
cat > ~/homeops/docs/runbooks/recover-from-snapshot.md << 'EOF'
# Recover mae-vps from Hetzner snapshot

When to use: data loss, accidental destructive change, or Memos corruption.

## Snapshot policy

- Manual snapshots before risky changes (manual via Hetzner Cloud UI)
- Automated daily snapshots: not yet (Phase 1 out of scope)
- Snapshot retention: keep last 3 manual + 7 daily (when automated)

## Recovery steps

### Option A: Restore in-place (overwrites current server)

Hetzner Cloud Console → Servers → mae-vps → Snapshots tab → "Rebuild" with target snapshot.

⚠ Destructive: anything created on the server since snapshot is lost.

### Option B: Spin up parallel from snapshot, copy data, swap DNS

1. Hetzner UI: Snapshots → "Create server from snapshot" → name `mae-vps-recovery`
2. SSH in, verify Memos data intact at `/srv/memos`
3. Stop main server's Memos: `ssh mae@mae-vps 'docker compose -f ~/homeops/stacks/memos/docker-compose.yml down'`
4. Copy data: `rsync -avz --delete mae-vps-recovery:/srv/memos/ /tmp/restore/ && rsync -avz --delete /tmp/restore/ mae@mae-vps:/srv/memos/`
5. Restart main: `ssh mae@mae-vps 'docker compose -f ~/homeops/stacks/memos/docker-compose.yml up -d'`
6. Destroy `mae-vps-recovery`

### Option C: Full rebuild from spec

If snapshot is also bad: re-run the provision-vps runbook end-to-end. Memos data lost (acceptable for Phase 1; data will be re-syncable from phone Memos app cache once available).
EOF
```

- [ ] **Step 4: Commit runbooks**

```bash
cd ~/homeops
git add docs/runbooks/
git commit -m "docs: add provision/add-service/recover runbooks"
```

---

## Task 7: Write decision records (ADRs)

**Files:**
- Create: `~/homeops/docs/decisions/001-vps-shape.md`
- Create: `~/homeops/docs/decisions/002-no-caddy-yet.md`
- Create: `~/homeops/docs/decisions/003-debian-vs-ubuntu.md`

- [ ] **Step 1: Write ADR 001 (VPS shape)**

```bash
cat > ~/homeops/docs/decisions/001-vps-shape.md << 'EOF'
# 001 — VPS shape: CAX11 ARM Helsinki

**Date:** 2026-05-05
**Status:** Accepted

## Context

Need a low-cost, low-maintenance VPS to host Memos and (later) Forgejo, Syncthing, etc.

## Decision

Hetzner Cloud **CAX11** (Arm64 Ampere, 2 vCPU / 4 GB / 40 GB, €3.79/mo) in **Helsinki (hel1)** datacentre.

## Why CAX11 (not CAX21)

Spec §6.4 originally suggested CAX21 (€5.39/mo, 4 vCPU / 8 GB / 80 GB) for stacking multiple services. Phase 1 hosts only Memos — single Go app, ~50MB RAM idle. Starting smaller halves cost; Hetzner allows non-destructive upgrade later when the stack actually demands it.

## Why ARM (not x86 CX22)

- Cheaper per-spec at Hetzner (~10% less)
- Memos image is multi-arch (linux/amd64 + linux/arm64)
- Future stack additions (Forgejo, Syncthing, Caddy, Tailscale) all multi-arch
- Edge case: any service that's amd64-only blocks adoption — verify before adding to stack

## Why Helsinki

- EU jurisdiction (data sovereignty post-Brexit, GDPR alignment)
- Latency from Ireland is reasonable (~40ms)
- Hetzner's Helsinki location is newer + has more capacity than Falkenstein/Nuremberg
EOF
```

- [ ] **Step 2: Write ADR 002 (No Caddy yet)**

```bash
cat > ~/homeops/docs/decisions/002-no-caddy-yet.md << 'EOF'
# 002 — No Caddy reverse proxy in Phase 1

**Date:** 2026-05-05
**Status:** Accepted

## Context

The vault spec named Caddy as part of the eventual stack (reverse proxy + auto-HTTPS). For Phase 1 with a single service (Memos) accessed only over Tailscale, Caddy adds a layer with no benefit.

## Decision

Use **`tailscale serve`** to expose Memos. Caddy stays uninstalled until a second service is added.

## Why

- `tailscale serve --bg https://localhost:5230` provides HTTPS automatically using Tailscale's cert system. No domain, no Let's Encrypt, no Caddyfile.
- Single service = nothing to route between
- YAGNI

## Trigger to revisit

Add Caddy when:
- A **second service** is deployed (multi-service routing benefit emerges)
- A **public domain** is attached (Tailscale serve only does Tailscale-internal)
- **Path-based routing** is needed within a single hostname

When triggered: install Caddy via Docker Compose at `stacks/caddy/`, replace tailscale serve mappings with Caddyfile entries.
EOF
```

- [ ] **Step 3: Write ADR 003 (Debian vs Ubuntu)**

```bash
cat > ~/homeops/docs/decisions/003-debian-vs-ubuntu.md << 'EOF'
# 003 — Debian 12 over Ubuntu 24.04

**Date:** 2026-05-05
**Status:** Accepted

## Context

Hetzner offers both Debian 12 and Ubuntu 24.04 as one-click images. Both run Docker fine.

## Decision

**Debian 12.**

## Why

- **No snap surprises** (Ubuntu's snap-installed packages occasionally cause Docker headaches)
- **Lighter base image** — fewer pre-installed services
- **Stable, predictable** — Debian's release cadence aligns with single-purpose servers
- **Docker upstream supports Debian first-class** (apt repo + tested images)

## Trade-off

Ubuntu has more StackOverflow answers and tutorial coverage. For our small stack, Debian's lower-noise baseline outweighs the documentation gap.
EOF
```

- [ ] **Step 4: Commit ADRs**

```bash
cd ~/homeops
git add docs/decisions/
git commit -m "docs: add ADRs for VPS shape, no-caddy-yet, debian choice"
```

---

## Task 8: Push artifact creation to GitHub

- [ ] **Step 1: Push all commits**

```bash
cd ~/homeops
git push
```

- [ ] **Step 2: Verify**

```bash
gh repo view cadrianmae/homeops --web
```

Expected: browser opens; all files visible (cloud-init, bootstrap, stacks/memos/, runbooks, decisions).

---

## Phase B: Tailscale device prep (Mae's hands)

## Task 9: Install + auth Tailscale on laptop

- [ ] **Step 1: Install Tailscale on laptop**

Fedora:
```bash
sudo dnf config-manager --add-repo https://pkgs.tailscale.com/stable/fedora/tailscale.repo
sudo dnf install tailscale
sudo systemctl enable --now tailscaled
```

- [ ] **Step 2: Authenticate**

```bash
sudo tailscale up
```

Click the URL it prints; authenticate in browser.

- [ ] **Step 3: Verify in admin console**

Open https://login.tailscale.com/admin/machines

Expected: laptop appears in the list.

---

## Task 10: Install + auth Tailscale on phone

- [ ] **Step 1: Install Tailscale app**

App Store / Play Store → "Tailscale" → Install.

- [ ] **Step 2: Sign in with same account**

In app: sign in. Match the account you used on laptop.

- [ ] **Step 3: Verify in admin console**

Open https://login.tailscale.com/admin/machines

Expected: phone now also in the list. **Two devices visible.**

---

## Phase C: Hetzner provisioning (Mae's hands, with my exact specs)

## Task 11: Add SSH key to Hetzner

- [ ] **Step 1: Open Hetzner Cloud Console**

https://console.hetzner.cloud → select default project → Security → SSH Keys

- [ ] **Step 2: Add key**

Click "Add SSH key":
- Name: `mae-vps`
- Public key: paste contents of `~/.ssh/mae-vps.pub` (output from `cat ~/.ssh/mae-vps.pub` on laptop)
- Click Create

- [ ] **Step 3: Verify**

The key appears in the SSH Keys list with the name `mae-vps`.

---

## Task 12: Create Hetzner Cloud Firewall

- [ ] **Step 1: Find your home public IP**

```bash
curl -s https://ifconfig.me
echo
```

Note this IP — you'll restrict SSH to it.

- [ ] **Step 2: Create firewall in Hetzner UI**

Console → Firewalls → "Create Firewall":
- Name: `mae-vps-fw`
- **Inbound rule 1 (SSH):**
  - Protocol: TCP
  - Port: 22
  - Source IPs: `<your-home-ip>/32` (e.g. `203.0.113.45/32`)
- **Inbound rule 2 (Tailscale):**
  - Protocol: UDP
  - Port: 41641
  - Source IPs: `0.0.0.0/0` (Tailscale punches NAT — needs any-source)
- **Outbound:** leave default (allow all)
- Apply to resources: leave empty (will attach during server creation)
- Click Create

---

## Task 13: Provision the CAX11 server

- [ ] **Step 1: Open server creation**

Console → Servers → "Add Server"

- [ ] **Step 2: Configure**

- **Location:** Helsinki (hel1)
- **Image:** Debian 12
- **Type:** Click "Shared vCPU" tab → "Arm64" → select **CAX11**
- **Networking:** keep defaults (Public IPv4 + IPv6)
- **SSH key:** check `mae-vps` (from Task 11)
- **Firewalls:** check `mae-vps-fw` (from Task 12)
- **Cloud config (under "Cloud config" or "User data"):** paste the contents of `~/homeops/cloud-init/mae-vps.yaml`
- **Name:** `mae-vps`

- [ ] **Step 3: Create**

Click "Create & Buy now". You'll see the server provisioning.

- [ ] **Step 4: Note the public IP**

Once provisioned, copy the public IPv4 address shown.

- [ ] **Step 5: Wait for first boot + cloud-init**

Wait ~90 seconds. The cloud-init reboots the server at the end, so it'll appear, go down briefly, come back up.

---

## Phase D: VPS bootstrap (Mae's hands, runs my scripts)

## Task 14: First SSH and verify cloud-init

- [ ] **Step 1: SSH in**

```bash
ssh -i ~/.ssh/mae-vps mae@<vps-public-ip>
```

Expected: prompt becomes `mae@mae-vps:~$`. If "permission denied", cloud-init may still be reconfiguring SSH — wait 30s and retry.

- [ ] **Step 2: Verify cloud-init log**

```bash
sudo tail -30 /var/log/cloud-init-output.log
```

Expected: no error lines. End with `finished at ...`.

- [ ] **Step 3: Verify ufw is active**

```bash
sudo ufw status verbose
```

Expected:
- Status: active
- Default: deny (incoming), allow (outgoing)
- 22/tcp ALLOW IN
- Anywhere on tailscale0 ALLOW IN

- [ ] **Step 4: Verify root login disabled + password auth disabled**

```bash
sudo grep -E "PermitRootLogin|PasswordAuthentication" /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null
```

Expected: `PermitRootLogin no` and `PasswordAuthentication no` (in cloud-init's drop-in config).

---

## Task 15: Run bootstrap script

- [ ] **Step 1: Clone homeops on VPS**

Still SSHed in as `mae`:

```bash
git clone https://github.com/cadrianmae/homeops.git ~/homeops
ls ~/homeops/bootstrap/01-stack.sh
```

Expected: file present.

- [ ] **Step 2: Run bootstrap**

```bash
bash ~/homeops/bootstrap/01-stack.sh
```

The script will pause at `tailscale up` — it prints a URL. **Open that URL in your laptop browser** to authenticate this VPS to your tailnet. Click "Connect" in the browser.

Once authenticated, the script continues: starts Memos, configures `tailscale serve`.

- [ ] **Step 3: Verify Tailscale**

```bash
tailscale status
```

Expected: shows `mae-vps` (this server) + your laptop + your phone.

- [ ] **Step 4: Verify Memos container running**

```bash
docker compose -f ~/homeops/stacks/memos/docker-compose.yml ps
docker compose -f ~/homeops/stacks/memos/docker-compose.yml logs --tail 20 memos
```

Expected: `memos` container Up, logs show "Server running" or similar.

- [ ] **Step 5: Verify tailscale serve**

```bash
sudo tailscale serve status
```

Expected: shows HTTPS forwarding from `mae-vps.<your-tailnet>.ts.net` → `localhost:5230`.

Copy the Tailscale URL — it'll be `https://mae-vps.<tailnet>.ts.net`.

---

## Phase E: Phone access + first user

## Task 16: Access Memos from phone

- [ ] **Step 1: Ensure Tailscale on phone is connected**

Open Tailscale app on phone. Toggle should be ON. Verify `mae-vps` appears in machine list.

- [ ] **Step 2: Open Memos in phone browser**

Type the URL printed by `tailscale serve status` (`https://mae-vps.<tailnet>.ts.net`). Browser should load the Memos signup page (no cert warnings — Tailscale handles the HTTPS).

- [ ] **Step 3: Sign up first user**

Fill in username + password. **The first user becomes admin automatically.**

- [ ] **Step 4: Disable open registration**

In Memos UI: top-right → Settings → System → toggle off "Allow user signup".

This prevents anyone else who reaches Memos via your tailnet from creating accounts (defence-in-depth — Tailscale is your perimeter, but multi-layer is good).

- [ ] **Step 5: Install as PWA**

Phone browser → tap menu → "Add to Home Screen" / "Install app". Memos now appears as an app icon. Open from home screen — full-screen PWA.

---

## Task 17: Final verification

- [ ] **Step 1: Capture a test memo**

In Memos PWA on phone: type "test from phone" + tap save.

- [ ] **Step 2: Verify it persisted**

In Memos PWA: refresh / close+reopen. Memo still visible.

- [ ] **Step 3: Verify it's on disk on VPS**

SSH to VPS:
```bash
sudo ls -la /srv/memos/
sudo find /srv/memos -name "*.db" -exec stat -c '%y %s %n' {} \;
```

Expected: data files present (Memos uses SQLite by default — look for `memos_prod.db` or similar).

- [ ] **Step 4: Verify success criteria from spec §9**

- [ ] CAX11 provisioned, Debian 12, hostname `mae-vps`
- [ ] SSH works as `mae` from laptop using dedicated key; root SSH disabled
- [ ] Hetzner Cloud Firewall + ufw both active, default-deny
- [ ] Tailscale running on VPS, joined to tailnet, visible in admin console
- [ ] `~/homeops/` repo on GitHub + cloned to VPS
- [ ] Memos container running, data persisted at `/srv/memos/`
- [ ] `tailscale serve` reverse-proxies HTTPS to Memos
- [ ] Phone (with Tailscale on) reaches `https://mae-vps.<tailnet>.ts.net` and signs in
- [ ] Memos PWA installable from phone browser
- [ ] Runbooks written (`provision-vps.md`, `add-service.md`, `recover-from-snapshot.md`)

All ten ✓ = done.

---

## Wrap-up

**What's running after this plan executes:**
- Hetzner CAX11 in Helsinki, Debian 12 hardened
- Memos container, data on `/srv/memos`
- Tailscale exposing Memos at `https://mae-vps.<tailnet>.ts.net`
- `~/homeops/` infrastructure-as-code repo on GitHub + cloned on VPS

**Cost:** €3.79/mo (CAX11) + ~€0.48/mo (snapshot storage if used) ≈ €4.27/mo

**Time estimate:**
- Phase A (artifact creation): ~1 hour
- Phase B (Tailscale on devices): ~10 min
- Phase C (Hetzner UI): ~10 min
- Phase D (bootstrap): ~10 min (mostly waiting for apt + Docker installs)
- Phase E (phone access): ~5 min
- Total: ~1.5–2 hours focused

**Out of scope (per spec §8):**
- Caddy reverse proxy (Phase 2 trigger: second service added)
- Forgejo (summer project)
- Syncthing (own future spec)
- Memos → MaeNotes vault sync script (own future spec)
- Automated backups (Phase 1 uses manual Hetzner snapshots)
- Monitoring (Phase 1 doesn't need it)

**Next session opportunities:**
- Write the Memos → vault sync script (Phase 3 in spec §10)
- Add daily/weekly Hetzner snapshot automation
- Set up restic backup to Hetzner Storage Box
