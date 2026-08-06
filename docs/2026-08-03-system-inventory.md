# System inventory — 2026-08-03

Acer Nitro AN517-51 | Fedora 44 | niri + noctalia session

Read-only audit. Four subagents (secrets, packages, backups, session) plus direct
inspection. Nothing was changed except one accidental write, disclosed in §9.

---

## PRIORITY 1 — Disk has uncorrectable media errors

```
Scrub  Sat 2026-08-01 21:39, 738 GiB in 10m05s
  read=640   Corrected: 628   Uncorrectable: 12

btrfs device stats:  read_io_errs 2151
SMART nvme1n1:       Media and Data Integrity Errors  45
                     Error Information Log Entries    45
                     Percentage Used                  13%
                     Power On Hours               10,801
                     Unsafe Shutdowns                506
                     Warning Comp. Temperature Time  662 min
                     Overall health               PASSED
```

`btrfs-maint.service` shows as failed. It is not broken — it exited **3**, which is
scrub's "errors found" code. The failed unit IS the alarm, and it has been sitting
unread for 1d19h.

**All 12 uncorrectable blocks landed in disposable data.** Four files, all Zen
browser cache:

```
root 256 (= home subvol), inodes 1339745 / 1339685 / 1339681 / 1339669
.zen/6zgfejv9.Default (release)/storage/default/
  https+++slowroads.io^userContextId=8/cache/morgue/{9,254,37,217}/*.final
```

Nothing irreplaceable was lost. Pure luck.

Assessment: 13% wear rules out wear-out. These are isolated media defects on a
Samsung 980. All 45 errors are dated Aug 01; **zero since Aug 02** — because
nothing has re-read those blocks. The four bad files still exist and still pin them.

Suggested (NOT done):
1. Delete the 4 files, or the whole 28M slowroads cache dir.
2. Re-scrub. Should come back clean once the bad blocks are freed and remapped on
   next write.
3. Watch `Media and Data Integrity Errors`. Stable at 45 = isolated defect, fine.
   Climbing = replace the drive.
4. 506 unsafe shutdowns is high and is a plausible contributing cause.

---

## PRIORITY 2 — ~206 GB has no backup path at all

Not git, not yadm, not synced, not snapshotted:

| Path | Size |
|---|---|
| `Desktop/Photo Repository` | 77G |
| `Pictures` | 42G |
| `Videos` | 42G |
| `Documents` | 38G |
| `Music` | 5.1G |
| `podcast-backups` | 1.1G |
| `home-scans` | 542M |
| `Zotero` | 346M |

**Snapper does not cover any of it.** Confirmed:

```
/etc/snapper/configs/    root          (only config)
config root:             SUBVOLUME="/"
btrfs subvolume list /:  ID 256 home        <- your data
                         ID 257 root
                         ID 258 .snapshots  (top level 257 = inside root)
```

30 snapshots exist, oldest Jan 2026, newest hourly — all of `subvol=root` only.
`subvol=home` has never been snapshotted.

The intended safety net is dead:

```
rclone-proton.service: failed
  dial tcp: lookup drive-api.proton.me: Temporary failure in name resolution
  5 retries in <1s -> "Start request repeated too quickly" -> gave up
~/ProtonDrive: exists, empty, unmounted
```

Boot race, not credentials. The fix is already recorded in memory
(`RestartSec` drop-in + `network-online.target`) and was never applied. The folder
looks like a working sync target and is not one.

Installed: rclone, rsync, snapper. Absent: restic, borg, borgmatic, timeshift,
btrbk, deja-dup.

Combined with Priority 1: unbacked data on a disk with confirmed media defects.

---

## PRIORITY 3 — Why wifi credentials don't save

Root cause found. Two Secret Service providers race at login; gnome-keyring wins,
KWallet holds the actual data.

```
org.freedesktop.secrets  ->  gnome-keyring-daemon  PID 1668316
ksecretd (kf6-kwallet)   ->  SIGABRT               PID 1668338
```

PIDs 22 apart — same login, same instant. Two crashes logged:

```
Sat 2026-08-01 21:24:50  SIGABRT  /usr/bin/ksecretd
Sat 2026-08-01 21:46:21  SIGABRT  /usr/bin/ksecretd
```

