# Upgrade Fedora to a new release

Major-version upgrade via `dnf system-upgrade`. Plug the laptop in — never run on battery.

## Prerequisites

- [ ] On AC power
- [ ] Free disk space ≥ 10 GB on `/`
- [ ] Recent backup or known-good restore point

## Procedure

```bash
# 1. (Only if needed) Import GPG key for new release
sudo rpm --import https://fedoraproject.org/static/keys/RPM-GPG-KEY-fedora-43-primary

# 2. Download upgrade packages
sudo dnf system-upgrade download --releasever=43

# 3. Reboot into the upgrade environment
sudo dnf system-upgrade reboot
```

The system reboots, runs the upgrade in offline mode, and reboots again into the new release.

## Post-upgrade checklist

```bash
# Clean up packages left over from the previous release
sudo dnf distro-sync

# /boot space — old kernels accumulate here
df -h /boot

# Remove old kernels if /boot is > 80 % full
sudo dnf remove kernel-{core,modules,}-<old-version>

# Bring rootless docker containers back up
docker start <name>

# Re-enable COPR repos that need a per-release nudge
sudo dnf copr enable <user>/<repo>

# Sanity-check NVIDIA module against the running kernel
lsmod | grep nvidia
rpm -q kmod-nvidia | sort
```

If NVIDIA isn't loaded after the upgrade, see [Troubleshoot NVIDIA driver mismatch](troubleshoot-nvidia.md).

## Verification

- New terminal sessions open with the expected shell + theme
- `cat /etc/fedora-release` reflects the new version
- KDE / Niri session logs in cleanly
- Steam, Zen, Obsidian launch without missing-library errors
- `journalctl -p err -b` is quiet on first boot

## Recovery

- Boot with `nomodeset` if graphics fail — see [NVIDIA runbook](troubleshoot-nvidia.md)
- KDE panel applets rendering black? — see [KDE applets runbook](troubleshoot-kde-applets.md)
- If `dnf system-upgrade` aborts mid-download, rerun it; it resumes from where it left off

## Related

- [NVIDIA mismatch](troubleshoot-nvidia.md)
- [KDE panel applets](troubleshoot-kde-applets.md)
