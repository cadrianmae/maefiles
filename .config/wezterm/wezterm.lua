-- ~/.config/wezterm/wezterm.lua
-- Minimal config — defaults everywhere except theme.
-- Full starter config parked at wezterm.lua.parked (restore for summer 2026 trial).

local wezterm = require 'wezterm'
local config = wezterm.config_builder()

config.color_scheme = "Noctalia"

-- Slight translucency for a hint of frost, but opaque enough that the bright
-- wallpaper doesn't bleed through and wash out text readability.
-- Colours come from the Noctalia template (tracks the active Lumae-Dusk scheme).
-- 1.0 = fully opaque (no frost); 0.85 = strong frost but washes out over light wallpaper.
config.window_background_opacity = 0.90

-- Font A/B trial — uncomment one. Reload with Ctrl+Shift+R.
-- config.font = wezterm.font('IntoneMono Nerd Font Mono')            -- accessibility-tested, high x-height
config.font = wezterm.font('AtkynsonMono Nerd Font Mono', { weight = 'Medium' })  -- Atkinson Hyperlegible (Medium for less-thin baseline)
-- config.font = wezterm.font('OpenDyslexicM Nerd Font Mono')         -- OpenDyslexic (weighted-bottom)
-- config.font = wezterm.font('CaskaydiaCove Nerd Font Mono')         -- previous default
config.font_size = 13.0
config.line_height = 1.15  -- extra breathing room for sustained reading

-- Dumb-terminal mode: hide tab bar unless multiple tabs exist.
-- This keeps the "just a terminal window" feel for daily use, while letting
-- wezterm's tab bar reappear naturally the moment you start using tabs.
config.hide_tab_bar_if_only_one_tab = true

return config
