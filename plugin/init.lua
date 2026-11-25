-- wezterm-cheatsheet-window
-- Show your key bindings in a separate small window.
local wezterm = require("wezterm")

local M = {}

-- require passes the module's own file path as the second argument,
-- which lets us find the viewer script wherever the plugin is installed
local PLUGIN_PATH = select(2, ...)
local PLUGIN_DIR = PLUGIN_PATH:match("^(.*)[/\\]")

local LOCALES = {
	en = {
		trigger = "Show this cheatsheet",
		misc = "Other",
		ungrouped = "Ungrouped",
		undocumented = "(no description)",
		leader = "Leader = %s (next key within %gs)",
		footer = "q / Esc: close   j / k: scroll",
		python_missing = "Cannot run %s. Install Python 3, or set the \"python\" option.",
		table_groups = { copy_mode = "Copy mode", search_mode = "Search mode" },
	},
	ja = {
		trigger = "このチートシートを表示",
		misc = "その他",
		ungrouped = "未分類",
		undocumented = "（説明なし）",
		leader = "Leader = %s（%g秒以内に次のキー）",
		footer = "q / Esc: 閉じる   j / k: スクロール",
		python_missing = "%s を実行できません。Python 3 を導入するか、python オプションを指定してください。",
		table_groups = { copy_mode = "コピーモード", search_mode = "検索モード" },
	},
}

-- Built-in modes are not entered through ActivateKeyTable, so rows get no prefix
local BUILTIN_TABLES = { copy_mode = true, search_mode = true }

local DEFAULTS = {
	key = { key = "?", mods = "LEADER|SHIFT" }, -- false to skip the binding
	lang = "en",
	title = "Keybinds",
	group_order = {}, -- groups not listed follow in definition order
	table_groups = {}, -- default group for each key table
	columns = 2, -- 1 or 2
	max_height = 50,
	colors = { heading = "#8ba4b0", key = "#c4b28a" },
	python = "python3",
}

local MOD_ORDER = {
	{ "LEADER", "Leader" },
	{ "SUPER", "Super" },
	{ "CTRL", "Ctrl" },
	{ "ALT", "Alt" },
	{ "SHIFT", "Shift" },
}

local KEY_NAMES = { Escape = "Esc" }

local RESET = "\27[0m"

local function merge(base, overrides)
	local result = {}
	for k, v in pairs(base) do
		result[k] = v
	end
	for k, v in pairs(overrides or {}) do
		result[k] = v
	end
	return result
end

local function ansi(hex, bold)
	local r, g, b = hex:match("^#(%x%x)(%x%x)(%x%x)$")
	assert(r, "cheatsheet: color must look like #rrggbb, got " .. tostring(hex))
	return string.format(
		"\27[%s38;2;%d;%d;%dm",
		bold and "1;" or "",
		tonumber(r, 16),
		tonumber(g, 16),
		tonumber(b, 16)
	)
end

local function resolve_options(opts)
	local options = merge(DEFAULTS, opts)
	options.colors = merge(DEFAULTS.colors, opts and opts.colors)
	local locale = LOCALES[options.lang]
	assert(locale, "cheatsheet: unsupported lang " .. tostring(options.lang))
	options.text = locale
	options.table_groups = merge(locale.table_groups, opts and opts.table_groups)
	return options
end

----------------------------------------------------
-- Preparing the config
----------------------------------------------------
-- Remove the display-only fields before handing bindings to wezterm
local function strip(keys)
	local result = {}
	for i, entry in ipairs(keys) do
		local copy = merge(entry)
		copy.desc, copy.group, copy.enters = nil, nil, nil
		result[i] = copy
	end
	return result
end

----------------------------------------------------
-- Building the list
----------------------------------------------------
local function split_key(entry)
	local mods = {}
	for mod in (entry.mods or ""):gmatch("[^|%s]+") do
		mods[mod] = true
	end
	local key = KEY_NAMES[entry.key] or entry.key
	if mods.SHIFT and key:match("^%u$") then
		key = key:lower()
	end
	local parts = {}
	for _, pair in ipairs(MOD_ORDER) do
		if mods[pair[1]] then
			table.insert(parts, pair[2])
		end
	end
	return table.concat(parts, " + "), key
