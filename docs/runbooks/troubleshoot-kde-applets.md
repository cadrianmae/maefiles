# Troubleshoot KDE panel applets

Recurring KDE quirks after Plasma upgrades.

## Black / unreadable text in third-party panel applets

After a Fedora upgrade, third-party panel applets — Window Title Fork, Thermal Monitor, Minimal Chaac Weather, etc. — can render with black-on-dark text because Plasma's colour-token names changed underneath them.

### Fix

1. Install [Panel Colorizer](https://store.kde.org/p/2130967) from the KDE Store.
2. Open its settings, toggle any value, and apply.

That single round-trip forces a colour refresh across every panel widget, which adopts the current colour scheme correctly.

## Built-in speakers vanished from audio settings

Symptom: after a session restart, the built-in speakers no longer appear in System Settings → Audio. Only HDMI / Bluetooth / mic options remain.

### Cause

The device profile silently switched to **input-only**.

### Fix

System Settings → Audio → device → Profile → set back to **Stereo Duplex**.

## Related

- [Troubleshoot NVIDIA mismatch](troubleshoot-nvidia.md) — overlapping symptoms after major upgrades
- [Upgrade Fedora](upgrade-fedora.md)
