# Desktop — KDE Plasma

KDE Plasma 6 on Wayland with the [Karousel](https://github.com/peterfajdiga/karousel) scrolling tiler and a Catppuccin Macchiato Flamingo palette. Switchable with [Niri](desktop-niri.md) at the SDDM login screen — both share the same theme.

## Theme

| Component | Value |
|-----------|-------|
| Color scheme | `CatppuccinMacchiatoFlamingo` |
| Look-and-feel | `Utterly-Nord` |
| Icons | Papirus-Dark |
| Sound theme | `modern-minimal-ui-sounds-v1.1` |
| Window decoration | `claude-decorations` (custom) |
| Accent | Flamingo `#e93a9a` |

## Workspaces

3 vertical workspaces (rows × 1 column).

| # | Name | Use |
|---|------|-----|
| 1 | Mocha | General work |
| 2 | Strawberry | Secondary |
| 3 | Kitty | Terminal / dev |

## Tiling

### Karousel (active)

Scrolling tile manager — windows arrange in a horizontal row, scroll left/right.

| Setting | Value |
|---|---|
| Status | Enabled |
| Gap | 8 px |

### Other tiling scripts (installed, disabled)

| Script | Description |
|---|---|
| Krohnkite | Dynamic tiling (i3-like, vim keys) |
| KZones | Snap zones — 7 layouts pre-configured |

??? note "KZones layouts"
    1. Priority Grid (25/50/25 vertical)
    2. Quadrant Grid (2×2)
    3. Priority Vertical (25/50/25 horizontal)
    4. Split (50/50 left/right)
    5. Split Vertical (50/50 top/bottom)
    6. Thirds Split (vertical)
    7. Thirds Split Vertical (horizontal)

## Keybindings

### Window management

| Keys | Action |
|---|---|
| `Meta+Q` / `Alt+F4` | Close window |
| `Meta+F` / `Meta+Shift+F` | Maximize / Fullscreen |
| `Meta+Ctrl+Esc` | Force kill |

### Vim navigation

| Keys | Action |
|---|---|
| `Meta+H/L` | Focus left / right |
| `Meta+U/I` | Focus down / up |
| `Alt+Tab` | Walk windows |

### Workspaces

| Keys | Action |
|---|---|
| `Meta+1/2/3` | Switch to workspace |
| `Meta+Ctrl+1/2/3` | Move window to workspace |
| `Meta+J/K` | Workspace down / up |
| `Meta+Ctrl+J/K` | Move window down / up |

### Overview & launchers

| Keys | Action |
|---|---|
| `Meta+O` / `Meta+G` | Overview / Grid view |
| `Meta+D` | Peek at desktop |
| `Meta+T` | Launch Kitty |
| `Meta+V` | Clipboard history |
| `Meta+Alt+L` | Lock screen |

### KDE quick tiling

| Keys | Action |
|---|---|
| `Meta+←/→/↑/↓` | Tile half (left/right/top/bottom) |

### Karousel

??? abstract "Column navigation"
    | Keys | Action |
    |---|---|
    | `Meta+Home/End` | Move focus to start/end |
    | `Meta+Alt+A/D` | Scroll one column left/right |
    | `Meta+Alt+PgUp/PgDown` | Scroll left/right |
    | `Meta+Alt+Home/End` | Scroll to start/end |
    | `Meta+Alt+Return` | Center focused window |

??? abstract "Column management"
    | Keys | Action |
    |---|---|
    | `Meta+Ctrl+Shift+A/D` | Move column left/right |
    | `Meta+Ctrl+Shift+Home/End` | Move column to ends |
    | `Meta+Ctrl+Shift+1-9` | Move column to position |
    | `Meta+Space` | Toggle floating |
    | `Meta+W` | Toggle stacked layout |

??? abstract "Column width"
    | Keys | Action |
    |---|---|
    | `Meta+R` | Cycle preset widths |
    | `Meta+=` / `Meta+-` | Increase / decrease width |

??? abstract "Window in column"
    | Keys | Action |
    |---|---|
    | `Meta+Shift+W` | Move window up |
    | `Meta+Shift+D` | Move window right |
    | `Meta+Shift+Home/End` | Move window to start/end |
    | `Meta+Shift+1-9` | Move window to column |

### Plasma & system

| Keys | Action |
|---|---|
| `Meta` / `Alt+F1` | Application launcher |
| `Meta+Alt+P` | Focus between panels |
| `Meta+Shift+Q` | Power menu |
| `Ctrl+Alt+Del` | Logout (fallback) |
| `Meta+B` | Switch power profile |

### Screenshots (Spectacle)

| Keys | Action |
|---|---|
| `Print` | Current monitor |
| `Ctrl+Print` / `Meta+Shift+S` | Full screen |
| `Meta+Alt+R` / `Alt+Print` | Record screen |

!!! note "Zoom shortcuts"
    Cleared to avoid conflict with Karousel column-width keys.

## Desktop effects

| Effect | Status |
|---|---|
| Blur | Enabled |
| Glide (open/close) | Enabled |
| Magic Lamp (minimize) | Enabled |
| Desktop Change OSD | Enabled (500 ms) |
| Night Color (3200 K) | Enabled |
| Scale, Slide, Squash, Window Aperture | Disabled |

### Custom effects

| Effect | Detail |
|---|---|
| TV Glitch | Magenta `(255,0,127)`, 250 ms |
| Wisps | 3-colour magenta gradient, 500 ms |
| Geometry Change | Smooth Karousel column moves |
| KDE Rounded Corners | Built from source |
| Dim Inactive | Dims unfocused windows |

Animation duration factor: **0.25** (4× faster — workspace slide ≈ 75 ms).

## Panels

### Bottom panel (primary, 32 px, floating, auto-hide)

Widgets, left → right:
1. Window Title (with Steam icon)
2. KDE Control Station (brightness/volume, flat style)
3. Thermal Monitor (CPU avg + GPU temps)
4. CPU Monitor (line chart, 30 s history, per-core)
5. Memory Monitor (pie chart, pink accent)
6. Disk Usage Monitor (pie chart)
7. Audio Visualizer (128 bars, Catppuccin palette)
8. Music Toolbar (album art as icon, palette from cover)
9. Weather Widget (minimal)
10. Digital Clock (560 × 450 popup)
11. App Menu
12. System Tray

### Left panel (launcher, 44 px, floating, centered)

Application Launcher (Kickoff) · Icon Tasks (Zen, Spotify, Obsidian, VS Code) · Show Desktop.

## Applications

### Konsole

| Setting | Value |
|---|---|
| Default profile | `Zsh.profile` |
| Shell | `/usr/bin/zsh` |
| Font | CaskaydiaCove Nerd Font, 10 pt |
| Color scheme | Catppuccin-Mocha |

Profiles: `Zsh.profile` (default — Catppuccin-Mocha), `Print.profile` (Cascadia Code NF, Catppuccin-Latte for printing).

### Dolphin

Menu bar hidden, 224 px icon previews, keyboard-driven workflow.

## Wallpaper

Slideshow from `~/Pictures/Wallpaper 2024/`, rotating every 6 hours.

## Night Color

| Setting | Value |
|---|---|
| Temperature | 3200 K |
| Location | Auto (Dublin: 53.35 N, -6.26 W) |
| Fallback | 45.34 N, -12.86 W |

## Catppuccin Macchiato palette

| Colour | Hex | Role |
|---|---|---|
| Base | `#1e2030` | Background |
| Surface0 | `#363a4f` | Elevated surfaces |
| Overlay0 | `#6e738d` | Inactive elements |
| Text | `#cad3f5` | Primary text |
| Subtext0 | `#a5adcb` | Secondary text |
| Flamingo | `#f0c6c6` | Accent (borders) |
| Pink | `#e93a9a` | Focus / selection |
| Red | `#ed8796` | Errors / urgent |
| Yellow | `#eed49f` | Warnings |
| Green | `#a6da95` | Success |
| Blue | `#8aadf4` | Info / links |
| Mauve | `#c6a0f6` | Special / visited |

## Config files

```
~/.config/
  kwinrc                                       # KWin (effects, tiling, compositing)
  kdeglobals                                   # Global theme, colours, icons
  kglobalshortcutsrc                           # All keyboard shortcuts
  plasmarc                                     # Plasma shell settings
  plasmashellrc                                # Panel/widget configuration
  plasma-org.kde.plasma.desktop-appletsrc      # Desktop widgets
  dolphinrc                                    # Dolphin file manager
  konsolerc                                    # Konsole terminal
  powerdevilrc                                 # Power management
  kscreenlockerrc                              # Lock screen settings
  baloofilerc                                  # File indexing

~/.local/share/
  kwin/scripts/        # Karousel, Krohnkite, kzones
  konsole/             # Profiles + colour schemes
  plasma/              # Plasma themes
  color-schemes/
  aurorae/             # Window decorations
  icons/
  wallpapers/
```

## Useful commands

```bash
# Reload KWin config
qdbus org.kde.KWin /KWin reconfigure

# Restart Plasma shell
systemctl --user restart plasma-plasmashell.service

# Toggle tiling scripts
kwriteconfig6 --file kwinrc --group Plugins --key karouselEnabled true
kwriteconfig6 --file kwinrc --group Plugins --key krohnkiteEnabled false
kwriteconfig6 --file kwinrc --group Plugins --key kzonesEnabled false

# List installed KWin scripts
ls ~/.local/share/kwin/scripts/

# Konsole with profile
konsole --profile Zsh

# Screenshot
spectacle
```

## Resources

- [Karousel](https://github.com/peterfajdiga/karousel)
- [Krohnkite](https://github.com/esjeon/krohnkite)
- [KDE UserBase Wiki](https://userbase.kde.org/)
- [Catppuccin KDE](https://github.com/catppuccin/kde)
- [Papirus icons](https://github.com/PapirusDevelopmentTeam/papirus-icon-theme)

## Related

- [Niri compositor](desktop-niri.md) — alternate session, same palette
- [Troubleshoot KDE panel applets](../runbooks/troubleshoot-kde-applets.md) — black-text fix after upgrade
