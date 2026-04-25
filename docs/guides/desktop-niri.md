# Desktop — Niri

[Niri](https://github.com/YaLTeR/niri) — a scrolling tiling Wayland compositor — as the lightweight alternative to [KDE Plasma](desktop-kde.md). Same Catppuccin Macchiato Flamingo palette; choose at the SDDM login screen.

## Theme

Catppuccin Macchiato with Flamingo accent (`#f5bde6`).

## Workspaces

| # | Name | Icon | Use |
|---|------|------|-----|
| 1 | Mocha | coffee | General work |
| 2 | Strawberry | strawberry | Secondary |
| 3 | Kitty | cat | Terminal / dev |

## Keybindings

`Mod` = Super (Meta).

### Launchers & utilities

| Keys | Action |
|---|---|
| `Alt+Space` / `Mod+D` | Rofi launcher |
| `Mod+T` | Kitty terminal |
| `Mod+P` | Clipboard history |
| `Mod+Shift+Q` | Power menu (wlogout) |
| `Super+Alt+L` | Lock screen (swaylock) |

### Window management

| Keys | Action |
|---|---|
| `Mod+Q` | Close |
| `Mod+F` / `Mod+Shift+F` | Maximize column / Fullscreen |
| `Mod+V` | Toggle floating |
| `Mod+C` | Center column |

### Vim navigation (crosses workspaces on J/K)

| Keys | Action |
|---|---|
| `Mod+H/L` | Focus left / right |
| `Mod+J/K` | Focus down / up (crosses workspaces) |
| `Mod+Ctrl+H/J/K/L` | Move window |

### Workspaces

| Keys | Action |
|---|---|
| `Mod+1/2/3` | Switch |
| `Mod+Ctrl+1/2/3` | Move window to workspace |
| `Mod+U/I` | Workspace down / up |
| `Mod+O` | Toggle overview |

### Window sizing

| Keys | Action |
|---|---|
| `Mod+R` | Cycle preset widths (1/3, 1/2, 2/3) |
| `Mod+-` / `Mod+=` | -10 % / +10 % width |
| `Mod+Shift+-` / `Mod+Shift+=` | -10 % / +10 % height |

### Columns

| Keys | Action |
|---|---|
| `Mod+[` / `Mod+]` | Consume / expel window left / right |
| `Mod+,` / `Mod+.` | Consume / expel within current column |
| `Mod+W` | Toggle tabbed display |

### System & screenshots

| Keys | Action |
|---|---|
| `Mod+Shift+E` | Quit niri |
| `Mod+Shift+P` | Power off monitors |
| `Print` / `Ctrl+Print` / `Alt+Print` | Region / screen / window screenshot |

### Media & brightness

Standard `XF86Audio*` and `XF86MonBrightness*` keys are wired. `pulseaudio` icon scrolls volume; `backlight` icon scrolls brightness.

## Keyboard

| Setting | Value |
|---|---|
| Layout | `gb` (British) |
| Caps Lock | Escape |
| Shift+Caps Lock | Caps Lock |

## Waybar

```
[Left]                    [Center]                       [Right]
Workspaces | Window       Sysmon | Tray                  Clock | Music | Weather | Notifs
```

| Region | Modules |
|---|---|
| Left | `niri/workspaces`, `niri/window` |
| Center | `temperature`, `custom/cpu` (bar), `custom/memory` (bar), `custom/disk` (bar), `pulseaudio`, `backlight`, `bluetooth`, `network`, `battery`, `tray` |
| Right | `clock`, `mpris`, `custom/weather`, `custom/notifications` |

### Progress-bar alerts

| Level | Threshold | Style |
|---|---|---|
| Normal | < 75 % | Coloured |
| Warning | ≥ 75 % | Yellow |
| Critical | ≥ 90 % | Red blinking |

### Icon sets

| Module | Icons |
|---|---|
| Volume | 󰕿 󰖀 󰕾 (level) · 󰝟 (muted) · 󰋋 (headphones) |
| Brightness | 󰃞 󰃟 󰃠 |
| WiFi | 󰤯 󰤟 󰤢 󰤥 󰤨 (signal) · 󰤭 (offline) |
| Battery | 󰁺 … 󰁹 (10 levels) · 󱐋 (charging) |

Bar style: transparent backgrounds, pill-shaped hover (border-radius `999 px`), frosted glass with noise.

## Startup applications

Defined in `config.kdl` via `spawn-at-startup`:

- `waybar` — status bar
- `mako` — notification daemon
- `nm-applet` — network tray icon
- `swaybg` — wallpaper
- `swayidle` — auto-lock 5 min, monitors off 10 min
- `wl-paste` + `cliphist` — clipboard manager

## Features

- [x] Rounded corners (12 px radius)
- [x] Window shadows
- [x] Focus ring (2 px Flamingo)
- [x] No client-side decorations (`prefer-no-csd`)
- [x] Named workspaces
- [x] Touchpad natural scroll + tap
- [x] Numlock on startup
- [x] Hot corners disabled
- [x] Auto-lock after 5 min
- [x] Clipboard history

### Floating by default

`pavucontrol`, `blueman-manager`, `nm-connection-editor`, `gnome-calculator`, `file-roller`, `eog`, `wlogout`. Plus dialogs: Open File, Save File, Preferences, Settings.

## Useful commands

```bash
# Reload config (auto-reloads on save anyway)
niri msg action reload-config

# Inspect state
niri msg outputs
niri msg windows

# Restart waybar (inside the niri session)
pkill waybar; niri msg action spawn -- waybar

# From outside the niri session
NIRI_SOCKET=/run/user/1000/niri.*.sock niri msg action spawn -- waybar

# Notifications
makoctl reload
notify-send "Test" "Hello from mako"

# Clipboard history
cliphist list | rofi -dmenu | cliphist decode | wl-copy
```

## Config files

```
~/.config/niri/
  config.kdl                  # main niri config

~/.config/waybar/
  config                      # modules + layout
  style.css                   # translucent + pill hover
  catppuccin.css              # theme colours
  scripts/
    progress-bar.sh           # base bar generator
    cpu-bar.sh
    mem-bar.sh
    disk-bar.sh

~/.config/rofi/
  config.rasi
  catppuccin-macchiato.rasi

~/.config/fuzzel/fuzzel.ini   # backup launcher
~/.config/mako/config         # notifications (top-right)
~/.config/kitty/
  kitty.conf
  catppuccin-macchiato.conf
```

## Catppuccin Macchiato palette

| Colour | Hex | Role |
|---|---|---|
| Base | `#24273a` | Background |
| Surface0 | `#363a4f` | Elevated surfaces |
| Overlay0 | `#6e738d` | Inactive elements |
| Text | `#cad3f5` | Primary text |
| Subtext0 | `#a5adcb` | Secondary text |
| Flamingo | `#f0c6c6` | Accent (borders) |
| Pink | `#f5bde6` | Focus ring |
| Red | `#ed8796` | Errors / critical |
| Yellow | `#eed49f` | Warnings |
| Peach | `#f5a97f` | Disk usage |
| Blue | `#8aadf4` | CPU |
| Mauve | `#c6a0f6` | Memory |
| Green | `#a6da95` | Success / battery |

## Resources

- [Niri wiki](https://github.com/YaLTeR/niri/wiki)
- [Niri configuration docs](https://yalter.github.io/niri/Configuration:-Introduction.html)
- [Waybar wiki](https://github.com/Alexays/Waybar/wiki)
- [Rofi docs](https://davatorium.github.io/rofi/)
- [Nerd Fonts cheatsheet](https://www.nerdfonts.com/cheat-sheet)

## Related

- [KDE Plasma](desktop-kde.md) — full DE alternative
