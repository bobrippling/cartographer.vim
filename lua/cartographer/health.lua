local M = {}

local function stats(summary)
	local earliest, latest

	for _, types in pairs(summary) do
		for _, ents in pairs(types) do
			for _, summary in pairs(ents) do
				if earliest == nil or (summary.earliest and summary.earliest < earliest) then
					earliest = summary.earliest
				end
				if latest == nil or (summary.latest and summary.latest > latest) then
					latest = summary.latest
				end
			end
		end
	end

	if earliest then
		local earliest_str = os.date("%Y-%m-%d %H:%M:%S", earliest)
		local latest_str = os.date("%Y-%m-%d %H:%M:%S", latest)
		return earliest_str, latest_str
	end
end

M.check = function()
	local C = require("cartographer")
	local script_summary = C.usage_summary()
	local OLD = os.time() - 60 * 60 * 24 * 28

	local earliest, latest = stats(script_summary)
	if earliest then
		vim.health.info(("Oldest event %s, newest event %s"):format(earliest, latest))
	else
		vim.health.warn("No gathered statistics")
	end

	for _, ent in pairs(C.unhookable()) do
		vim.health.warn(ent)
	end

	for fname, types in pairs(script_summary) do
		local used = {}
		local no_uses = {}
		local old_uses = {}

		vim.health.start(("Script %s:"):format(fname))

		for ty, ents in pairs(types) do -- mapping/command
			local total = 0
			local uses = 0

			for name, summary in pairs(ents) do
				if summary.uses == 0 then
					table.insert(no_uses, ("Unused %s: \"%s\""):format(ty, name))
				else
					local tbl
					local old_warn = ""
					if summary.latest < OLD then
						tbl = old_uses
						old_warn = ", last used > a month ago"
					else
						tbl = used
					end

					local latest_str = os.date("%Y-%m-%d %H:%M:%S", summary.latest)
					table.insert(
						tbl,
						("%s: %q: used %d times (latest %s%s)"):format(
							ty,
							name,
							summary.uses,
							latest_str,
							old_warn
						)
					)
					uses = uses + 1
				end
				total = total + 1
			end

			local fn
			if uses == 0 then
				fn = vim.health.error
			else
				fn = vim.health.info
			end
			fn(("%.0f%% of %ss used (%d / %d)"):format(uses / total * 100, ty, uses, total))
		end

		for _, ent in pairs(no_uses) do
			vim.health.warn(ent)
		end
		for _, ent in pairs(old_uses) do
			vim.health.warn(ent)
		end
		for _, ent in pairs(used) do
			vim.health.info(ent)
		end
	end
end

return M
