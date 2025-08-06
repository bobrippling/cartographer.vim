local function hook_keymaps()
	local keymap = vim.api.nvim_get_keymap('')

	for i, mapping in pairs(keymap) do
		local remap = mapping.noremap and "n" or ""

		if mapping.rhs ~= nil and mapping.mode:gsub("%s+", ""):len() > 0 then
			local scriptpath = nil
			if mapping.sid > 0 then
				scriptpath = vim.fn.getscriptinfo({ sid = mapping.sid })[1].name
			else
				scriptpath = "<builtin?>"
			end

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
					--buffer = mapping.buffer,

					desc =
						"cartographer: " .. mapping.lhs .. " -> " .. mapping.rhs ..
						" (" .. "Last set from " .. scriptpath .. " line " .. mapping.lnum .. ")",

					callback = function()
						vim.fn.CartographerLog(mapping.lhs, "map")

						-- FIXME: this doesn't respect <silent>
						local out = vim.api.nvim_replace_termcodes(mapping.rhs, true, false, true)
						vim.api.nvim_feedkeys(out, remap, false)
					end,
				}
			)
		end
	end
end

hook_keymaps()
