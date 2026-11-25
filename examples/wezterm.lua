local wezterm = require("wezterm")
local act = wezterm.action
local config = wezterm.config_builder()

local cheatsheet = wezterm.plugin.require("https://github.com/YujiTsuruda/wezterm-cheatsheet-window")

config.leader = { key = "b", mods = "CTRL", timeout_milliseconds = 1500 }

config.keys = {
	{ key = "n", mods = "LEADER", group = "Tab", desc = "New tab", action = act.SpawnTab("CurrentPaneDomain") },
	-- Rows with the same group and desc are merged: "Leader + , / ."
	{ key = ",", mods = "LEADER", group = "Tab", desc = "Previous / next tab", action = act.ActivateTabRelative(-1) },
	{ key = ".", mods = "LEADER", group = "Tab", desc = "Previous / next tab", action = act.ActivateTabRelative(1) },
	{ key = "v", mods = "LEADER", group = "Pane", desc = "Split left / right", action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }) },
	{ key = "-", mods = "LEADER", group = "Pane", desc = "Split top / bottom", action = act.SplitVertical({ domain = "CurrentPaneDomain" }) },
	{ key = "LeftArrow", mods = "LEADER", group = "Pane", desc = "Focus left / right", action = act.ActivatePaneDirection("Left") },
	{ key = "RightArrow", mods = "LEADER", group = "Pane", desc = "Focus left / right", action = act.ActivatePaneDirection("Right") },
	-- "enters" shows the table's keys as "Leader + e → LeftArrow"
	{
		key = "e",
		mods = "LEADER",
		group = "Pane",
		desc = "Resize mode",
		enters = "pane_size",
		action = act.ActivateKeyTable({ name = "pane_size", one_shot = false }),
	},
}

config.key_tables = {
	pane_size = {
		{ key = "LeftArrow", group = "Pane", desc = "Move border left / right", action = act.AdjustPaneSize({ "Left", 3 }) },
		{ key = "RightArrow", group = "Pane", desc = "Move border left / right", action = act.AdjustPaneSize({ "Right", 3 }) },
		{ key = "Escape", group = "Pane", desc = "Leave resize mode", action = "PopKeyTable" },
	},
}

-- Call this after leader, keys and key_tables are set
cheatsheet.apply_to_config(config)

return config