Cause is duplicated PAM wiring:

```
/etc/pam.d/sddm:
  -auth    optional  pam_gnome_keyring.so
  -auth    optional  pam_kwallet5.so
  -auth    optional  pam_kwallet.so
  -session optional  pam_gnome_keyring.so auto_start
  -session optional  pam_kwallet5.so auto_start
  -session optional  pam_kwallet.so auto_start
```

Three keyring modules in one stack. Both daemons unlock; both want the bus name.

Where the data actually is:

```
~/.local/share/keyrings/login.keyring     3.5k   gnome-keyring, near-empty, WINS the bus
~/.local/share/kwalletd/kdewallet.kwl      16k   KWallet, has the secrets, LOSES the bus
```

NetworkManager PSK flags:

| Connection | key-mgmt | flags |
|---|---|---|
| Adri | sae (WPA3) | 1 = agent-owned |
| Three_1811 | sae (WPA3) | 1 = agent-owned |
| VM0967321 / VM2114764 / VM8787334 | wpa-psk | 1 = agent-owned |
| eduroam | wpa-eap | **0 = stored on disk** (root-only 0600) |
| Dublin Bus / Motel One / Pi-Direct | open | n/a |

`flags=1` means the secret is not on disk — NM asks the Secret Service owner.
That owner is gnome-keyring, which has nothing. Hence the endless prompts.

`org.kde.secretservicecompat` is **already installed** (ships as `ksecretd` in
`kf6-kwallet`). Nothing is missing. It just loses a race.

Three options, none requiring a reinstall:
- A: make KWallet authoritative (drop the gnome-keyring PAM lines)
- B: migrate to gnome-keyring (drop the kwallet PAM lines; re-auth everything)
- C: just fix wifi — set `psk-flags 0` on the 5 networks

Note `/usr/share/xdg-desktop-portal/niri-portals.conf` sets `Secret=gnome-keyring`,
which reinforces B if you go that way.

Other stores are healthy: `pass` (4 entries), GPG RSA4096 ultimate trust
(created 2026-04-12), `bws` CLI + config present.

---

## PRIORITY 4 — Disk space

```
nvme1n1 (Samsung 980, 1TB)  LUKS -> btrfs   930G, 740G used, 135G free (85%)
  subvol=root -> /     subvol=home -> /home     [/home survives a reinstall]
  subvol=swap -> /swap/overflowswap 16G
nvme0n1 (Micron 256G)  NTFS, unmounted, Windows, 30% wear, 0 media errors

btrfs filesystem usage /:
  Data,single    759.01 GiB, used 713.70 (94.03%)   <- ENOSPC risk zone
  Metadata,DUP    40.00 GiB, used  12.21 (30.51%)   <- over-allocated, 80 GiB raw
  Device unallocated  90.78 GiB
```

`$HOME` = 583G.

| Path | Size |
|---|---|
| `.local/share/Steam` | 123G |
| `Desktop/Photo Repository` | 77G |
| `Pictures` | 42G |
| `Videos` | 42G |
| `.local/share/PrismLauncher` | 38G |
| `Documents` | 38G |
| `Games` | 34G |
| `Downloads` | 32G |
| `.local/share/Trash` | **22G** |
| `git` | 22G |

Easy reclaim, no judgement calls:

```
~/.local/share/Trash      22G   77 items, oldest 2026-02-28 (5 months)
~/Downloads (2026-03)   14.5G   untouched since March
/var/log (journald)       4.0G   no SystemMaxUse cap set
/var/spool/abrt           2.2G   82 crash reports
/var/lib/systemd/coredump 2.2G   90 files
/var/cache/libdnf5        519M
dnf autoremove            ~1 GiB (187 leaf packages)
                          ~46 GB total
```

Metadata is over-allocated (40 GiB allocated for 12.21 GiB used). A `btrfs balance`
with a metadata filter would return raw space — but run it AFTER dealing with the
media errors, not before.

---

## PRIORITY 5 — Apps launched from noctalia inherit its cgroup

An earlier reading of "noctalia using 2.3G" was wrong: that was the **service
cgroup**, not the process. The bar itself is fine.