end

-- Keys sharing a description share a row: "Leader + , / ." when the mods match
local function format_keys(combos)
	local same_mods = true
	for _, c in ipairs(combos) do
		same_mods = same_mods and c.mods == combos[1].mods
	end
	local names = {}
	for _, c in ipairs(combos) do
		if same_mods or c.mods == "" then
			table.insert(names, c.key)
		else
			table.insert(names, c.mods .. " + " .. c.key)
		end
	end
	local text = table.concat(names, " / ")
	if same_mods and combos[1].mods ~= "" then
		text = combos[1].mods .. " + " .. text
	end
	return text
end

local function collect(binds, options)
	local groups, seen_order = {}, {}

	local function add(group_name, prefix, entry)
		local group = groups[group_name]
		if not group then
			group = { rows = {}, by_id = {} }
			groups[group_name] = group
			table.insert(seen_order, group_name)
		end
		local mods, key = split_key(entry)
		-- Show bindings without desc rather than hiding them
		local desc = entry.desc or options.text.undocumented
		local id = prefix .. "\0" .. (entry.desc or (mods .. key))
		local row = group.by_id[id]
		if not row then
			row = { prefix = prefix, desc = desc, combos = {} }
			group.by_id[id] = row
			table.insert(group.rows, row)
		end
		table.insert(row.combos, { mods = mods, key = key })
	end

	-- Remember which key enters each key table
	local entry_keys = {}
	for _, entry in ipairs(binds.keys) do
		add(entry.group or options.text.ungrouped, "", entry)
		if entry.enters then
			local mods, key = split_key(entry)
			entry_keys[entry.enters] = format_keys({ { mods = mods, key = key } })
		end
	end

	local table_names = {}
	for name in pairs(binds.key_tables) do
		table.insert(table_names, name)
	end
	table.sort(table_names)
	for _, name in ipairs(table_names) do
		local prefix = entry_keys[name] and (entry_keys[name] .. " → ") or ""
		if BUILTIN_TABLES[name] then
			prefix = ""
		end
		for _, entry in ipairs(binds.key_tables[name]) do
			add(entry.group or options.table_groups[name] or name, prefix, entry)
		end
	end

	local ordered, done = {}, {}
	local function push(name)
		if groups[name] and not done[name] then
			done[name] = true
			table.insert(ordered, { name = name, rows = groups[name].rows })
		end
	end
	for _, name in ipairs(options.group_order) do
		push(name)
	end
	for _, name in ipairs(seen_order) do
		push(name)
	end
	return ordered
end

local function pad(text, width)
	return text .. string.rep(" ", width - wezterm.column_width(text))
end

-- Turn one group into { { text = colored string, width = cells }, ... }
local function render_group(group, options)
	local heading, key_color = ansi(options.colors.heading, true), ansi(options.colors.key)
	local key_width = 0
	for _, row in ipairs(group.rows) do
		row.label = row.prefix .. format_keys(row.combos)
		key_width = math.max(key_width, wezterm.column_width(row.label))
	end
	local lines = { { text = heading .. group.name .. RESET, width = wezterm.column_width(group.name) } }
	for _, row in ipairs(group.rows) do
		local key = pad(row.label, key_width)
		table.insert(lines, {
			text = "  " .. key_color .. key .. RESET .. "  " .. row.desc,
			width = key_width + 4 + wezterm.column_width(row.desc),
		})
	end
	return lines
end

local function stack(blocks, first, last)
	local column = {}
	for i = first, last do
		if #column > 0 then
			table.insert(column, { text = "", width = 0 })
		end
		for _, line in ipairs(blocks[i]) do
			table.insert(column, line)
		end
	end
	return column
end

