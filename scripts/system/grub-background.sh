#!/usr/bin/env bash
# Keep the stock Elegant grub theme, swap in your own background.
#
# This deliberately REVERTS the Lumae customisation attempt and restores the
# theme as shipped, changing only background.jpg. Two things learned while
# trying to do more:
#
#   1. GRUB paints `+ image` components ON TOP of boot_menu regardless of their
#      order in theme.txt. Elegant's info.png works only because it is
#      transparent exactly where the menu sits; an opaque window there hides
#      every menu label.
#   2. Elegant bakes its text into info.png -- "Select Your System" and "Press
#      the Shortcut Key to Enable the Function" are pixels, not labels. gfxmenu
#      exposes only __timeout__, so there is no help component to restyle.
#
# Restyling properly therefore means redrawing that overlay, which is a design
# job rather than a config change. Parked.
#
# Run with sudo. Safe to re-run.

set -euo pipefail

THEME_DIR=/boot/grub2/themes/Elegant-mojave-window-left-dark
SRC=/home/cadrianmae/.local/share/grub-lumae
NEW_BG=$SRC/background-plain.jpg
STAMP=$(date +%Y%m%d-%H%M%S)

(( EUID == 0 )) || { echo "run with sudo" >&2; exit 1; }
say() { printf '\n\033[1m== %s\033[0m\n' "$*"; }

[[ -d $THEME_DIR ]] || { echo "theme not installed at $THEME_DIR" >&2; exit 1; }
[[ -f $NEW_BG    ]] || { echo "missing $NEW_BG" >&2; exit 1; }

say "restore the stock theme"
# The earliest .orig-* backup is the pristine one -- later runs backed up our
# own edits, so picking the newest would restore the customisation.
# find, not ls: the names are timestamped so sorting is safe either way, but
# ls output is not robust to odd filenames and shellcheck is right to say so.
ORIG_THEME=$(find "$THEME_DIR" -maxdepth 1 -name 'theme.txt.orig-*' -print 2>/dev/null | sort | head -1)
if [[ -n $ORIG_THEME ]]; then
    install -o root -g root -m 0644 "$ORIG_THEME" "$THEME_DIR/theme.txt"
    echo "theme.txt <- $(basename "$ORIG_THEME")"
else
    echo "no theme.txt backup found — leaving as is" >&2
fi

if [[ -f "$THEME_DIR/info.png.orig" ]]; then
    install -o root -g root -m 0644 "$THEME_DIR/info.png.orig" "$THEME_DIR/info.png"
    echo "info.png <- info.png.orig (stock overlay, with its baked-in text)"
fi

say "install the background"
install -o root -g root -m 0644 "$NEW_BG" "$THEME_DIR/background.jpg"
echo "background.jpg <- $(basename "$NEW_BG")"

say "regenerate grub.cfg"
cp -a /boot/grub2/grub.cfg "/boot/grub2/grub.cfg.bak-$STAMP"
grub2-mkconfig -o /boot/grub2/grub.cfg 2>&1 | tail -4

say "state"
grep -nE "item_font|left =|^\+ " "$THEME_DIR/theme.txt" | head -8
echo
echo "Stock layout restored: menu at left = 52%, picture panel on the left."
echo "Only the background is yours."
