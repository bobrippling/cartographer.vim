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

	for i, mapping in pairs(keymap) do
		local remap = mapping.noremap and "n" or ""

		if mapping.rhs ~= nil and mapping.mode:gsub("%s+", ""):len() > 0 then
			local scriptpath = scriptname(mapping.sid, true)

			log_hooked(mapping.sid, "mapping", mapping.lhs)

			vim.api.nvim_set_keymap(
				mapping.mode,
				mapping.lhs,
				"", --mapping.rhs, -- ignored
				{
					noremap = mapping.noremap,
					expr = mapping.expr ~= 0,
					nowait = mapping.nowait ~= 0,
					script = mapping.script ~= 0,
					silent = mapping.silent ~= 0,
					--abbr = mapping.abbr,
					--buffer = mapping.buffer, TODO

					desc =
						"cartographer: " .. mapping.lhs .. " -> " .. mapping.rhs ..
						" (" .. "Last set from " .. scriptpath .. " line " .. mapping.lnum .. ")",

					callback = function()
						log_timestamp(mapping.sid, "mapping", mapping.lhs)

						local out
						if mapping.expr and mapping.expr ~= 0 then
							out = vim.fn.eval(mapping.rhs)
						else
							-- replace <lt>, which is what vim stores in mappings
							out = vim.api.nvim_replace_termcodes(mapping.rhs, true, true, true)
						end

						-- FIXME: this doesn't respect <silent>
						-- - Use vim.cmd("silent ...") or nvim_cmd({ ..., silent = true }).
						-- - Or feed keys that trigger a separately defined <silent> mapping.
						vim.api.nvim_feedkeys(out, remap, false)
					end,
				}
			)
		end
	end
end

local function ensure_int(d, key)
	local n = type(d[key]) == "string" and d[key]:match("^(%d+)$")

	if n then
		d[key] = tonumber(n)
	end
end

local function hook_cmds()
	local cmds = vim.api.nvim_get_commands({})

	table.sort(cmds)
	for i, cmd in pairs(cmds) do
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
							bang = (details.bang and details.bang ~= 0) and "!" or "",
							count = details.count ~= -1 and details.count or nil,
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
		return vim.fn.getscriptinfo({ sid = sid })[1].name
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
		ent = { uses = 0 }
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
end

function serialize_table(tbl)
	local result = {}
	for k, v in pairs(tbl) do
		if type(k) == "string" then
			k = ("%q"):format(k)
		end
		if type(v) == "table" then
			v = serialize_table(v)
		elseif type(v) == "string" then
			v = ("%q"):format(v)
		end
		table.insert(result, string.format("[%s] = %s", k, v))
	end
	return "{" .. table.concat(result, ", ") .. "}"
end

function save_table(tbl, filename)
	local file = io.open(filename, "w")
	if not file then
		return false
	end
	file:write("return " .. serialize_table(tbl) .. "\n")
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
	return load(content)()
end

function fname_to_sid(fname)
	local info = vim.fn.getscriptinfo({ name = "^" .. fname .. "$" }) -- not perfect
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

function M.install()
	hook_cmds()
	hook_keymaps()

	local log_with_scriptnames = load_table(FNAME_LOG) or {}
	local rejects = {}
	local got_reject = false

	for fname, ents in pairs(log_with_scriptnames) do
		local sid = fname_to_sid(fname)
		if sid then
			if vim.o.verbose >= 1 then
				print(("Cartographer: resolved fname %q to SID %d"):format(fname, sid))
			end
			scriptlog[sid] = ents
		else
			emit_err(("Cartographer: no <SID> for filename %q"):format(fname))
			rejects[fname] = ents
			got_reject = true
		end
	end

	if got_reject then
		save_table(rejects, FNAME_LOG_NOTFOUND)
		emit_err(("Cartographer: rejects saved to %q"):format(FNAME_LOG_NOTFOUND))
	end
end

function M.exit()
	local log_with_scriptnames = {}

	for sid, ents in pairs(scriptlog) do
		local fname = scriptname(sid, false)
		if fname then
			log_with_scriptnames[fname] = ents
		end
	end

	save_table(log_with_scriptnames, FNAME_LOG)
end

function M.show_log(q_bang)
	for sid, types in pairs(scriptlog) do
		local latest, earliest
		local uses = 0

		for _, ty in pairs(types) do
			for _, ts in pairs(ty) do
				uses = uses + ts.uses
				if latest == nil or ts.latest > latest then
					latest = ts.latest
				end
				if earliest == nil or ts.earliest < earliest then
					earliest = ts.earliest
				end
			end
		end

		local earliest_str = os.date("%Y-%m-%d %H:%M:%S", earliest)
		local latest_str = os.date("%Y-%m-%d %H:%M:%S", latest)

		print(("%s .. %s: %d use%s for %s"):format(earliest_str, latest_str, uses, uses == 1 and "" or "s", scriptname(sid, true)))
	end

	if q_bang:len() > 0 then
		for sid, ent in pairs(hooked) do
			if not scriptlog[sid] then
				local fname = scriptname(sid, false)

				if fname then
					print(("%s: no uses!"):format(fname))
				end
			end
		end
	end
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
				for name, details in pairs(hook_entries) do
					local ent = scriptlog[sid]
						and scriptlog[sid][ty]
						and scriptlog[sid][ty][name]

					local uses = 0
					local earliest, latest

					if ent then
						uses = ent.uses or 0
						earliest = ent.earliest
						latest = ent.latest
					end

					if not summary[fname][ty] then
						summary[fname][ty] = {}
					end

					summary[fname][ty][name] = {
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
