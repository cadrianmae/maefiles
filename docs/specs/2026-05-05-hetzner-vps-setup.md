# Hetzner VPS Setup — Phase 1 (Memos host)

- **Author:** cadrianmae
- **Date:** 2026-05-05
- **Status:** Design approved
- **Related:**
  - `~/docs/specs/2026-05-04-maenotes-vault-design.md` §6.4 — Memos hosting context
  - `~/docs/specs/2026-05-05-journal-weekly-workflow.md` — wellness journal needs Memos for phone capture

## 1. Context

MaeNotes vault was designed assuming an external phone-capture path via Memos PWA (FOSS, self-hosted FleetingNotes-equivalent). Spec §6.4 named Hetzner Cloud CAX21 Helsinki ARM as the provisional VPS target. Without the VPS, phone capture currently relies on Obsidian Mobile share-sheet (always-works fallback).

This phase brings up the minimal VPS to host Memos, with Tailscale providing private-network HTTPS, and a `~/homeops/` repo holding all infrastructure-as-code so future services can stack onto the same baseline.

The maenotes spec listed Memos + Forgejo + Syncthing + Caddy + Tailscale all as eventual residents. This phase ships only **Memos + Tailscale**. Caddy is deferred until a second service makes reverse-proxying useful; Forgejo is deferred to the summer Codeberg-migration project; Syncthing is its own future project.

## 2. Decision summary

| Decision | Choice | Why |
|---|---|---|
| Provider | Hetzner Cloud (existing default project) | Already accepted in vault spec §6.4 |
| Server type | **CAX11** (ARM, 2 vCPU / 4 GB / 40 GB, €3.79/mo) Helsinki | Start small for single-service load; upgrade to CAX21 if/when stack grows. Hetzner upgrades are non-destructive. |
| OS | **Debian 12** | Stable, lightweight, well-supported by Docker, no Ubuntu snap surprises |
| Hostname | `mae-vps` | Descriptive, no namespace clash with `mae*` user files |
| User account | `mae` (non-root, sudo). Root SSH disabled after bootstrap. | Standard hardening |
| SSH key | Fresh dedicated keypair (`~/.ssh/mae-vps[.pub]`) | Compromise of any other key (GitHub, etc.) doesn't grant VPS access |
| Mesh VPN | **Tailscale** (free tier, existing account) | Private-network access, MagicDNS, free Let's Encrypt-equivalent HTTPS |
| HTTPS | `tailscale serve` — terminates at Tailscale, proxies to localhost:5230 | No domain needed, no cert management, no public exposure |
| Reverse proxy | **None for Phase 1** (Caddy deferred) | Single service + Tailscale-only HTTPS = Caddy redundant; YAGNI |
| Containers | Docker + Docker Compose v2 plugin (official Docker apt repo) | Industry default; matches user's existing Docker familiarity |
| Service | Memos (`neosmemo/memos:stable`) | Per maenotes spec §6.4 |
| Data volume | `/srv/memos/` on host disk | Easy `rsync` migration to future homelab; survives container rebuilds |
| Bootstrap | **Hybrid:** cloud-init (OS hardening) + shell script (Docker stack) | Reproducible baseline + iterable stack |
| Config repo | `~/homeops/` (local + cloned on VPS), GitHub remote | Single home for infrastructure-as-code; future services stack here |
| Backups (Phase 1) | Hetzner snapshots (manual or scheduled via UI) | Out-of-scope to automate; revisit when data volume justifies it |

## 3. Architecture

```
Local laptop                       Hetzner CAX11 (Debian 12, mae-vps)
┌──────────────┐                   ┌──────────────────────────────────┐
│ ssh ─────────┼─── SSH (key) ─────► sshd (port 22, key-only)         │
│              │                   │                                   │
│ Tailscale ──┼── Tailscale mesh ──► Tailscale daemon                  │
│   ↑          │                   │   ↓                               │
│   │ HTTPS    │                   │ tailscale serve :443 → :5230     │
│   │          │                   │   ↓                               │
│ Phone ───────┼── Tailscale ───────► docker compose                   │
│ (browser/PWA)│                   │   └─ memos:5230                   │
│              │                   │     └─ /srv/memos/ (volume)       │
└──────────────┘                   └──────────────────────────────────┘
```

### Network access