```
noctalia PID 391857:
  VmRSS       93,524 kB   (91 MB)
  VmHWM      418,260 kB   (peak 408 MB)

noctalia.service cgroup:
  MemoryCurrent  1.85 G
  MemoryPeak     4.19 G
  memory.swap.current 1.8 G
```

The gap is other people's processes living in the service cgroup:

```
  391857   90 MB  /usr/bin/noctalia
  394502  334 MB  zen
  ...      20x zen -contentproc          (~2.2 GB total)
  634612   73 MB  dolphin
  612781    5 MB  nvidia-smi dmon -d 2 -s pucm     <- expected, sysmon plugin
  612782    4 MB  ksystemstats_intel_helper        <- expected, sysmon plugin
```

The GPU helpers belong there. Zen and Dolphin do not — they were launched from
noctalia's launcher and inherited its cgroup instead of getting their own scope.

**This is a real risk, not just bad accounting.** systemd kills the entire cgroup
when it stops a service, and the unit has `Restart=on-failure`. If noctalia
crashes or is OOM-killed, it takes the browser and file manager with it — and the
self-healing restart added earlier makes that a live path rather than a
theoretical one.

Fix: launch apps into their own scope (`systemd-run --user --scope`, or `uwsm
app`) rather than as direct children. Worth raising upstream.

Version `noctalia-5.0.0~beta.7-1.fc44`, from `updates-testing`. Correctly run as a
systemd user unit (`WantedBy=niri.service`) rather than `spawn-at-startup`.

---

## PRIORITY 6 — The choom fix has a hole

```
Aug 02 02:49  task=java  oom_score_adj:200
              memcg=/user.slice/.../app-niri-alacritty-1672465.scope
              Killed process 2006050 (java) anon-rss:3330016kB
```

`oom_score_adj` was **200, not 1000**, and the cgroup is an alacritty scope. This
was Java launched from a terminal, bypassing the desktop-file
`WrapperCommand=choom`. The protection only covers GUI launches.

Also `minecraft-launcher` SIGSEGV'd 8 times in 30 minutes on Aug 03.

---

## Stale automation

1. `crontab: */2 * * * * $HOME/bin/memory_check.sh` — **script does not exist**.
   Fires every 2 minutes into nothing. Left over from before
   `memory-notify.service` replaced it.
