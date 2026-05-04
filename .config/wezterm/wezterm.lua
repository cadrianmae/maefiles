-- ~/.config/wezterm/wezterm.lua
-- Quick-start config mirroring kitty look + tmux-style C-Space leader.
-- Docs: https://wezterm.org/config/files.html

local wezterm = require 'wezterm'
local config = wezterm.config_builder()

-- ---- Theme (Catppuccin Macchiato is built-in) ----------------------------
config.color_scheme = 'Catppuccin Macchiato'

-- ---- Fonts ---------------------------------------------------------------
config.font = wezterm.font_with_fallback {
  'CaskaydiaCove Nerd Font Mono',
}
config.font_size = 11.0
-- ligatures are on by default for fonts that have them; disable per-feature
-- if you want with: config.harfbuzz_features = { 'calt=0', 'liga=0' }

-- ---- Window chrome -------------------------------------------------------
config.window_padding = { left = 8, right = 8, top = 8, bottom = 8 }
config.window_background_opacity = 1.0
config.window_decorations = 'TITLE | RESIZE'

-- ---- Cursor (matches kitty 'beam' + 0.5s blink) --------------------------
config.default_cursor_style = 'BlinkingBar'
config.cursor_blink_rate = 500

-- ---- Bell (off, like kitty) ----------------------------------------------
config.audible_bell = 'Disabled'
config.visual_bell = {
  fade_in_duration_ms = 0,
  fade_out_duration_ms = 0,
}

-- ---- Scrollback ----------------------------------------------------------
config.scrollback_lines = 10000

-- ---- Tabs (closest to kitty 'powerline slanted') -------------------------
config.use_fancy_tab_bar = true
config.tab_bar_at_bottom = false
config.hide_tab_bar_if_only_one_tab = false
config.show_new_tab_button_in_tab_bar = false

-- ---- Mouse / URLs --------------------------------------------------------
config.hyperlink_rules = wezterm.default_hyperlink_rules()

-- ---- Keys: tmux-style C-Space leader -------------------------------------
-- Mirrors the C-Space prefix muscle memory from your tmux config.
config.leader = { key = 'Space', mods = 'CTRL', timeout_milliseconds = 1500 }

config.keys = {
  -- Splits in current dir (tmux: " and %)
  { key = '"', mods = 'LEADER|SHIFT',
    action = wezterm.action.SplitVertical { domain = 'CurrentPaneDomain' } },
  { key = '%', mods = 'LEADER|SHIFT',
    action = wezterm.action.SplitHorizontal { domain = 'CurrentPaneDomain' } },

  -- Tabs (tmux: c, n, p, &)
  { key = 'c', mods = 'LEADER',
    action = wezterm.action.SpawnTab 'CurrentPaneDomain' },
  { key = 'n', mods = 'LEADER', action = wezterm.action.ActivateTabRelative(1) },
  { key = 'p', mods = 'LEADER', action = wezterm.action.ActivateTabRelative(-1) },
  { key = '&', mods = 'LEADER|SHIFT',
    action = wezterm.action.CloseCurrentTab { confirm = true } },
  { key = 'x', mods = 'LEADER',
    action = wezterm.action.CloseCurrentPane { confirm = true } },

  -- Goto tab N (tmux: prefix 1..9)
  { key = '1', mods = 'LEADER', action = wezterm.action.ActivateTab(0) },
  { key = '2', mods = 'LEADER', action = wezterm.action.ActivateTab(1) },
  { key = '3', mods = 'LEADER', action = wezterm.action.ActivateTab(2) },
  { key = '4', mods = 'LEADER', action = wezterm.action.ActivateTab(3) },
  { key = '5', mods = 'LEADER', action = wezterm.action.ActivateTab(4) },
  { key = '6', mods = 'LEADER', action = wezterm.action.ActivateTab(5) },
  { key = '7', mods = 'LEADER', action = wezterm.action.ActivateTab(6) },
  { key = '8', mods = 'LEADER', action = wezterm.action.ActivateTab(7) },
  { key = '9', mods = 'LEADER', action = wezterm.action.ActivateTab(8) },

  -- Tab swap (tmux: < and >)
  { key = ',', mods = 'LEADER|SHIFT', action = wezterm.action.MoveTabRelative(-1) },
  { key = '.', mods = 'LEADER|SHIFT', action = wezterm.action.MoveTabRelative(1) },

  -- Zoom (tmux: z) — wezterm's built-in
  { key = 'z', mods = 'LEADER', action = wezterm.action.TogglePaneZoomState },

  -- Reload config (tmux: r)
  { key = 'r', mods = 'LEADER', action = wezterm.action.ReloadConfiguration },

  -- Pane navigation — direct binds for smart-splits.nvim parity
  -- (no leader; smart-splits.nvim will intercept inside nvim)
  { key = 'h', mods = 'CTRL', action = wezterm.action.ActivatePaneDirection 'Left' },
  { key = 'j', mods = 'CTRL', action = wezterm.action.ActivatePaneDirection 'Down' },
  { key = 'k', mods = 'CTRL', action = wezterm.action.ActivatePaneDirection 'Up' },
  { key = 'l', mods = 'CTRL', action = wezterm.action.ActivatePaneDirection 'Right' },

  -- Fullscreen (you wanted plain F11 in kitty too)
  { key = 'F11', mods = 'NONE', action = wezterm.action.ToggleFullScreen },

  -- Font size
  { key = '=', mods = 'CTRL|SHIFT', action = wezterm.action.IncreaseFontSize },
  { key = '-', mods = 'CTRL|SHIFT', action = wezterm.action.DecreaseFontSize },
  { key = '0', mods = 'CTRL|SHIFT', action = wezterm.action.ResetFontSize },
}

-- ---- Notes for later -----------------------------------------------------
-- WezTerm has a built-in multiplexer with workspaces and persistence:
--   wezterm.action.ShowLauncher / ShowLauncherArgs { flags = 'WORKSPACES' }
--   `wezterm cli list` / `attach` for session-style use.
-- This solves the 7-workspace pattern natively — explore once basics feel right.

return config