| Path | Source | Allowed | How |
|---|---|---|---|
| SSH (port 22) | Local laptop home IP | yes | Hetzner Cloud Firewall whitelist + ufw |
| SSH (port 22) | Anywhere else | no | firewall denies |
| Tailscale mesh (port 41641 UDP) | Tailscale | yes | firewall allows |
| HTTPS (port 443) public | n/a | **no** — service only reachable via Tailscale | tailscale serve binds to Tailscale interface only |
| Memos (port 5230) | localhost only | yes | docker compose binds 127.0.0.1:5230, not 0.0.0.0 |
| Everything else | any | no | firewall deny-by-default |

## 4. Repo layout (`~/homeops/`)

```
~/homeops/
├── README.md                   # what this is, how to use
├── .gitignore
├── cloud-init/
│   └── mae-vps.yaml            # Hetzner cloud-init: user, SSH, packages, hardening
├── bootstrap/
│   └── 01-stack.sh             # post-SSH stack install (Docker, Tailscale, Memos)
├── stacks/
│   └── memos/
│       ├── docker-compose.yml  # Memos service definition
│       └── README.md           # service-specific notes (env vars, ports, etc.)
└── docs/
    ├── runbooks/
    │   ├── provision-vps.md    # step-by-step: from "no server" to "Memos running"
    │   ├── add-service.md      # template for stacking future services
    │   └── recover-from-snapshot.md
    └── decisions/
        ├── 001-vps-shape.md    # CAX11 vs CAX21
        ├── 002-no-caddy-yet.md # why Tailscale serve only
        └── 003-debian-vs-ubuntu.md
```

`/srv/memos/` (on VPS) is the data volume — backed up via Hetzner snapshots, never in git.

## 5. Bootstrap workflow

### Phase A: cloud-init (provisioning time)

`cloud-init/mae-vps.yaml` is pasted into Hetzner's "User Data" field during server creation. It runs once on first boot.

Responsibilities:
- Create user `mae` with sudo access (no password — key-only)
- Install local laptop's SSH public key (`mae-vps.pub`)
- Disable root SSH login (`PermitRootLogin no`)
- Disable password authentication (`PasswordAuthentication no`)
- Set hostname `mae-vps`
- Install baseline packages: `curl ufw git gnupg ca-certificates`
- Configure `unattended-upgrades` for auto security patches
- Enable + set basic ufw rules (allow SSH + Tailscale, deny everything else)

### Phase B: shell script (post-SSH)

After cloud-init finishes and Mae SSHes in as `mae` for the first time, she runs `bootstrap/01-stack.sh`.

Responsibilities:
- Install Docker + Docker Compose v2 plugin from official Docker apt repo
- Add `mae` to `docker` group (logout/login required after)
- Install Tailscale from official apt repo
- Run `tailscale up` (interactive — Mae authenticates in browser to add VPS to her tailnet)
- Clone `~/homeops/` from GitHub (depth 1)
- Create `/srv/memos/` with correct ownership
- `cd ~/homeops/stacks/memos && docker compose up -d`
- `tailscale serve --bg https://localhost:5230` to expose Memos via Tailscale
- Print connection info (Tailscale URL for Memos)

## 6. Order of operations (one-time)

1. **Local prep:**
   - Generate SSH keypair: `ssh-keygen -t ed25519 -f ~/.ssh/mae-vps -C "mae-vps"`
   - Add public key to Hetzner project (UI: Security → SSH Keys)
   - Initialise `~/homeops/` repo locally + push empty repo to GitHub

2. **Tailscale prep:**
   - Install Tailscale on laptop, authenticate, add to tailnet
   - Install Tailscale on phone, authenticate, add to tailnet
   - Confirm both devices visible in Tailscale admin console

3. **Hetzner Cloud Firewall:**
   - Create firewall: allow port 22 from laptop's home IP only, allow Tailscale subnet, deny everything else
   - Apply to project (or to the server when created)

4. **Provision CAX11:**
   - Hetzner UI: Create Server → CAX11 / Helsinki / Debian 12
   - Attach the SSH key + cloud-init User Data from `~/homeops/cloud-init/mae-vps.yaml`
   - Attach the firewall
   - Wait ~30 seconds for boot + cloud-init to complete