2. at-job #12 (Nov 15) text says "jump 43 -> 44" — already on 44.
3. Memory note `reference_at_jobs` lists 5 jobs; only 2 remain (#12 Nov 15
   Fedora, #15 Aug 27 Zen archive). Three fired and the note is stale.
4. Two fc43 kernels still installed. At the retention ceiling of 3, so the next
   kernel update prunes automatically — no action needed.
5. Two stale `kmod-nvidia` builds for the fc43 kernels (580.173.02); current is
   610.43.03 for fc44.

---

## Packages

```
9,370 installed
dnf list --extras     119   (~90 = stale texlive-*-doc from fc43)
dnf autoremove        187 leaves, ~1 GiB
  clang19 + clang20 libs side by side (~339 MB)
  inkscape (~187 MB), R stack, kf5-bluez-qt/kf5-purpose leftovers
```

Stale / broken third-party repos:

```
network:im:signal          -> .../Fedora_43/    (system is 44)
github_git-lfs             -> .../fedora/42/    (2 behind)
nvidia-container-toolkit   -> CA cert error, metadata refresh fails
781e4eb5...                -> dead repo, 2 orphaned pkgs, no longer configured
```

5 unmerged `.rpmnew`/`.rpmsave` under `/etc` (cups-browsed, texlive).

Desktop stack:

```
kf6-*  87    plasma-*  46    kde*  27    qt6-*  51    qt5-*  30    gnome-*  25
```

`ksystemstats` (your iGPU sensor source) is installed and has **no dependency on
plasma-workspace** — it installs standalone on any base. Earlier concern retracted.

---

## Session

```
/usr/share/wayland-sessions/: gnome.desktop, niri.desktop, plasma.desktop
/usr/share/xsessions/:        empty
sddm: theme 01-breeze-fedora, autologin OFF
niri: config.kdl + conf.d/ (7 files), 2 pre-refactor .bak (31k, 28k)
      no active spawn-at-startup; noctalia via systemd unit
```

A GNOME session is already installed and selectable — the keyring theory can be
tested today without reinstalling anything.

Portals: your `~/.config/xdg-desktop-portal/niri-portals.conf` sets
`default=gnome;gtk` + `FileChooser=gtk`. Deliberate and working — gnome for
screencast, gtk for file pickers.

Failing user units, triaged:

| Unit | Verdict |
|---|---|
| `kclockd`, `sealertauto` | Cruft under niri — safe to gate off |
| `kdeconnect`, `solaar`, `easyeffects` | Desktop-agnostic, real bugs, worth fixing |
| `xwaylandvideobridge` | Half-done user override, edited 1 Aug 21:53 |
| `plasma-kactivitymanagerd` | Always fails under niri. Harmless |
| `Minecraft@...` | Stale failed unit. `reset-failed` clears it |
| `kalendarac` | Known — covered by the akonadi memory note |

---

## Security

Good:

```
sshd: port 22, permitrootlogin no, passwordauthentication no,
      pubkeyauthentication yes, allowusers cadrianmae
SELinux: Enforcing
LUKS on nvme1n1p3
```

Worth knowing:

```
firewall zone FedoraWorkstation: ports 1025-65535/tcp AND /udp open
Secure Boot: disabled
```

The wide port range is the Fedora Workstation default, not a misconfiguration, but
it is broader than most people assume.

---

## Uncommitted work

```
yadm                            28 unpushed, 2 modified
cs-soc-tudublin/Plume           11 unpushed
cadrianmae/convert-pdf           1 unpushed
tu856-4                         64 dirty
tu856-4-claude                  22 dirty
pandoc_resume                   19 dirty
Advancement-Count               13 dirty
creative-coding                  8 dirty
maeirl / dslr-webcam             6 dirty each
```

68 git repos under `~/git`. The 28 yadm commits are the only work that exists
nowhere but this machine.

---

## §9 — Disclosure

The backups subagent ran `yadm encrypt --list`. That is not a real yadm flag, so it
fell through to `yadm encrypt`, which **created a file**:

```
~/.local/share/yadm/archive   588 bytes, PGP RSA encrypted
```

Verified harmless: not tracked (`yadm ls-files` has no match; the 15 "archive" hits
were `easyeffects/_archive/*` presets), does not appear in `yadm status`, and every
pattern in `~/.config/yadm/encrypt` is commented out per ADR 004 — so it encrypts
an empty set. Safe to `rm` or ignore. Flagged because a read-only audit wrote to
disk.

---

## Non-base packages

9,072 installed; ~90 come from somewhere other than the Fedora repos.

```
[@commandline]  manual rpm -i, no repo, NEVER auto-updates
  ente, figma-linux, nbfc-linux, nbfc-qt, proton-mail, protonmail-bridge,
  qbz, rstudio, spotify-client
  kmod-nvidia x3, kmod-v4l2loopback x3   (two each are for dead fc43 kernels)

[COPR]
  atim:heroic-games-launcher   heroic-games-launcher-bin
  derisis13:ani-cli            ani-cli
  lihaohong:yazi               yazi, resvg
  matinlotfali:KDE-Rounded-Corners  kwin-effect-roundcorners   <- KDE-only, dead under niri
  wezfurlong:wezterm-nightly   wezterm, -common, -gui, -mux-server
  wojnilowicz:ungoogled-chromium  ungoogled-chromium, -common
  ycollet:audinux              supercollider, sc3-plugins, dragonfly-reverb,
                               lv2-dragonfly-reverb, yabridge, zix

[rpmfusion-nonfree]  akmod-nvidia, xorg-x11-drv-nvidia (+cuda/libs/power/kmodsrc),
                     nvidia-modprobe, nvidia-persistenced, nvidia-settings,
                     steam, steam-arch-transition, discord, intel-media-driver,
                     lpf-spotify-client
[rpmfusion-free]     x264/x265-libs, libavcodec-freeworld, vlc-plugins-freeworld,
                     gstreamer1-plugins-{bad-freeworld,ugly}, v4l2loopback,
                     akmod-v4l2loopback, obs-studio-plugin-x264, libde265,
                     libheif-freeworld, libva-intel-driver, pipewire-codec-aptx,
                     svt-hevc-libs, vvenc-libs, libfreeaptx
[docker-ce-stable]   docker-ce, -cli, -rootless-extras, containerd.io,
                     docker-buildx-plugin, docker-compose-plugin
[protonvpn]          proton-vpn-{daemon,gnome-desktop,gtk-app}, python3-proton-*
[nvidia-container-toolkit]  nvidia-container-toolkit(-base), libnvidia-container1,
                     libnvidia-container-tools     <- repo currently broken (CA cert)
[tailscale-stable]   tailscale
[code]               code          [claude-desktop]  claude-desktop-unofficial
[fedora-cisco-openh264]  openh264, mozilla-openh264
[updates-testing]    noctalia
[781e4eb5... dead repo]  hfsutils, pakchois
```

The `@commandline` group is worth knowing: those 9 apps were installed from
downloaded RPMs with no repo behind them, so **nothing ever updates them**.
`dnf history userinstalled` does not exist in dnf5; `dnf repoquery --userinstalled`
reports 816 packages.

`kwin-effect-roundcorners` is a KWin effect — inert under niri.

---

## Browser state

**Zen** (`~/.zen`, active profile `6zgfejv9.Default (release)` = 4.0G)

```
storage/          3.8G     <- storage/default alone is 3.7G, 2,036 site dirs
extensions/        76M
zen-sessions-backup 35M
places.sqlite      35M
favicons.sqlite    31M
```

Ten largest site-storage dirs total ~2.34G — over half the profile:

| Site | Size |
|---|---|
| web.whatsapp.com (container 8) | 405M |
| piper.ttstool.com | 315M |
| piper.ttstool.com (container 8) | 314M |
| read.readwise.io (container 8) | 290M |
| read.readwise.io | 287M |
| onlinesequencer.net (container 8) | 226M |
| tudublin-my.sharepoint.com | 137M |
| web.whatsapp.com | 131M |
| tudublin-my.sharepoint.com (container 8) | 130M |
| tudublin.sharepoint.com (container 8) | 106M |

Several sites appear twice — once bare, once under Multi-Account Container 8 —
roughly doubling their footprint.

Extensions: **47 total, 25 disabled.** The memory note's "~30" was low.

`profiles.ini` lists 6 profiles; only 2 exist on disk. Four are ghost entries, and
`installs.ini` has a dead pointer to `1tb2fgff.Default (release)-3` which does not
exist. `hshixjas.Default Profile` is flagged `Default=1` but is empty (4K) and
referenced by nothing. Clutter only, no disk impact.

`browser.cache.disk.capacity` is **not set anywhere**. The backlog item to "reset
the 500MB cache pref" has nothing to reset — the pref was never applied. Zen is on
Firefox's automatic cache sizing.

Also on disk:

```
~/.zen/6zgfejv9.Default (release).zip          264M  backup, Sep 2025
~/.zen/_ARCHIVE-DELETE-AFTER-2026-08-27        172M  <- at-job #15 covers this
```

**Other browsers**

```
~/.mozilla                 66M   stock Firefox, real profile, untouched ~11 months
~/.config/opera            66M   real profile, last used 2026-06-09
~/.config/chromium        408M   1 profile, 3 extensions (incl. Claude)
~/.cache/chromium         1.5G   plain cache
google-chrome / BraveSoftware / microsoft-edge / vivaldi   4.0K each, empty stubs
```

---

## Global installs

| Tool | Size | Verdict |
|---|---|---|
| ghcup + cabal | **6.9G** | **Stale.** GHC 9.6.7, but *two* cabal versions and *two* stack versions. Package index last fetched 2026-01-28 — no build activity in ~7 months. ghcup itself flags its own install as "stray". |
| VS Code | **11.2G** | Active. 126 extensions (Java/Python/C++/cloud/LaTeX/remote). `~/.vscode` 7.2G is almost all `extensions/`; `~/.config/Code` holds CachedExtensionVSIXs 1.4G + WebStorage 1017M + Cache 410M. |
| JetBrains | 4.7G | Borderline. IntelliJ IDEA Ultimate via Toolbox, installed Oct 2025, config last touched 2026-05-04. Nothing in ~3 months. |
| nvim | 2.5G | Active. mason 1.3G, lazy 1.1G (103 plugins, 64 treesitter parsers). `kulala.nvim` is 104M on its own. |
| pyenv | 1.6G | Global is `system`, not any pyenv version. 3.8.20 stale since 2025-10-21. |
| rustup + cargo | 2.0G | Active. One toolchain (stable). 9 binaries, refreshed as recently as 2026-07-25. |
| R | 653M | Active-ish. 38 packages, last touched 2026-06-10. |
| pipx | 552M | Active. `convert-pdf`, `gencast` — both yours. |
| go | — | Active. `ghq` touched last month; `pomodoro` is your own build. |
| npm globals | 180M cache | claude-code, mermaid-cli, electron, httpyac, asar, mermaid-filter |
| uv | — | No tools installed. |

Reclaimable with high confidence: **~8.7G** (Haskell 6.9G + VS Code caches 1.8G).
Up to ~15G if pyenv 3.8.20 and JetBrains also go.

---

## Peripherals, timers, misc

**Timers** — all system timers healthy and firing (snapper-timeline 15 min ago,
fstrim weekly, logrotate, plocate, dnf-makecache, unbound-anchor). User timers
fine except `drkonqi-sentry-postman.timer`, which has **never** run. Benign.

**Bluetooth** — adapter on, 9 paired: Polaroid P1, LG-PN7, WH-1000XM6, WH-1000XM4,
Xbox Wireless Controller, Spark 2 Audio, SRS-X11, Intuos BT S tablet, cadrimae-s23.

**Input** — Keychron Link, Logitech Unifying receiver → MX Anywhere 2S + K540/K545.
That receiver is what `solaar` targets, which is the failing unit worth fixing.
`libinput list-devices` needs root; skipped.

**Printers** — cupsd running and listening on 631, **zero destinations configured**.

**Containers**

```
docker daemon: INACTIVE
~/.local/share/docker/volumes   2.3G   <- orphaned, nothing references them
podman: 4 images (~1.3G) — ss-a2:dev 529M, dangling <none> 526M,
        fedora:43 187M, ubuntu:24.04 81M; 0 containers
```

**Tailscale** — this node `cadrianmae` 100.114.32.29 online. Two peers both long
dead: `cadrimae-s23` last seen 83 days ago, `mae-vps` 81 days ago. No exit node,
no subnet routes.

**Locale/time** — `en_IE.UTF-8`, keymap `ie`, Europe/Dublin, NTP synced. RTC is on
local time, which is correct for the dual-boot Windows install.

**Power** — **no power-profile daemon at all.** Neither `power-profiles-daemon`
nor `tlp` is installed or running; `powerprofilesctl` exits 4. Unusual for a
laptop — no thermal/performance profile switching. Note the disk reported 662
minutes above its warning temperature.

**Fonts** — 2,223 system-wide; 152 user files. Atkinson Hyperlegible, OpenDyslexic
(4 variants), Sylexiad Sans, Cascadia/CaskaydiaCove, Fira Code, Atkynson Mono,
Intone Mono, Twemoji.

**Icon themes** (`~/.local/share/icons`, 725M) — three Papirus variants (436M) and
three Tela-circle variants (180M) installed at once; only one of each can be
active. Breeze_RC + Breeze_Dark_RC (50M) are Plasma leftovers. No
`~/.local/share/themes` or `~/.themes` at all.

**Windows disk** — `/dev/nvme0n1` p2/p3 NTFS, unmounted, absent from fstab.
Untouched, as expected.

---

## Reclaimable summary

| Item | Size | Confidence |
|---|---|---|
| Haskell (ghcup + cabal, no activity since Jan) | 6.9G | High |
| Trash (77 items, oldest Feb 2026) | 22G | High |
| Downloads from March 2026 | 14.5G | Your call |
| Zen site storage (WhatsApp/SharePoint/Readwise) | ~2.3G | Your call |
| ~~Docker orphaned volumes~~ | ~~2.3G~~ | **RETRACTED** — they are named project volumes (open-notebook-stack, snappy-fyp). Rebuildable, but a blanket prune destroys FYP build state. |
| VS Code CachedExtensionVSIXs + caches | 1.8G | High — auto-rebuilds |
| journald (uncapped) | 4.0G | High |
| ABRT spool (82 reports) | 2.2G | High |
| systemd coredumps (90 files) | 2.2G | High |
| dnf autoremove (187 leaves) | 1.0G | High |
| Duplicate icon themes (all but Papirus-Dark + hicolor) | 696M | High — inheritance verified |
| libdnf5 cache | 519M | High |
| Zen backup zip (Sep 2025) | 264M | Your call |
| JetBrains IntelliJ (idle ~3 months) | 4.7G | Low-medium |

Roughly **45G** at high confidence, ~65G if the judgement calls go the same way.
Current free space is 135G of 930G.

---

## Follow-ups, now closed

### Docker volumes — NOT orphaned junk

Read off disk without starting the daemon. They are named volumes belonging to
live projects:

```
873M  open-notebook-stack_frontend_node_modules
802M  open-notebook-stack_hf-hub-cache
208M  snappy-go-mod          <- FYP
163M  snappy-go-build        <- FYP
139M  snappy-whisper-cache   <- FYP
 80M  open-notebook-stack_frontend_next
128K  supabase_edge_runtime_glfmxlvhhpdjaymabzsw
 48K  snappy-data            <- FYP
   0  2 anonymous volumes
```

All rebuildable caches, but tied to real repos. **Revise the earlier "2.3G
orphaned, reclaimable" line down** — a blanket `docker volume prune` would throw
away FYP build state. The two 0-byte anonymous volumes are the only free win.

### Active theme

```
icons   Papirus-Dark      (gtk-3.0, gtk-4.0, gsettings, kdeglobals all agree)
GTK     Breeze
cursor  Posy_Cursor
noctalia palette  Lumae-Midnight (custom) / Oxocarbon (community)
```

Inheritance checked — **Papirus-Dark inherits `breeze-dark`, not `Papirus`** — so
the 377M base theme is independent and safe to drop.

```
KEEP   Papirus-Dark    30M      DROP  Papirus         377M
       hicolor        1.5M            Tela-circle x3  180M
                                      BeautySolar      60M
                                      Papirus-Light    29M
                                      Breeze_RC x2     50M
                                                      696M reclaimable
```

Note: Papirus-Dark inheriting `breeze-dark` means the active icon theme depends on
a **KDE** package — another quiet KDE dependency in the niri session.

### Obsidian / Anki / Zotero

```
Obsidian: 4 vaults registered, MaeNotes open
  MaeNotes                          9.4G   <- active, and in the unbacked set
  The Nexus Vault
  Documents/Computer Science TU856
  git/github.com/cadrianmae/snappy-fyp
  ~/.config/obsidian                1.6G

Anki:   collection.anki2  393K, last modified 13 Mar (5 months idle)
        AnkiProgramFiles  689M
Zotero: zotero.sqlite     7.1M, last touched 25 Apr; storage 310M
```

`MaeNotes` alone is a quarter of the `Documents` total and has no backup.

### Zen extensions

36 user-installed (the earlier "47/25" counted Firefox's built-in themes):
**21 disabled, 15 active.**

Disabled: AWESOME THEME, AdBlock, Bionic Reader, Blur Neon, Broken Link Checker,
Dreamer–Bold, DuckDuckGo, Firefox Color, Fleeting Notes, HighlightAll, Markdown
Viewer, Markdown Viewer Webext, Open Multiple URLs, Popup window, Proton Pass,
Purple Night, Readwise, Sidebery, The Camelizer, Tree Style Tab, Tridactyl.

Active: Bitwarden, Browser Control MCP, Copy Selected Tabs, Dark Reader, Export
Cookies, Multi-Account Containers, Forest, I still don't care about cookies,
Obsidian Web Clipper, Read Aloud, Readwise Highlighter, Return YouTube Dislike,
Todoist, Zotero Connector, uBlock Origin.

No conflicts — just accumulation. Proton Pass is disabled while Bitwarden is
active, consistent with the keyring findings. Two Markdown Viewers both off;
`Readwise` off while `Readwise Highlighter` is on; `AdBlock` off while `uBlock
Origin` is on.

### Input devices

`libinput list-devices` still needs root (askpass went unanswered). From `/proc`
and `/dev/input/by-id`:

```
Keychron Link (dongle)   mouse0, event5-8, and a JOYSTICK node js0/event7
Logitech USB Receiver -> MX Anywhere 2S + K540/K545     <- solaar's targets
SYNA7DB5 touchpad + mouse
AT Translated Set 2 keyboard, Lid/Sleep/Power, Video Bus x2,
Acer Wireless Radio Control, Acer WMI hotkeys, PC Speaker,
HDA NVidia HDMI/DP x4, HDA Intel PCH Front Headphone
```

Two things worth knowing:

1. **Keyboard layout diverges.** `localectl` reports X11 layout and keymap `ie`,
   but `~/.config/niri/conf.d/input.kdl` sets `xkb layout "gb, us"` (variant
   `", altgr-weur"`, model `pc104alt`, `caps:escape_shifted_capslock`). niri wins
   in the Wayland session, so a drop to a TTY lands on a different layout.
2. The Keychron dongle exposes a **joystick node**. Harmless, but games sometimes
   detect it as a phantom controller.

Touchpad config: `tap` and `natural-scroll` both on.

---

### Obsidian vault activity

Measured by newest `.md` mtime, excluding `.git`/`node_modules`/`.obsidian`:

```
OPEN  3291 md  newest 2026-07-31 ( 3d ago)  Documents/MaeNotes
      2702 md  newest 2026-05-04 (91d ago)  Documents/Computer Science TU856
       911 md  newest 2026-05-05 (90d ago)  Documents/The Nexus Vault
      5154 md  newest 2026-04-30 (95d ago)  git/.../snappy-fyp
```

The three quiet vaults all stopped within a week of each other, Apr 30 – May 5 —
exactly when the FYP was submitted. They are **finished, not stale**: academic-year
archives. `MaeNotes` is the only live vault. Nothing here needs pruning, but it
does mean 9.4G of the unbacked set is actively changing while ~3 vaults' worth is
static history that would be equally painful to lose.

### Anonymous docker volumes

```
b4b6f8554ec8/_data   empty, created 24 Mar 14:35
c867ebc51ef9/_data   empty, created 24 Mar 14:35
metadata.db: both labelled "anonymous", no com.docker.compose.project owner
```

No project claims them, both 0 bytes. Safe to remove — tidiness, not space.

---

### libinput capabilities

Run manually (sudo has no TTY in an agent session, and neither `ksshaskpass` nor a
zenity `SUDO_ASKPASS` helper could raise a dialog).

```
SYNA7DB5:01 06CB:CD41 Touchpad   /dev/input/event13   103x75mm
  Capabilities:    pointer gesture
  Scroll methods:  *two-finger  edge
  Click methods:   *button-areas  clickfinger
  Tap button map:  left/right/middle
  Disable-w-typing:        enabled
  Disable-w-trackpointing: enabled
  Accel profiles:  flat *adaptive custom

Keychron Link            event5   pointer            scroll=button (BTN_MIDDLE)
Keychron Link Keyboard   event8   keyboard pointer   scroll=none
Logitech MX Anywhere 2S  event9   keyboard pointer   scroll=button (BTN_MIDDLE)
```

**Do not read the touchpad's `Tap-to-click: disabled` / `Nat.scrolling: disabled`
as a conflict with `input.kdl`.** `libinput list-devices` opens its own libinput
context and reports device *defaults*; it cannot observe runtime configuration a
compositor applies through its own context. niri sets `tap` and `natural-scroll`
live, and they are in effect.

Click method is `button-areas` (default — bottom of the pad split into zones).
`clickfinger` is supported if preferred on a pad this size.

Correction to an earlier note: the Keychron dongle's joystick node **does not
appear in libinput output at all** — libinput ignores joystick devices. So it is
inert for niri and anything using libinput; only software reading `/dev/input/js0`
directly (games, emulators) would see a phantom controller.

---

## Still not covered

Nothing outstanding.
