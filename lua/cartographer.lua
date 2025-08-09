local M = {}

local scriptname

local function hook_keymaps()
	local keymap = vim.api.nvim_get_keymap('')

	for i, mapping in pairs(keymap) do
		local remap = mapping.noremap and "n" or ""

		if mapping.rhs ~= nil and mapping.mode:gsub("%s+", ""):len() > 0 then
			local scriptpath = scriptname(mapping.sid)

			vim.api.nvim_set_keymap(
				mapping.mode,
				mapping.lhs,
				"", --mapping.rhs, -- ignored
				{
					noremap = mapping.noremap,
					expr = mapping.expr,
					nowait = mapping.nowait,
					script = mapping.script,
					silent = mapping.silent,
					--abbr = mapping.abbr,
					--buffer = mapping.buffer, TODO

					desc =
						"cartographer: " .. mapping.lhs .. " -> " .. mapping.rhs ..
						" (" .. "Last set from " .. scriptpath .. " line " .. mapping.lnum .. ")",

					callback = function()
						vim.fn.CartographerLog(mapping.lhs, "map")

						local out
						if mapping.expr then
							out = vim.fn.eval(mapping.rhs)
						else
							out = vim.api.nvim_replace_termcodes(mapping.rhs, true, false, true)
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

local function hook_cmds()
	local cmds = vim.api.nvim_get_commands({})

	table.sort(cmds)
	for i, cmd in pairs(cmds) do
		-- TODO: handle cmd.buffer

		if cmd.nargs:match("^[01]$") ~= nil then
			cmd.nargs = tonumber(cmd.nargs)
		end

		if cmd.range == "." then
			cmd.range = nil -- -range
		elseif cmd.range == "%" then
			cmd.range = "%" -- -range=%
		elseif cmd.range ~= nil then
			local n = cmd.range:match("(%d+)$") -- -count=N
			if n ~= nil then
				cmd.range = nil
				cmd.count = tonumber(n)
			else
				cmd.range = "-range=" .. cmd.range
			end
		end

		if cmd.complete ~= nil and cmd.nargs == nil then
			cmd.nargs = '*'
		end
		if cmd.complete ~= nil and cmd.complete:match("^custom") then
			cmd.complete = cmd.complete .. "," .. cmd.complete_arg
		end

		vim.api.nvim_create_user_command(
			cmd.name,
			function(details)
				-- details.{name,args,fargs,nargs,bang,line1,line2,range,count,reg,mods,smods}

				-- TODO: test
				vim.cmd.echom('"' .. cmd.definition:gsub('"', '\\"') .. '"')
				vim.cmd(cmd.definition)
			end,
			{
				force = true,

				addr = cmd.addr,
				bang = cmd.bang,
				bar = cmd.bar,
				complete = cmd.complete,
				--complete_arg = cmd.complete_arg, -- bundled as part of cmd
				count = cmd.count,
				keepscript = cmd.keepscript,
				nargs = cmd.nargs,
				--preview = cmd.preview, -- FIXME: boolean comes through???
				range = cmd.range,
				register = cmd.register,

				desc =
					"cartographer: " .. cmd.name .. " -> " .. cmd.definition ..
					" (" .. "Last set from " .. scriptname(cmd.script_id) .. ")",

			}
		)
	end
end

function scriptname(sid)
	if sid > 0 then
		return vim.fn.getscriptinfo({ sid = sid })[1].name
	else
		return "<builtin?>"
	end
end

function M.install()
	hook_cmds()
	hook_keymaps()
end

return M
