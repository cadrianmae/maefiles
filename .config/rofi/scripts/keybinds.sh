#!/bin/bash
# Keybinds cheatsheet in floating kitty + nvim (readonly)

kitty --class=floating --title="Keybinds" \
    nvim -R -c "set nonumber norelativenumber signcolumn=no" \
    ~/.config/rofi/keybinds.txt
