# Post-reinstall recovery — 2026-08-08

Everything done in one long session, two days after the Fedora 44 reinstall.
Companion to `2026-08-03-system-inventory.md` (the pre-reinstall audit) and
`~/reinstall-kit/2026-08-03/RESTORE.md` (the procedure).

The value here is not the config — that is in git. It is the **traps**: each one
cost real time, each was invisible until it wasn't, and several would recur on
the next rebuild.

---

## Where the machine ended up

```
Fedora 44 · kernel 7.1.7-200 · niri + noctalia · gdm
NVIDIA 610.57.04 (hybrid, PRIME offload) · nouveau + nova_core blacklisted
swap 24G pri=10 + 20G reserved hiberfile · zswap zstd/zsmalloc 25% · zram masked
hibernation verified 4 cycles, twice after the driver bump
~1025 packages from a 436-package triage
```

---

## Traps, in the order they bit

### 1. Noctalia registers a NetworkManager secret agent that cannot do the job

`org.noctalia.SecretAgent` looks like a replacement for `nm-applet`. It is not.
`GetSecrets` only ever prompts — it never reads Secret Service — and
`SaveSecrets` is an **empty stub that returns success and stores nothing**.

So wifi cannot auto-connect at boot on noctalia alone, and any password NM asks
it to persist is silently dropped. That is what swallowed a corrected PSK: the
connection worked in-session while the keyring kept the older, wrong value.

`nm-applet` is mandatory, and arrives via `/etc/xdg/autostart/nm-applet.desktop`
(`NotShowIn=KDE;GNOME;` — niri is neither). **Do not write a systemd unit for
it**: it forks, so the unit reports `inactive` while the process runs and
`Restart=` supervises nothing.

Upstream issue #2367 asked for Secret Service support and was closed
NOT_PLANNED as v4 housekeeping, with a note to revisit for v5. Not filed.

### 2. Two gnome-keyring daemons race, and pam loses

`gkr-pam: unable to locate daemon control file` at auth time is **benign** — pam
stashes the password and delivers it at session-open. The real failure was
subtler:

```
22:24:42  gkr-pam: gnome-keyring-daemon started properly and unlocked keyring
22:24:42  gnome-keyring-daemon.socket ActiveEnterTimestamp
```

Both in the same second. Only one process can own `org.freedesktop.secrets`; the
socket-activated one won, and it never received the stashed password. pam's
daemon lost the bus name and exited, taking the unlocked state with it.

Fix: `systemctl --user mask gnome-keyring-daemon.socket gnome-keyring-daemon.service`
so pam owns the daemon outright.

### 3. Hibernation: the resume pointer must be cleared on resume

systemd 259 on UEFI records the location in the `HibernateLocation` EFI variable
— there is **no `resume=` or `resume_offset=` any more**, and nothing to
recompute when a swapfile is recreated. The old procedure in `HARD-SETUPS.md`
was obsolete.

The replacement trap: `hibernate-resume.service` swaps the reserved file off but
must also clear `/sys/power/resume`, or the kernel keeps pointing at a file that
is no longer active swap:

```
Call to Hibernate failed: Specified resume device is missing or is not an
active swap device
```

The first hibernate of a boot succeeds and every later one fails. **A single
test cycle cannot catch this, and a single cycle is what everyone tests.**

Also: `pri=100` on the reserve is load-bearing. `find_hibernate_location()` takes
the highest-priority swap and, per systemd#20761, does not fall back to a larger
one at lower priority.

### 4. akmod-nvidia installs a PARTIAL kernel

It needs `kernel-devel`, which pulls `kernel-devel-matched` → `kernel-core` →
`kernel-modules-core`. **None of those depend on `kernel-modules`** — only the
`kernel` metapackage does. Result: a newer kernel missing most drivers including
`iwlwifi`. It boots, with no wifi and no session, and nothing says why.

The tell is the initramfs size — 44M against the old kernel's 160M — and it was
visible an hour before the failed boot. `sudo dnf upgrade` fixes it.

Related: check the kernel that will **boot**, not the running one. akmods can
only build for a kernel that has `kernel-devel`, so `modinfo nvidia` reports
nothing while the build succeeded.

### 5. Restoring `.repo` files gives you repos that cannot verify anything

The GPG keys ship **inside `rpmfusion-*-release`**, not in any file
`collect-root.sh` captures. Copying the `.repo` files produces repos that list as
enabled, download happily, then abort mid-transaction:

```
cannot open file: /etc/pki/rpm-gpg/RPM-GPG-KEY-rpmfusion-free-fedora-44
```

`restore-repos.sh` now runs each vendor's own install command instead.

