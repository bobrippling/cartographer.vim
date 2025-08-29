local M = {}

local DIR_LOG = vim.fn.stdpath("log")
local FNAME_LOG = DIR_LOG .. "/cartographer.log"
local FNAME_LOG_NOTFOUND = DIR_LOG .. "/cartographer_rejects.log"
DIR_LOG = nil

local replace_placeholders
local scriptname
local log_timestamp
local log_entry
local log_create
local log_hooked
local serialize_table
local save_table
local load_table
local fname_to_sid
local emit_err
local nil_or_zero
local can_remap_mode
local hook_cmd
local hook_keymap
local already_hooked

local scriptlog = {} --[[
	{
		[sid] = {
			command = {
				[name] = Timestamps
			},
			mapping = {
				[lhs] = Timestamps
			}
		}
	}

	Timestamps = {
		earliest = <timestamp>
		latest = <timestamp>
		uses = number
		uses_this_session = number | nil
	}
]]
local hooked = {} --[[
	{
		[sid] = {
			command = { [name] = true },
			mapping = { [lhs] = true },
		}
	}
]]

local function hook_keymaps()
	local keymap = vim.api.nvim_get_keymap('')

	for _, mapping in pairs(keymap) do
		hook_keymap(mapping, {})
	end
end

function already_hooked(map)
	return map.desc and map.desc:match("^cartographer: ")
end

function hook_keymap(mapping, err)
	if already_hooked(mapping) then
		if err.if_exists then
			error(("mapping %s already hooked"):format(mapping.lhs))
		end
		return
	end

	local remap = nil_or_zero(mapping.noremap)
	local is_plug = mapping.lhs:match("^<Plug>")

	if mapping.rhs == nil
		or not can_remap_mode(mapping.mode)
		or is_plug
	then
		if err.invalid then
			error(("can't hook mapping %s"):format(mapping.lhs))
		end
		return
	end

	local scriptpath = scriptname(mapping.sid, true)

	log_hooked(mapping.sid, "mapping", mapping.lhs)

	local rhs_desc = mapping.rhs
	local plug_mapping
	if not nil_or_zero(mapping.silent) then
		plug_mapping = "<Plug>(cart_" .. mapping.lhs .. ")"
		rhs_desc = plug_mapping .. " (then on to " .. rhs_desc .. ")"
		remap = false

		vim.api.nvim_set_keymap(
			mapping.mode,
			plug_mapping,
			mapping.rhs,
			{
				silent = true,
				noremap = not remap,
				expr = not nil_or_zero(mapping.expr),
				nowait = not nil_or_zero(mapping.nowait),
				script = not nil_or_zero(mapping.script),
			}
		)
	end

	vim.api.nvim_set_keymap(
		mapping.mode,
		mapping.lhs,
		"", --mapping.rhs, -- ignored
		{
			noremap = mapping.noremap,
			nowait = not nil_or_zero(mapping.nowait),
			script = not nil_or_zero(mapping.script),
			silent = not nil_or_zero(mapping.silent),
			--abbr = mapping.abbr,
			--buffer = mapping.buffer, TODO

			expr = true, -- this allows us to return a string from `callback`

			-- we need to replace keycodes if:
			-- - we're using `<Plug>` to perform a `<silent>` map, so we need the `<Plug>` expanding
			-- - we're wrapping an expr mapping, which might give back "<Left>" instead of "\<Left>"
			--   > nmap <expr> R "<Left>" behaves as a left-key
			-- - we're a non-<Plug>, non-<expr> mapping - still replace
			replace_keycodes = false,

			desc =
				"cartographer: " .. mapping.lhs .. " -> " .. rhs_desc ..
				" (" .. "Last set from " .. scriptpath .. " line " .. mapping.lnum .. ")",

			callback = function()
				log_timestamp(mapping.sid, "mapping", mapping.lhs)

				local out
				if plug_mapping then
					out = plug_mapping
				elseif not nil_or_zero(mapping.expr) then
					out = vim.fn.eval(mapping.rhs)
				else
					out = mapping.rhs
				end

				-- replace termcodes, unless we see a termcode already
				-- (e.g. "\<Left>" is "\x80kl")
				--
				-- this prevents us from replacing termcodes in a string
				-- which already has them replaced, which breaks for the
				-- command line (see the test)
				if not out:match("\x80") then
					out = vim.api.nvim_replace_termcodes(
						out,
						true, -- from_part
						false, -- do_lt <lt>
						true -- special (<CR>, etc)
					)
				end

				return out
			end,
		}
	)
