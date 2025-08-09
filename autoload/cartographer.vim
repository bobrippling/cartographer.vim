let s:log = {}

function! cartographer#show_log()
	for name in keys(s:log)
		let dupe = copy(s:log[name])
		call map(dupe, { _, v -> v.when })
		call sort(dupe)

		let earliest = strftime("%Y-%m-%d %H:%M", dupe[0])
		let latest = strftime("%Y-%m-%d %H:%M", dupe[len(dupe) - 1])

		echo name .. ":" len(s:log[name]) "uses, earliest at" earliest .. ", latest at" latest
	endfor
endfunction

function! cartographer#install()
	if !has("nvim")
		throw "cartographer: can't hook maps - need neovim"
	endif

	lua require('cartographer').install()
endfunction

function! CartographerLog(name, cmd_or_map)
	let key = a:name .. " (" .. a:cmd_or_map .. ")"
	if !has_key(s:log, key)
		let s:log[key] = []
	endif
	call add(
	\  s:log[key],
	\  {
	\    'when': localtime(),
	\  }
	\ )
endfunction