### 6. bw CLI 2026.3.0 returns a session token that never unlocks

[bitwarden/clients#20703](https://github.com/bitwarden/clients/issues/20703).
`bw unlock` returns a correct 88-char token, `bw status` still says `locked`,
every later command re-prompts. Fixed in 2026.7.0.

It was hard to spot because `bootstrap` ran `bw get password "$ITEM" 2>/dev/null`
— inside `$( )` the re-prompt had nowhere to read from, so the script reported
**"item not found in bw vault"** for an item that existed with a populated
password field.

### 7. The BWS → pass pipeline had never worked

Two independent bugs hiding each other:

- `yadm-refresh-secrets` delegated to bootstrap without `--all`, and step 5 skips
  any pass entry that already exists. The default path could only ever SEED,
  never refresh.
- The manifest asked for `anthropic-api-key`; BWS actually holds
  `ANTHROPIC_API_KEY`. Every lookup missed — invisible, because the skip above
  meant the lookup never ran.

So the 30-day TTL and the staleness timer were reporting on a pipeline that
could not update anything.

### 8. GRUB paints `+ image` above `boot_menu`, whatever the file says

An opaque window behind the menu hides every label. Elegant's own `info.png`
works only because it is transparent exactly where the menu sits. The failure
looks like a font problem — background and frame render, text does not — and
fonts were fine throughout.

Elegant's text is **pixels, not labels**: "Select Your System" is baked into
`info.png`. gfxmenu exposes only `__timeout__`.

Also: install with `-b`. `/boot` is separate and unencrypted, `/` is LUKS, so a
theme under `/usr/share/grub` is unreadable at menu-draw time.

### 9. Noctalia raced PipeWire, and volume silently did nothing

`noctalia msg volume-set 60` returned `ok` and moved no sink. At boot noctalia
and wireplumber both started at `21:23:27` — the unit ordered itself only after
`niri.service`. Restarting fixed it instantly, which is the signature of a
startup race.

Separately, the volume keys called `wpctl` directly while brightness went through
noctalia — which is why brightness showed an OSD and volume never did.

### 10. niri exports `XCURSOR_THEME=default` unless told otherwise

Posy_Cursor was installed and named in both gsettings and `settings.ini`, and the
pointer stayed Adwaita. niri hands every client its own `cursor` block; with no
block it exports `default`, which wins.

### 11. nbfc: the stock config cannot control these fans

No `AN517-51` config exists upstream. `AN515-51` / `AN715-51` / `AN517-54` all
use identical registers, but the **stock config has no
`RegisterWriteConfigurations`** — so writes to `0x37`/`0x3a` are ignored and the
firmware keeps control. That is the "read works, write fails" symptom in nbfc
issues #188 and #219.

The custom config flips manual mode first:

```
Register 34 (0x22) = 12   CPU fan manual mode
Register 33 (0x21) = 48   GPU fan manual mode
Register 16 (0x10) = 0    CoolBoost off
```

EC access is `dev_port` — Fedora sets `CONFIG_ACPI_EC_DEBUGFS is not set`, so
`ec_sys` cannot exist. The two `modprobe: FATAL` lines at startup are **normal**.

### 12. Things that look like cleanup and are not

- **2.5G of `nvidia/` CUDA wheels** in user site-packages power piper TTS
  (`use_cuda=True`). Not FYP leftovers.
- **`~/.wine`** hosts four VST3s bridged to Reaper.
- Genuinely dead, and removed: `~/.local/lib/python3.13` (8.8G, orphaned when
  Fedora moved to 3.14) and rootless `~/.local/share/docker` (2.3G).

---

## Where things live

```
~/scripts/hibernate/     01-swap-zswap.sh, 02-nvidia.sh, 03-hibernate.sh,
                         04-test-cycles.sh   (all idempotent, commented)
~/scripts/system/        grub-lumae.sh, grub-background.sh
~/scripts/ptt/           ptt-daemon.c + justfile + udev rule
~/.local/share/grub-lumae/   theme assets, window PNGs, blurred backgrounds
~/reinstall-kit/2026-08-03/  RESTORE.md, HARD-SETUPS.md, restore-repos.sh,
                             collect-root.sh, kwallet-to-keyring.sh
```

USB stick (`MAE`, `RESTORE-BOOTSTRAP/`) carries RESTORE.md, HARD-SETUPS.md,
restore-repos.sh, collect-root.sh, kwallet-to-keyring.sh — all byte-verified.

---

## Still open

- noctalia secret-agent issues — drafted, unfiled (bug: `SaveSecrets` discards;
  feature: read Secret Service, refile of #2367)
- `rclone-proton.service` fails every boot on a DNS race; fix known, unapplied
- noctalia's cgroup swallows apps launched from its launcher
- `~1G` of FYP python residue (chromadb, litellm, playwright) — deliberate keep
  for now; `import piper` is the canary
- `~/.local/share/Trash` 1.6G
- grub Lumae theme — parked, needs artwork rather than config
- WH-1000XM6 maps to the `Default` EasyEffects preset, not a tuned one
- `qt6ct` fonts unset (stored as base64 QVariant; set them in the GUI)
- **EasyEffects is not in the audio path.** `process-all-outputs` is unset, the
  default sink is the hardware sink, and `easyeffects_sink` has zero clients —
  so the loaded `Nitro 5 AN517 Speakers` preset is applied to nothing. Enable
  "Process All Output Streams" in EE Preferences. Until then `screenrec`'s
  pre-effects capture records silence and falls back is not triggered, because
  the monitor source exists but carries no audio.

### Resolved: Intel iGPU missing from `mae/sysmon`

The widget read the iGPU through `/usr/libexec/ksystemstats_intel_helper`,
which ships with KDE's `ksystemstats` — dropped with the rest of Plasma. The
probe was `fileExists(HELPER)`, so the row was correctly omitted rather than
broken; nothing looked wrong, the iGPU simply was not there.

Reinstalling `ksystemstats` would drag KIO, NetworkManagerQt, Solid and
libksysguard back in. `intel_gpu_top` reads the i915 PMU and needs
`CAP_PERFMON` (`perf_event_paranoid` is 2 here). `nvtop` was already
installed, reads DRM fdinfo unprivileged, covers both cards, and has emitted
JSON under `-s`/`-l` since 3.x.

So both GPUs now come from one stream, `~/bin/sysmon-gpu`, which reframes
nvtop's multi-line JSON into one line per GPU per tick. That also let the
widget drop a duplicated stream: one ownership, respawn and staleness path
instead of two, and availability discovered from nvtop's device list rather
than guessed from which binaries exist.

Two things to know:

- `nvidia-smi dmon`'s `mem` column was memory *bandwidth*; nvtop's `mem_util`
  is VRAM *occupancy*. The panel renders only usage and temp, so nothing
  visible changed.
- **noctalia's Luau sandbox has no `os` library.** `os.getenv("HOME")` fails
  the entire chunk at load with `attempt to call a nil value`, same class as
  the absent `require`/`load`. Paths must be absolute.

Reload without restarting the service — a restart kills noctalia's cgroup and
takes launcher-spawned apps with it:

```bash
noctalia msg plugins disable mae/sysmon && noctalia msg plugins enable mae/sysmon
```

### Trap: removing flameshot/ksnip silently takes `grim`

`sudo dnf remove flameshot ksnip` removed **7** packages, not 2. `grim` had been
pulled in as a dependency, so dnf counted it as an orphan and took it — along
with `kimageannotator`, `kcolorpicker` and the Qt variants. Every Print bind
broke at once with `grim: command not found`, which reads as a niri or bind
problem rather than a package one.

Reinstalled explicitly, so `grim`, `slurp` and `wf-recorder` are now
user-installed and safe from the next autoremove. Check with:

```bash
dnf repoquery --userinstalled | grep -E '^(grim|slurp|wf-recorder)'
```

---

## Commits (15)

```
019345a  feat(swap)       rebuild swap, zswap and hibernation as scripts
9c7f8b8  feat(nvidia)     install 610.43.03, hibernation re-verified
6ed8480  feat(pkg-triage) banner when crossing into a new group
0d1649f  feat(pkg-triage) --preview and the P key
4322f31  fix(pkg-triage)  keep MANUAL packages out of the dnf line
e6c1768  fix(bootstrap)   stop reporting bw and yadm failures as the wrong thing
d72cb53  fix(secrets)     default refresh could seed but never update
a33bca1  fix(hibernate)   gate each test cycle on a keypress
c88bdb8  fix(secrets)     manifest bws names never matched the real BWS keys
513f56f  feat(niri)       hide the Xwayland Video Bridge window
b68d3b1  feat(grub)       Elegant theme, custom background, Lumae parked
d4eca6f  feat(theming)    adw-gtk3-dark for GTK, qt6ct for Qt
fe31e00  fix(niri)        volume keys through Noctalia, order after PipeWire
ddee010  fix(niri)        set the cursor theme so Posy_Cursor applies
5fc3b1d  fix(backup,ptt)  exclude the leaked-key file; drop KDE askpass
```

Memory files written: `project_noctalia_secret_agent_gap`,
`reference_bw_cli_session_regression`, `project_user_site_packages_cuda`,
`project_nbfc_fan_control`.