5. **First SSH:**
   - From laptop: `ssh -i ~/.ssh/mae-vps mae@<vps-ip>`
   - Verify cloud-init succeeded: `tail -50 /var/log/cloud-init-output.log`
   - Bootstrap by cloning + running:
     ```bash
     git clone https://github.com/cadrianmae/homeops.git ~/homeops
     bash ~/homeops/bootstrap/01-stack.sh
     ```

6. **Tailscale auth (interactive):**
   - During bootstrap script: `sudo tailscale up` opens a browser-auth URL
   - Click through on laptop browser; VPS joins tailnet

7. **Verify:**
   - From phone (Tailscale on): `https://mae-vps.<tailnet>.ts.net` → Memos login page
   - Sign up first user (becomes admin)
   - Install as PWA on phone

## 7. Risks and mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| ARM image incompatibility (Memos image not multi-arch) | Low | High | Memos `neosmemo/memos:stable` is multi-arch (verified on Docker Hub). Fall back to `linux/amd64` via CX22 if needed. |
| Tailscale serve binding fails on first boot before tailnet auth | Medium | Low | Bootstrap script runs `tailscale up` first; only proceeds to `tailscale serve` after success |
| Hetzner snapshot lag / billing surprise | Low | Low | Snapshots cost €0.012/GB/month; 40 GB ≈ €0.48/mo; manual scheduling |
| SSH key compromise | Low | High | Dedicated VPS key; Hetzner Cloud Firewall restricts source IP |
| Memos data loss (no automated backups Phase 1) | Medium | High | Manual snapshot before risky changes; full automated backup deferred to its own spec |
| Tailscale free tier limit reached | Low | Low | 100 devices free; Mae has ≤5 |
| ufw/firewall lockout | Low | High | Hetzner Cloud Console provides recovery TTY independent of SSH |
| Cloud-init script bug locks out access | Low | High | Hetzner Cloud Console TTY recovery; cloud-init log inspection |

## 8. Out of scope (Phase 1)

- **Caddy reverse proxy** — defer to Phase 2 when second service is added
- **Forgejo** — summer project per maenotes spec §16
- **Syncthing** — its own future spec; replaces Obsidian Sync
- **Memos → MaeNotes vault sync script** — separate spec; pulls Memos API → `10 inbox/<timestamp>.md`
- **Automated backups** beyond Hetzner snapshots
- **Monitoring / alerting** (Uptime Kuma, Prometheus, etc.)
- **Public domain + Caddy public HTTPS**
- **CI/CD for the homeops repo** (manual `git pull && docker compose up -d` is fine)
- **Multi-server architectures** (single VPS sufficient)

## 9. Success criteria

Setup is complete when:

1. Hetzner CAX11 provisioned, Debian 12, hostname `mae-vps`
2. SSH works as `mae` from laptop using the dedicated key; root SSH disabled
3. Hetzner Cloud Firewall + ufw both active, default-deny posture
4. Tailscale running on VPS, joined to Mae's tailnet, visible in admin console
5. `~/homeops/` repo on GitHub + cloned to VPS
6. Memos container running, data persisted at `/srv/memos/`
7. `tailscale serve` reverse-proxies HTTPS to Memos
8. Phone (with Tailscale on) can reach `https://mae-vps.<tailnet>.ts.net` and sign in
9. Memos PWA installable from phone browser
10. Runbooks written: `provision-vps.md`, `add-service.md`

## 10. Future work

The following naturally extend Phase 1 and have their own specs/plans when the time comes:

- **Phase 2: Caddy reverse proxy** — when second service joins, switch from `tailscale serve` to Caddy (Tailscale-internal still). Reason: managing multiple Tailscale serve mappings becomes awkward.
- **Phase 3: Memos → MaeNotes sync script** — `qsync` or similar, runs on local laptop or as a systemd timer; calls Memos API, transforms each new memo into `10 inbox/<created-timestamp>.md`. Closes the journal-on-phone → vault loop.
- **Phase 4: Forgejo + bulk repo migration** — summer project. Per maenotes spec §16: Codeberg trial first, then Forgejo on this VPS.
- **Phase 5: Syncthing** — replaces Obsidian Sync (paid). Vault-tree sync between laptop, phone (eventually), and VPS as relay.
- **Phase 6: Automated backups** — restic to Hetzner Storage Box or B2, plus periodic snapshot verification.
- **Phase 7: Monitoring** — lightweight (Uptime Kuma) when the stack is enough services to warrant tracking.
