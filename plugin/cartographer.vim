" Replaces all maps, gathers statistics on use

" inspired by plug.vim, plug#end()

if !get(g:, 'cartographer_enabled', 1)
	finish
endif
if $CARTOGRAPHER ==# "0"
	echom "cartographer disabled via environment"
	finish
endif

if !has("nvim")
	throw "cartographer: can't install hooks - need neovim"
endif

" run later to capture late-loaded scripts
lua vim.defer_fn(function() require('cartographer').install() end, 0)

if exists('g:plugs')
\ && !empty(filter(values(g:plugs)[:], { _, ent -> has_key(ent, 'for') || has_key(ent, 'on') }))
	echohl Error
	echom "Cartographer: lazy plugs detected, won't be able to analyse all commands/maps"
	echom "(remove any 'for' or 'on' entries in your plug config)"
	echohl None
endif

function! CartographerHookComplete(arglead, cmdline, cursorpos)
	if a:cmdline =~# '^\vCartographer(H%[ook]|U%[nhook])\s+command\s+'
		return filter(getcompletion(a:arglead, 'command'), { _, cmd -> cmd[0] =~# '[A-Z]' })
	elseif a:cmdline =~# '^\vCartographer(H%[ook]|U%[nhook])\s+mapping\s+'
		return getcompletion(a:arglead, 'mapping')
	endif

	return filter(['command', 'mapping'], { _, x -> a:arglead ==# '' || x[0:len(a:arglead)-1] ==# a:arglead })
endfunction

command! -bang -bar CartographerLog lua require('cartographer').show_log(<q-bang>)
command! -bar -nargs=* -bang -complete=customlist,CartographerHookComplete CartographerHook lua require('cartographer').hook({<f-args>}, <q-bang>)
command! -bar -nargs=* -bang -complete=customlist,CartographerHookComplete CartographerUnhook lua require('cartographer').unhook({<f-args>}, <q-bang>)

command! -bar CartographerDontSave aug CartographerExit | au! | aug END

augroup CartographerExit
	autocmd!
	autocmd VimLeave * lua require('cartographer').save_stats()
augroup END
