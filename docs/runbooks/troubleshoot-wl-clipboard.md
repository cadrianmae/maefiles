# Troubleshoot wl-clipboard focus theft / fullscreen exit

## Symptom

Every time you copy in kitty + tmux (via `tmux-yank`), or run `wl-copy` directly, a window briefly steals focus from the active terminal. If the terminal is fullscreen, KWin drops it out of fullscreen.

The window is invisible (1×1 px) but real — its title is `wl-clipboard`.

## Root cause

`wl-clipboard` ≤ 2.2.x doesn't speak the `ext-data-control-v1` Wayland protocol. To set the clipboard selection it has to fall back to a hack: spawn a tiny `xdg_toplevel`, grab keyboard focus to obtain a valid input serial, call `wl_data_device.set_selection`, then destroy the surface. KWin honours the focus change strictly, so the previously focused window loses focus and exits fullscreen.

Confirmed via:

```bash
echo test | WAYLAND_DEBUG=1 wl-copy 2>&1 | grep -iE 'surface|toplevel'
```

You'll see `wl_compositor.create_surface`, `xdg_surface.get_toplevel`, `xdg_toplevel.set_title("wl-clipboard")`, then `wl_keyboard.enter` on the new surface.

## Fix

Upgrade to `wl-clipboard` ≥ 2.3.0 — that release added `ext-data-control-v1` support (contributed by KWin's Vlad Zahorodnii). With it, no surface is created and no focus is stolen.

Fedora 43 ships 2.2.1 in the main repo, so build from source until a newer build lands.

### Build from source (user-local)

```bash
sudo dnf install meson wayland-devel wayland-protocols-devel
git clone https://github.com/bugaevc/wl-clipboard.git \
  ~/git/github.com/bugaevc/wl-clipboard
cd ~/git/github.com/bugaevc/wl-clipboard
meson setup build --prefix=$HOME/.local
ninja -C build install
# When prompted to use sudo for fish system-wide completions: say n.
# Only ~/.local/bin/wl-copy and ~/.local/bin/wl-paste are needed.
```

Make sure `~/.local/bin` is before `/usr/bin` in `PATH`, then refresh the shell hash table:

```bash
hash -r
which wl-copy        # should resolve to ~/.local/bin/wl-copy
wl-copy --version    # should report 2.3.0
```

### Verify the fix

```bash
echo test | WAYLAND_DEBUG=1 wl-copy 2>&1 | grep -iE 'ext_data_control|surface|toplevel'
```

Expect `ext_data_control_manager_v1` and **no** `create_surface` / `xdg_toplevel` lines. Fullscreen flicker should be gone.

## Alternative workarounds

If you can't upgrade `wl-clipboard`:

- **Bypass `wl-copy` from tmux**: use kitty's OSC 52 passthrough so `tmux-yank` never invokes `wl-copy`.
  ```tmux
  set -g set-clipboard on
  set -g allow-passthrough on
  set -g @override_copy_command 'kitten clipboard'
  ```
- **KWin focus-stealing prevention** at Extreme — blunt, affects other apps:
  ```bash
  kwriteconfig6 --file kwinrc --group Windows --key FocusStealingPreventionLevel 4
  ```

## References

- [bugaevc/wl-clipboard #242 — Support ext-data-control](https://github.com/bugaevc/wl-clipboard/issues/242)
- [bugaevc/wl-clipboard #268 — KWin focus stealing spawns wl-clipboard window](https://github.com/bugaevc/wl-clipboard/issues/268)
- [bugaevc/wl-clipboard #12 — wl-paste relies on its surface stealing focus](https://github.com/bugaevc/wl-clipboard/issues/12)
- [KWin MR !6606 — Port to ext-data-control](https://invent.kde.org/plasma/kwin/-/merge_requests/6606)
- [wl-clipboard 2.3.0 release notes](https://github.com/bugaevc/wl-clipboard/releases)
