# Troubleshoot NVIDIA driver mismatch

Partial NVIDIA updates leave the kernel module out of sync with userspace, which manifests as Qt/KDE crashes and missing libraries — not always as obvious "no graphics" failures.

## Symptoms

- Qt symbol errors: `undefined symbol: _ZN…Qt_6.9_PRIVATE_API`
- KDE applications fail to start (KClock, Plasma widgets, …)
- Missing-library errors at app launch
- Graphics glitches after an update
- System unable to boot post-update (worst case)

## Diagnose

```bash
# Pending updates that may be stuck mid-transaction
dnf check-update

# Current driver versions across all NVIDIA packages
rpm -qa | grep -i nvidia | sort

# Broken dependencies
dnf check
```

## Fix

```bash
# 1. Full sync of the package set (preferred path)
sudo dnf upgrade --refresh

# 2. If divergence persists, force everything onto matching versions
sudo dnf distro-sync

# 3. Rebuild kernel modules against the running kernel
sudo akmods --force

# 4. Reboot
sudo reboot
```

## Emergency recovery — won't boot

1. Reboot, edit GRUB entry, append **`nomodeset`** to the kernel line.
2. Boot, then:

   ```bash
   sudo dnf upgrade --refresh
   sudo akmods --force
   ```

3. Reboot normally without `nomodeset`.

## Prevention

- Run **full** `dnf upgrade` rather than partial updates of single packages.
- Don't mix package sources for the NVIDIA stack (RPM Fusion + Fedora primary). Pick one origin.
- After an NVIDIA-related update, run `dnf check-update` *before* rebooting.

## Related

- [Upgrade Fedora](upgrade-fedora.md) — the major-version flow that often surfaces these mismatches