-- Keep the group order and split into columns of similar height
local function split_columns(blocks, count)
	if count == 1 or #blocks < 2 then
		return { stack(blocks, 1, #blocks) }
	end
	local best, best_height
	for cut = 1, #blocks - 1 do
		local columns = { stack(blocks, 1, cut), stack(blocks, cut + 1, #blocks) }
		local height = math.max(#columns[1], #columns[2])
		if not best_height or height < best_height then
			best, best_height = columns, height
		end
	end
	return best
end

-- Returns: text, width (cells), height (lines)
local function render(binds, leader, options)
	local blocks = {}
	for _, group in ipairs(collect(binds, options)) do
		table.insert(blocks, render_group(group, options))
	end
	local columns = split_columns(blocks, options.columns)

	local widths, height, width = {}, 0, 0
	for i, column in ipairs(columns) do
		widths[i] = 0
		for _, line in ipairs(column) do
			widths[i] = math.max(widths[i], line.width)
		end
		height = math.max(height, #column)
		width = width + widths[i] + (i > 1 and 4 or 0)
	end

	local out = {}
	if leader then
		local mods, key = split_key(leader)
		local combo = mods == "" and key or (mods .. " + " .. key)
		local note = string.format(options.text.leader, combo, (leader.timeout_milliseconds or 1000) / 1000)
		table.insert(out, note)
		table.insert(out, "")
		width = math.max(width, wezterm.column_width(note))
	end
	for i = 1, height do
		local left = columns[1][i] or { text = "", width = 0 }
		local right = columns[2] and columns[2][i]
		local line = left.text
		if right and right.text ~= "" then
			line = line .. string.rep(" ", widths[1] - left.width + 4) .. right.text
		end
		table.insert(out, line)
	end
	return table.concat(out, "\n"), width, #out
end

----------------------------------------------------
-- The cheatsheet window
----------------------------------------------------
local function find_window(window_id)
	for _, window in ipairs(wezterm.mux.all_windows()) do
		if window:window_id() == window_id then
			return window
		end
	end
end

local function show(window, binds, options)
	-- If the window is already open, focus it instead of opening another
	local existing = wezterm.GLOBAL.cheatsheet_window_id
	if existing then
		local mux_window = find_window(existing)
		local gui_window = mux_window and mux_window:gui_window()
		if gui_window then
			gui_window:focus()
			return
		end
	end

	-- Without Python the new window would close at once, so explain why instead.
	-- run_child_process raises if the program cannot be started.
	local ok, success = pcall(wezterm.run_child_process, { options.python, "-c", "import termios, tty" })
	if not (ok and success) then
		local message = string.format(options.text.python_missing, options.python)
		wezterm.log_error("cheatsheet: " .. message)
		window:toast_notification(options.title, message, nil, 5000)
		return
	end

	local text, width, height = render(binds, window:effective_config().leader, options)
	local _, _, mux_window = wezterm.mux.spawn_window({
		args = { options.python, PLUGIN_DIR .. "/cheatsheet_view.py", text, options.text.footer, options.title },
		-- A window in another workspace would not be shown
		workspace = window:active_workspace(),
		domain = { DomainName = "local" },
		width = width + 2,
		height = math.min(height + 2, options.max_height),
	})
	wezterm.GLOBAL.cheatsheet_window_id = mux_window:window_id()
end

----------------------------------------------------
-- Public API
----------------------------------------------------
-- Call after config.keys, config.key_tables and config.leader are set
function M.apply_to_config(config, opts)
	local options = resolve_options(opts)
	local binds = { keys = {}, key_tables = config.key_tables or {} }
	for i, entry in ipairs(config.keys or {}) do
		binds.keys[i] = entry
	end

	local action = wezterm.action_callback(function(window, _)
		show(window, binds, options)
	end)

	if options.key then
		local trigger = merge(options.key, { action = action })
		trigger.desc = trigger.desc or options.text.trigger
		trigger.group = trigger.group or options.text.misc
		table.insert(binds.keys, trigger)
	end

	config.keys = strip(binds.keys)
	if config.key_tables then
		local key_tables = {}
		for name, keys in pairs(binds.key_tables) do
			key_tables[name] = strip(keys)
		end
		config.key_tables = key_tables
	end

	return action
end

return M