end

function can_remap_mode(mode)
	return mode:gsub("%s+", ""):len() > 0
end

local function ensure_int(d, key)
	local n = type(d[key]) == "string" and d[key]:match("^(%d+)$")

	if n then
		d[key] = tonumber(n)
	end
end

local function hook_cmds()
	local cmds = vim.api.nvim_get_commands {}

	for _, cmd in pairs(cmds) do
		hook_cmd(cmd, false)
	end
end

function hook_cmd(cmd, err)
	if already_hooked(cmd) then
		if err.if_exists then
			error(("command %s already hooked"):format(cmd.name))
		end
		return
	end

	-- TODO: handle cmd.buffer

	if cmd.nargs:match("^[01]$") ~= nil then
		cmd.nargs = tonumber(cmd.nargs)
	end

	-- convert in to out
	if cmd.range == "." then
		cmd.range = true
	end

	-- if there is count and range (from nvim:api/command.c),
	-- then we use count (EX_COUNT | EX_RANGE) as opposed
	-- to range (EX_RANGE)
	if cmd.range and cmd.count then
		cmd.range = nil
	end

	ensure_int(cmd, "range")
	ensure_int(cmd, "count")

	if cmd.complete ~= nil then
		if cmd.nargs == nil then
			cmd.nargs = '*'
		end
		if cmd.complete:match("^custom") then
			cmd.complete = cmd.complete .. "," .. cmd.complete_arg
		end
	end

	log_hooked(cmd.script_id, "command", cmd.name)

	vim.api.nvim_create_user_command(
		cmd.name,
		function(details)
			log_timestamp(cmd.script_id, "command", cmd.name)

			-- tack trailing space onto the final arg, to not break
			-- plugins like `:Tabular / `
			local trailing_space = details.args:match("%s+$")
			if trailing_space then
				details.fargs[#details.fargs] = details.fargs[#details.fargs] .. trailing_space
			end

			-- deal with q- and f-<...>
			local generated_cmd =
				replace_placeholders(
					cmd.definition,
					{
						args = details.fargs, -- table
						--args = details.args, -- string
						bang = details.bang and "!" or "",
						count = details.count ~= -1 and details.count or 0,
						line1 = details.line1,
						line2 = details.line2,
						range = details.range,
						reg = details.reg,
						register = details.reg,
						mods = details.mods, -- smods: {}, mods: string
						lt = "<", -- <lt> -> literal
					}
				)
				:gsub(
					"%f[%a]s:",
					function(key)
						return ("<SNR>%d_"):format(cmd.script_id)
					end
				)

			vim.cmd(generated_cmd)
		end,
		{
			force = true,

			-- true/1 and false/0 are interchangeable here
			addr = cmd.addr,
			bang = cmd.bang,
			bar = cmd.bar,
			complete = cmd.complete,
			--complete_arg = cmd.complete_arg, -- bundled as part of cmd.complete
			count = cmd.count,
			keepscript = cmd.keepscript,
			nargs = cmd.nargs,
			--preview = cmd.preview, -- we only get a boolean, not the preview function (lua or vimscript)
			range = cmd.range,
			register = cmd.register,

			desc =
				"cartographer: " .. cmd.name .. " -> " .. cmd.definition ..
				" (" .. "Last set from " .. scriptname(cmd.script_id, true) .. ")",

		}
	)
end

function replace_placeholders(str, values)
	return str:gsub("<(.-)>", function(key)
		local prefix, name = key:match("^(.-)%-(.+)$")
		if not prefix then
			-- no f- or q-
			name = key
		end

		local value = values[name]
		if value == nil then
			return "<" .. key .. ">"
		end

		if prefix == "f" then
			if type(value) == "table" then
				local quoted = {}
				for _, v in ipairs(value) do
					table.insert(quoted, string.format("%q", v))
				end
				return table.concat(quoted, ", ")
			else
				return string.format("%q", tostring(value))
			end
		elseif prefix == "q" then
			return string.format("%q", type(value) == "table" and table.concat(value, " ") or tostring(value))
		else
			if type(value) == "table" then
				return table.concat(value, " ")
			else
				return tostring(value)
			end
		end
	end)
end

function scriptname(sid, default)
	if sid > 0 then
		return vim.fn.getscriptinfo { sid = sid }[1].name
	end
	return default and "<builtin?>" or nil
end

function log_entry(map, sid, ty)
	local log = map[sid]
	if not log then
		log = {}
		map[sid] = log
	end
	local t = log[ty]
	if not t then
		t = {}
		log[ty] = t
	end
	return t
end

function log_hooked(sid, type, desc)
	local entry = log_entry(hooked, sid, type)
	entry[desc] = true
end

function log_create(sid, ty, desc)
	local entry = log_entry(scriptlog, sid, ty)
	local ent = entry[desc]
	if not ent then
		ent = { uses = 0 } -- we don't set uses_this_session here, leave it as nil
		entry[desc] = ent
	end
	return ent
end

function log_timestamp(sid, ty, entry)
	local ent = log_create(sid, ty, entry)

	local now = os.time()
	if not ent.earliest then
		ent.earliest = now
	end
	ent.latest = now
	ent.uses = ent.uses + 1
	ent.uses_this_session = (ent.uses_this_session or 0) + 1
end

function save_table(tbl, filename)
	local file = io.open(filename, "w")
	if not file then
		return false
	end
	file:write(vim.json.encode(tbl))
	file:close()
	return true
end

function load_table(filename)
	local file = io.open(filename, "r")
	if not file then
		return nil
	end
	local content = file:read("*a")
	file:close()
	return vim.json.decode(content)
end

function fname_to_sid(fname)
	local info = vim.fn.getscriptinfo { name = "^" .. fname .. "$" } -- not perfect
	for _, script in pairs(info) do
		if script.name == fname then
			return script.sid
		end
	end
end

function emit_err(msg) -- can't handle single quotes
	vim.cmd.echohl("Error")
	vim.cmd.echo(("'%s'"):format(msg))
	vim.cmd.echohl("None")
end

function nil_or_zero(x)
	return x == nil or x == 0
end

function M.install()
	hook_cmds()
	hook_keymaps()

	local log_with_scriptnames = load_table(FNAME_LOG) or {}
	local rejects = {}
	local got_reject = false

	for fname, types in pairs(log_with_scriptnames) do
		local sid = fname_to_sid(fname)
		if sid then
			if vim.o.verbose >= 1 then
				print(("Cartographer: resolved fname %q to SID %d"):format(fname, sid))
			end
			scriptlog[sid] = types
		else
			emit_err(("Cartographer: no loaded script (SID) found for filename %q"):format(fname))
			rejects[fname] = types
			got_reject = true
		end
	end

	if got_reject then
		save_table(rejects, FNAME_LOG_NOTFOUND)
		emit_err(("Cartographer: rejects saved to %q"):format(FNAME_LOG_NOTFOUND))
	end
end

function M.save_stats()
	local log_with_scriptnames = {}

	for sid, types in pairs(scriptlog) do
		local fname = scriptname(sid, false)
		if fname then
			log_with_scriptnames[fname] = types
		end
	end

	local existing = load_table(FNAME_LOG)
	if existing then
		-- uses += uses_this_session
		-- latest <-- max()
		-- earliest <-- min()

		for fname_this, types_this in pairs(log_with_scriptnames) do
			for ty_this, entries_this in pairs(types_this) do
				for entry_this, stats_this in pairs(entries_this) do
					if existing[fname_this] then
						if existing[fname_this][ty_this] then
							local stats_existing = existing[fname_this]
								and existing[fname_this][ty_this]
								and existing[fname_this][ty_this][entry_this]

							if stats_existing then
								stats_existing.uses = stats_existing.uses + (stats_this.uses_this_session or 0)

								if stats_this.latest > stats_existing.latest then
									stats_existing.latest = stats_this.latest
								end
								if stats_this.earliest < stats_existing.earliest then
									stats_existing.earliest = stats_this.earliest
								end
							else
								-- no entry for specific mapping/command - create
								-- .uses_this_session is filtered out later
								existing[fname_this][ty_this][entry_this] = stats_this
							end
						else
							-- no entry for mappings/commands - create
							existing[fname_this][ty_this] = entries_this
						end
					else
						-- no entry for this script - create
						existing[fname_this] = types_this
					end
				end
			end
		end

		log_with_scriptnames = existing
	end

	-- filter out .uses_this_session (and anything else)
	for fname, types in pairs(log_with_scriptnames) do
		for ty, entries in pairs(types) do
			for entry, stats in pairs(entries) do
				log_with_scriptnames[fname][ty][entry] = {
					uses = stats.uses,
					latest = stats.latest,
					earliest = stats.earliest,
				}
			end
		end
	end

	save_table(log_with_scriptnames, FNAME_LOG)
end

function M.show_log(q_bang)
	for sid, types in pairs(scriptlog) do
		local latest, earliest
		local uses = 0

		for _ty, entries in pairs(types) do
			for _entry, stat in pairs(entries) do
				uses = uses + stat.uses
				if latest == nil or stat.latest > latest then
					latest = stat.latest
				end
				if earliest == nil or stat.earliest < earliest then
					earliest = stat.earliest
				end
			end
		end

		local earliest_str = os.date("%Y-%m-%d %H:%M:%S", earliest)
		local latest_str = os.date("%Y-%m-%d %H:%M:%S", latest)

		print(("%s .. %s: %d use%s for %s"):format(earliest_str, latest_str, uses, uses == 1 and "" or "s", scriptname(sid, true)))
	end

	if q_bang:len() > 0 then
		for sid, _types in pairs(hooked) do
			if not scriptlog[sid] then
				local fname = scriptname(sid, false)

				if fname then
					print(("%s: no uses!"):format(fname))
				end
			end
		end
	end
end

function M.hook(args, q_bang)
	local function usage()
		error("usage: hook | hook <type> <name>")
	end
	local type, name
	local bang = q_bang:len() > 0

	if #args == 2 then
		type, name = unpack(args)
	elseif #args ~= 0 then
		usage()
	end

	-- User must do this
	--name = name:gsub("<", "<lt>")

	if type == nil then
		hook_keymaps()
		hook_cmds()
		return
	end

	local found = false

	if type == "mapping" then
		local keymap = vim.api.nvim_get_keymap('')

		for i, mapping in pairs(keymap) do
			if mapping.lhs == name then
				hook_keymap(mapping, { if_exists = not bang, invalid = true })
				found = true
			end
		end
	elseif type == "command" then
		local cmds = vim.api.nvim_get_commands {}

		for _, cmd in pairs(cmds) do
			if cmd.name == name then
				hook_cmd(cmd, not bang)
				found = true
			end
		end
	else
		usage()
	end

	if not found then
		error(("no %s found for \"%s\""):format(type, name))
	end
end

function M.uses(type, name)
	local uses = 0
	local found = false

	-- User must do this
	--name = name:gsub("<[^>]*<", "<lt>")

	for _, types in pairs(scriptlog) do
		for ty, entries in pairs(types) do
			if ty == type then
				for name_, stat in pairs(entries) do
					if name_ == name then
						uses = uses + stat.uses
						found = true
					end
				end
			end
		end
	end

	if not found then
		local is_hooked = false
		for _sid, hooked_types in pairs(hooked) do
			for name_, _true in pairs(hooked_types[type] or {}) do
				if name_ == name then
					is_hooked = true
					goto fin
				end
			end
		end
		::fin::

		error(("no %s for \"%s\" (%s)"):format(
			type,
			name,
			is_hooked and "hooked but not used" or "not hooked"
		))
	end

	return uses
end

function M.clear()
	scriptlog = {}
end

function M.usage_summary()
	local summary = {} --[[
		{ [fname] = {
			mapping = { [lhs] = { uses } } -- including 0 uses
			command = { [cmd] = { uses } }
		}}
	]]

	for sid, hooked_types in pairs(hooked) do
		local fname = scriptname(sid, false)

		if fname then
			summary[fname] = {}

			for ty, hook_entries in pairs(hooked_types) do
				for entry, _true in pairs(hook_entries) do
					local stat = scriptlog[sid]
						and scriptlog[sid][ty]
						and scriptlog[sid][ty][entry]

					local uses = 0
					local earliest, latest

					if stat then
						uses = stat.uses or 0
						earliest = stat.earliest
						latest = stat.latest
					end

					if not summary[fname][ty] then
						summary[fname][ty] = {}
					end

					summary[fname][ty][entry] = {
						uses = uses,
						earliest = earliest,
						latest = latest,
					}
				end
			end
		end
	end

	return summary
end

return M
