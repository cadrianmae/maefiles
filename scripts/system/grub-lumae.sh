#!/usr/bin/env bash
# Customise the installed Elegant grub theme to match noctalia (Lumae Midnight).
#
# Base: vinceliuice Elegant, mojave / window / left / dark / 1080p, installed
# with -b so it lands in /boot/grub2/themes. That flag matters here: /boot is a
# separate UNENCRYPTED ext4 partition and / is LUKS, so a theme under
# /usr/share/grub/themes is unreadable at menu-draw time and silently ignored.
#
# What this changes:
#   - drops the side picture (info.png / logo.png are simply not referenced)
#   - centres the menu (Elegant offsets it to sit beside that picture)
#   - swaps in the noctalia wallpaper, cropped to 1920x1080 and soft-blurred
#   - recolours to Lumae Midnight
#
# Everything it touches is backed up next to the original.

set -euo pipefail

THEME_DIR=/boot/grub2/themes/Elegant-mojave-window-left-dark
# Assets live under ~/.local/share, NOT /tmp -- a reboot to look at the grub
# menu wipes /tmp, which is exactly when you need them again.
SRC=/home/cadrianmae/.local/share/grub-lumae
NEW_THEME=$SRC/theme.txt
NEW_BG=$SRC/background.jpg
# No window overlay: it is composited into background.jpg. GRUB paints image
# components above boot_menu regardless of theme.txt order, so an opaque
# overlay hides the menu labels entirely.
STAMP=$(date +%Y%m%d-%H%M%S)

(( EUID == 0 )) || { echo "run with sudo" >&2; exit 1; }

say() { printf '\n\033[1m== %s\033[0m\n' "$*"; }

say "checks"
[[ -d $THEME_DIR ]] || { echo "theme not installed at $THEME_DIR" >&2
                         echo "run: sudo ./install.sh -t mojave -p window -i left -c dark -s 1080p -b" >&2
                         exit 1; }
[[ -f $NEW_THEME ]] || { echo "missing $NEW_THEME" >&2; exit 1; }
[[ -f $NEW_BG     ]] || { echo "missing $NEW_BG" >&2; exit 1; }
echo "theme dir OK: $THEME_DIR"
ls -1 "$THEME_DIR"

say "backup"
cp -a "$THEME_DIR/theme.txt"      "$THEME_DIR/theme.txt.orig-$STAMP"
cp -a "$THEME_DIR/background.jpg" "$THEME_DIR/background.jpg.orig-$STAMP"
[[ -f "$THEME_DIR/info.png" && ! -f "$THEME_DIR/info.png.orig" ]] && \
  cp -a "$THEME_DIR/info.png" "$THEME_DIR/info.png.orig"
cp -a /etc/default/grub           "/etc/default/grub.bak-$STAMP"
[[ -f /boot/grub2/grub.cfg ]] && cp -a /boot/grub2/grub.cfg "/boot/grub2/grub.cfg.bak-$STAMP"
echo "backed up with suffix .orig-$STAMP / .bak-$STAMP"

say "apply theme + background"
install -o root -g root -m 0644 "$NEW_THEME" "$THEME_DIR/theme.txt"
install -o root -g root -m 0644 "$NEW_BG"     "$THEME_DIR/background.jpg"
# Restore the stock info.png if a previous run replaced it -- theme.txt no
# longer references any image component, so a leftover opaque overlay would
# still be painted over the menu.
[[ -f "$THEME_DIR/info.png.orig" ]] && \
  install -o root -g root -m 0644 "$THEME_DIR/info.png.orig" "$THEME_DIR/info.png"
echo "theme.txt and background.jpg replaced; info.png restored to stock"

say "/etc/default/grub"
# GRUB_SAVEDEFAULT was in the pre-reinstall config and the installer does not
# add it. Deliberately NOT restored: resume= and resume_offset=, which pointed
# at a swapfile that no longer exists -- systemd 259 records the hibernation
# location in an EFI variable instead.
if ! grep -q '^GRUB_SAVEDEFAULT=' /etc/default/grub; then
    sed -i '/^GRUB_DEFAULT=/a GRUB_SAVEDEFAULT=true' /etc/default/grub
    echo "added GRUB_SAVEDEFAULT=true"
else
    echo "GRUB_SAVEDEFAULT already set"
fi
grep -nE "GRUB_THEME|GRUB_TERMINAL|GRUB_GFXMODE|GRUB_BACKGROUND|GRUB_FONT|SAVEDEFAULT" /etc/default/grub

say "remove the unreadable /usr copy"
# GRUB cannot read this path (encrypted /), so leaving it only invites someone
# to point GRUB_THEME back at it later.
rm -rf /usr/share/grub/themes/Elegant-mojave-window-left-dark && echo "removed" || true

say "regenerate grub.cfg"
grub2-mkconfig -o /boot/grub2/grub.cfg 2>&1 | tail -6

say "verify"
printf 'theme referenced : %s\n' "$(grep -o 'themes/[^"]*theme.txt' /boot/grub2/grub.cfg | head -1)"
printf 'gfxterm loaded   : %s\n' "$(grep -c 'terminal_output gfxterm' /boot/grub2/grub.cfg)"
printf 'background size  : %s\n' "$(du -h "$THEME_DIR/background.jpg" | cut -f1)"

say "done — reboot to see it"
cat <<'EOF'
If the menu comes up unthemed or in plain text:
  - GRUB_TERMINAL_OUTPUT must stay commented out (a theme needs gfxterm)
  - check the theme path in /boot/grub2/grub.cfg resolves under /boot, not /usr

To revert, restore the two .orig-* files in the theme dir and rerun
grub2-mkconfig.
EOF
