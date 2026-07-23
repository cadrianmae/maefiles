# VPS Summer Roadmap — Brainstorm Snapshot (PARKED)

- **Author:** cadrianmae
- **Date:** 2026-05-11
- **Status:** Brainstorm parked until June 1, 2026 — to resume phasing + spec finalisation
- **Related:**
  - `~/docs/specs/2026-05-05-hetzner-vps-setup.md` — Phase 1 (Memos host, superseded by fleeting-notes replacement)
  - `~/homeops/` — existing infrastructure-as-code repo

## State at time of parking

VPS `mae-vps` (Hetzner) is fully operational on tailnet `quail-cordylus.ts.net`. Memos was abandoned (didn't suit use case); a self-hosted fleeting-notes replacement is in dev elsewhere. gencast offload via `vps-offload.sh` (SSH+tmux pattern) is proven and currently running.

## Brainstorm goal

"All of the above, in sequence": catalogue → shortlist → phasing framework. Catalogue and shortlist done. Phasing direction agreed but phase contents NOT yet committed.

## Stage 1: Catalogue (by service type)

Wide-net catalogue captured across 7 categories: always-on web apps, batch compute, storage/sync, network services, automations/bots, persistent-state plumbing, public-facing. ~60 candidate items. (Full catalogue in chat history; reproduce on demand when resuming.)

## Stage 2: Summer shortlist — 14 chunks

| # | Chunk | Notes |
|---|---|---|
| 1 | gencast offload | ✅ Done. Migrates to #15 as first job. |
| 2 | Fleeting-notes capture endpoint | Hosted here; dev elsewhere. Replaces Memos. |
| 3 | Caddy reverse proxy + domain + Let's Encrypt | Platform foundation. |
| 4 | Syncthing | Per maenotes vault spec, summer slot. |
| 5 | Forgejo | Per maenotes vault spec, summer slot. |
| 6 | Fleeting-notes → MaeNotes sync script | Closes phone-capture loop. |
| 7 | Restic backups + offsite (Hetzner Storage Box?) | Portfolio-grade requires this. |
| 8 | Immich + Ente migration | Photo data sovereignty. Ente is interim self-host. |
| 9 | Personal site (`cadrianmae.<tld>`) | Static; job-market portfolio surface. |
| 10 | Uptime Kuma | Service status monitoring. |
| 11 | Healthchecks.io self-hosted | Cron-job dead-man switch. |
| 12 | Telegram/Signal personal bot | Bidirectional phone ↔ VPS / laptop. |
| 13 | Scheduled digest emails | Cron + claude-mail wiring. |
| 14 | `vps-burst` (pueue + rsync wrapper + claude-mail/notify hooks) | Generalises gencast offload pattern. |

### Decisions made

- **Public surface:** Keep options open. Caddy + domain + LE wired even before public services exist.
- **Storage scope:** Immich only. Proton Unlimited covers mail/drive/calendar/contacts; Paperless/Radicale/Nextcloud parked.
- **Productivity self-host bucket (Vaultwarden/Atuin/AdGuard/RSS):** Skipped this summer.
- **Isolated Claude Code on VPS:** Parked.
- **GPU on VPS:** Parked. Will consider GPU rental (vast.ai, runpod) ad-hoc instead.
- **n8n:** Catalogued for later. Adopt only if integration count grows past 5-6 wired services.
- **Burst runner tool:** **pueue** (modern Rust daemon, in apt). Wrapper CLI `vps-burst` handles rsync up/down + notification hooks.

### Items NOT in summer scope (future catalogue)

- Vaultwarden, Atuin, AdGuard Home, FreshRSS/Miniflux
- Paperless-ngx, Radicale, Nextcloud-lite
- Authentik/Authelia (SSO)
- Headscale (only if leaving Tailscale free tier)
- n8n (adopt threshold = 5+ wired integrations)
- Isolated Claude Code on VPS
- GPU host upgrade

## Stage 3: Phasing direction — agreed shape, phase contents TBD

**Approach:** "C with inspiration from A" — use-case-driven phases (each phase ships a user-visible win), with deliberate platform-overbuild in early phases so later phases inherit a stable foundation rather than scrambling.

**Working phase sketch (NOT FINAL — to commit on resume):**

- **Phase 1 — Phone capture loop:** Caddy + domain + LE + fleeting-notes endpoint + sync script. Foundation deliberately overbuilt for future phases.
- **Phase 2 — Data sovereignty:** Immich + Ente migration + restic backups.
- **Phase 3 — Always-on me:** Telegram bot + scheduled digests + Uptime Kuma + Healthchecks.
- **Phase 4 — Portfolio surface:** Personal site + Forgejo + Syncthing.
- **(cross-cutting):** `vps-burst` runner ships early in Phase 1 alongside Caddy because it depends on nothing else and unlocks burst-job offload immediately.

## To resume (June 1, 2026)

1. Re-read this spec.
2. Confirm shortlist still matches priorities (rev-check against any state changes during May).
3. Commit phase contents: per-phase task list, dependencies, rough hour estimates, ordering.
4. Run brainstorm spec self-review.
5. Hand off to writing-plans skill for implementation plan.

## Time budget

~150h+ across summer. Per-chunk rough estimates from brainstorm (subject to revision):

- gencast offload: done
- Fleeting-notes endpoint: ~5h (hosting only; dev elsewhere)
- Caddy + domain + LE: ~10h
- Syncthing: ~5-8h
- Forgejo: ~10-15h
- Fleeting-notes → MaeNotes sync: ~8-12h
- Restic backups + offsite: ~5-8h
- Immich + Ente migration: ~30-45h
- Personal site: ~5-10h
- Uptime Kuma: ~3h
- Healthchecks self-hosted: ~3h
- Telegram bot: ~10-15h
- Scheduled digest emails: ~5-10h
- `vps-burst` (pueue wrapper): ~10-15h

Total: ~109-159h. Fits 150h budget; uses most of it.
