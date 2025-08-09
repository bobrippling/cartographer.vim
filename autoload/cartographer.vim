let s:log = {}

let s:cmds = {}
let s:script_names = ''

let s:completion_res = [
\  'arglist',
\  'color',
\  'compiler',
\  'cscope',
\  'dir',
\  'environment',
\  'event',
\  'expression',
\  'file_in_path',
\  'locale',
\  'mapping',
\  'option',
\  'shellcmd',
\  'tag_listfiles',
\  'user',
\  'var',
\  'custom',
\  'customlist',
\]
" the following are kept out - also commands:
" augroup behave buffer command file filetype function help highlight history
" lua mapclear menu messages packadd sign syntax syntime tag

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
	call s:hook_cmds()

	" TODO
	"call s:install_cmds()
	"call s:install_maps() / s:hook_map(...)

	" call s:hook_map()
endfunction

function! s:hook_cmd(command, verbose)
	let cmd = s:parse_command(a:command)

	let s:cmds[cmd.name] = cmd

	let from = a:verbose " 'Last set from path/to/script.vim line 32'
	let file = substitute(from, '\s*Last set from \(.*\) line \d\+', '\1', '')
	let line = substitute(from, '\s*Last set from .* line \(\d\+\)', '\1', '')
	let cmd["orig_file"] = file
	let cmd["orig_line"] = line

	let munged_cmd = cmd.vim_cmd
	if cmd.vim_cmd =~ '\<s:'
		" Need to handle cmd.vim_cmd containing <SID>... - currently resolves to this script, need to resolve to the other

		if empty(s:script_names)
			let script_names = split(execute('scriptnames'), "\n")
			let map = {}

			for s in script_names
				" ' 32: ~/.config/dotfiles/.vim/plugin/basic/statusline.vim'
				let parts = split(s, ' ')
				let id = str2nr(parts[0][:-2])
				let fname = parts[1]
				let map[fname] = id
			endfor

			let s:script_names = map
		endif

		let munged_cmd = substitute(munged_cmd, '\<s:\ze\k\+', '<SNR>' .. s:script_names[file] .. '_', 'g')
	endif

	let hook_cmd = "command!"
	\ .. " " .. s:cmd_flags_expand(cmd.flags)
	\ .. " " .. s:cmd_args_expand(cmd.args)
	\ .. " " .. s:cmd_range_expand(cmd.range)
	\ .. " " .. s:cmd_addrtype_expand(cmd.addrtype)
	\ .. " " .. s:cmd_completion_expand(cmd)
	\ .. " " .. cmd.name
	\ .. " " .. "call CartographerLogCmd('" . cmd.name . "') |"
	\ .. " " .. munged_cmd

	try
		execute hook_cmd
	catch /./
		echohl ErrorMsg
		echomsg "cartographer couldn't hook :" .. cmd.name
		echomsg "  error:" v:exception
		echomsg "  running:" hook_cmd
		echomsg "  original:" a:command
		echomsg "  cmd:" cmd
		echohl none
	endtry
endfunction

function! s:parse_command(s)
	let parts = split(a:s, '\s\+')
	let i = 0

	if a:s[0] ==# " "
		let flags = ""
	else
		" ! -bang
		" " -register
		" | -bar
		" b -buffers
		let flags = parts[i]
		let i += 1
	endif

	let name = parts[i]
	let i += 1

	" -nargs=[0*?+1]
	let args = parts[i]
	let i += 1

	" [0-9]c: -count=N
	" %: -range=%
	" [0-9]: -range=N
	" .: -range
	if parts[i] =~ '^[0-9.%]'
		let range = parts[i]
		let i += 1
	else
		let range = ""
	endif

	" -addr=
	if parts[i] =~ '\vline|arg|buf|load|win|tab|qf|\?'
		" "line" is never displayed - default
		let addrtype = parts[i]
		let i += 1
	else
		let addrtype = ""
	endif

	let completion = ""
	for re in s:completion_res
		if parts[i] =~ '^\v' .. re .. '$'
			let completion = parts[i]
			let i += 1
			break
		endif
	endfor

	let vim_cmd = join(parts[i:], " ")

	return {
	\   "flags": flags,
	\   "args": args,
	\   "range": range,
	\   "addrtype": addrtype,
	\   "completion": completion,
	\   "name": name,
	\   "vim_cmd": vim_cmd,
	\ }
endfunction

function! s:cmd_flags_expand(s)
	let r = []
	if stridx(a:s, "!") >= 0 | call add(r, "-bang") | endif
	if stridx(a:s, '"') >= 0 | call add(r, "-register") | endif
	if stridx(a:s, '|') >= 0 | call add(r, "-bar") | endif
	if stridx(a:s, 'b') >= 0 | call add(r, "-buffers") | endif
	return join(r, " ")
endfunction

function! s:cmd_args_expand(s)
	return empty(a:s) || a:s ==# "0" ? "" : "-nargs=" . a:s
endfunction

function! s:cmd_range_expand(s)
	if empty(a:s)
		return ""
	elseif a:s ==# "%"
		return "-range=%"
	elseif a:s ==# "."
		return "-range"
	elseif a:s =~ '^[0-9]\+$'
		return "-range=" . a:s
	else
		let n = a:s[:len(a:s)-2]
		if n !~ '^[0-9]\+$'
			throw "invalid count for command's range (\"" . n . "\") - indicates a parser bug"
		endif
		return "-count=" . n
	endif
endfunction

function! s:cmd_addrtype_expand(s)
	if empty(a:s) || a:s ==# "line"
		return ""
	elseif a:s ==# "arg"
		return "-addr=arguments"
	elseif a:s ==# "buf"
		return "-addr=buffers"
	elseif a:s ==# "load"
		return "-addr=loaded_buffers"
	elseif a:s ==# "win"
		return "-addr=windows"
	elseif a:s ==# "tab"
		return "-addr=tabs"
	elseif a:s ==# "qf"
		return "-addr=quickfix"
	elseif a:s ==# "?"
		return "-addr=other"
	endif
	return ""
endfunction

function! s:cmd_completion_expand(cmd)
	let s = a:cmd.completion
	if empty(s) || s =~ '\vcustom(list)?'
		" bug: can't get the custom/customlist back out, so we turn it off
		return ''
	endif

	if empty(s:cmd_args_expand(a:cmd.args))
		" -complete errors without -nargs (E1208)
		"  e.g. :LspInfo from nvim-lspconfig
		return ""
	endif

	return '-complete=' .. s
endfunction

function! CartographerLogCmd(name)
	let cmd = s:cmds[a:name]

	if !has_key(s:log, a:name)
		let s:log[a:name] = []
	endif
	call add(
	\  s:log[a:name],
	\  {
	\    'when': localtime(),
	\  }
	\ )
endfunction

function! s:hook_cmds()
	let commands = split(execute("verbose command"), "\n")[1:]

	let command = ''
	let i = 0
	while i < len(commands)
		let ent = commands[i]
		let i += 1

		if ent =~ '^\tLast set from '
			let verbose = ent
		elseif ent =~ '^....\S'
			if !empty(command)
				throw "cartographer: multiple commands found when parsing :command output"
			endif
			let command = ent
			continue
		elseif ent =~ '^ \{5,\}'
			" docs - ignore
			continue
		endif

		call s:hook_cmd(command, verbose)
		let command = ''
	endwhile
endfunction
