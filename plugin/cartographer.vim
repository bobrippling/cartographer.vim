" Replaces all maps, gathers statistics on use

finish

" inspired by plug.vim, plug#end()


let s:cmds = {}
let s:log = {}

let s:script_fns = []

function! s:show_log()
	for k in keys(s:log)
		let dupe = copy(s:log[k])
		call map(dupe, { _, v -> v.when })
		call sort(dupe)

		let earliest = strftime("%Y-%m-%d %H:%M", dupe[0])
		let latest = strftime("%Y-%m-%d %H:%M", dupe[len(dupe) - 1])

		echo k .. ":" len(s:log[k]) "uses, earliest at" earliest .. ", latest at" latest
	endfor
endfunction

command! CartographerLog call s:show_log()

function! s:install()
	call s:hook_cmd("Ttysplit")

	" TODO
	"call s:install_cmds()
	"call s:install_maps() / s:hook_map(...)
endfunction

function! s:hook_cmd(cmd)
	let current = split(execute("command " .. a:cmd), "\n")[1:]
	call assert_equal(len(current), 1)
	let current = current[0]

	let cmd = s:parse_command(current)

	let s:cmds[cmd.name] = cmd

	let munged_cmd = cmd.vim_cmd
	if cmd.vim_cmd =~ '\<s:'
		" Need to handle cmd.vim_cmd containing <SID>... - currently resolves to this script, need to resolve to the other
		if empty(s:script_fns)
			call s:populate_fns()
		endif

		let munged_cmd = substitute(
		\   munged_cmd,
		\   '\<s:\k\+',
		\   function('s:lookup_cmd'),
		\   'g')
	endif

	execute "command!"
	\   s:cmd_flags_expand(cmd.flags)
	\   s:cmd_args_expand(cmd.args)
	\   s:cmd_range_expand(cmd.range)
	\   s:cmd_addrtype_expand(cmd.addrtype)
	\   cmd.name
	\   "call CartographerLogCmd('" . cmd.name . "') | " munged_cmd
endfunction

function! s:lookup_cmd(matchlist)
	" called with matchlist = 's:funcname'

	let needle = a:matchlist[0][2:]
	for ent in s:script_fns
		if stridx(ent, needle) != -1
			return "<SNR>" .. ent
		endif
	endfor

	echoerr "couldn't find SNR command for " .. needle
	return ''
endfunction

function! s:populate_fns()
	let d = {}

	execute "silent normal! :echo *(<Tab>\<c-a>\<c-\>eextend(l:d,{'cmdline':getcmdline(),'empty':''}).empty\n"

	if !has_key(d, 'cmdline') || d['cmdline'] =~ "\<C-A>"
		echoerr "cartographer: couldn't grab script function ids"
		return
	endif

	let ents = split(d['cmdline'], ' ')
	call filter(ents, { i, v -> stridx(v, "<SNR>") == 0 })
	call map(ents, { i, v -> substitute(substitute(v, "<SNR>", "", ""), "(.*", "", "") })
	" ents = ['10_fn_name', '20_fn_other', ...]

	let s:script_fns = ents
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
		" b -buffer
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
	if parts[i] =~ '[0-9.%]'
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

	let vim_cmd = join(parts[i:], " ")

	return {
	\   "flags": flags,
	\   "args": args,
	\   "range": range,
	\   "addrtype": addrtype,
	\   "name": name,
	\   "vim_cmd": vim_cmd,
	\ }
endfunction

function! s:cmd_flags_expand(s)
	let r = []
	if stridx(a:s, "!") >= 0 | call add(r, "-bang") | endif
	if stridx(a:s, '"') >= 0 | call add(r, "-register") | endif
	if stridx(a:s, '|') >= 0 | call add(r, "-bar") | endif
	if stridx(a:s, 'b') >= 0 | call add(r, "-buffer") | endif
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
		return "-count=" . a:s[:len(a:s)-2]
	endif
endfunction

function! s:cmd_addrtype_expand(s)
	if empty(a:s) || a:s ==# "line"
		return ""
	endif
	return "-addr=" . a:s
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

call s:install()

finish

function! s:install_cmds()
	let commands = split(execute("command"), "\n")[1:]

	"call map(commands, { i, c -> substitute(c, '^....\(\S\+\)\s.*', '\1', '') })

	for cmd in commands
		let cmd = s:parse_command(cmd)

		" TODO: split cmd so we can recreate it later
		let [chars, name, args, range, completion, definition] = cmd

		execute printf(
		\  'command! -nargs=* -range -bang -complete=file %s call s:lod_cmd(%s, "<bang>", <line1>, <line2>, <q-args>, %s)',
		\  cmd, string(cmd), string(names))
	endfor
endfunction

" TODO

function! s:install_maps()
  for [map, names] in items(lod.map)
    for [mode, map_prefix, key_prefix] in
          \ [['i', '<C-O>', ''], ['n', '', ''], ['v', '', 'gv'], ['o', '', '']]
      execute printf(
      \ '%snoremap <silent> %s %s:<C-U>call <SID>lod_map(%s, %s, %s, "%s")<CR>',
      \ mode, map, map_prefix, string(map), string(names), mode != 'i', key_prefix)
    endfor
  endfor
endfunction

function! s:lod_cmd(cmd, bang, l1, l2, args, names)
  call s:lod(a:names, ['ftdetect', 'after/ftdetect', 'plugin', 'after/plugin'])
  call s:dobufread(a:names)
  execute printf('%s%s%s %s', (a:l1 == a:l2 ? '' : (a:l1.','.a:l2)), a:cmd, a:bang, a:args)
endfunction

function! s:lod_map(map, names, with_prefix, prefix)
  call s:lod(a:names, ['ftdetect', 'after/ftdetect', 'plugin', 'after/plugin'])
  call s:dobufread(a:names)
  let extra = ''
  while 1
    let c = getchar(0)
    if c == 0
      break
    endif
    let extra .= nr2char(c)
  endwhile

  if a:with_prefix
    let prefix = v:count ? v:count : ''
    let prefix .= '"'.v:register.a:prefix
    if mode(1) == 'no'
      if v:operator == 'c'
        let prefix = "\<esc>" . prefix
      endif
      let prefix .= v:operator
    endif
    call feedkeys(prefix, 'n')
  endif
  call feedkeys(substitute(a:map, '^<Plug>', "\<Plug>", '') . extra)
endfunction

function! s:lod(names, types, ...)
  for name in a:names
    call s:remove_triggers(name)
    let s:loaded[name] = 1
  endfor
  call s:reorg_rtp()

  for name in a:names
    let rtp = s:rtp(g:plugs[name])
    for dir in a:types
      call s:source(rtp, dir.'/**/*.vim')
    endfor
    if a:0
      if !s:source(rtp, a:1) && !empty(s:glob(rtp, a:2))
        execute 'runtime' a:1
      endif
      call s:source(rtp, a:2)
    endif
    call s:doautocmd('User', name)
  endfor
endfunction
