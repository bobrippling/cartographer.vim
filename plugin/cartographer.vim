" Replaces all maps, gathers statistics on use

" inspired by plug.vim, plug#end()

if !get(g:, 'cartographer_enabled', 1)
	finish
endif

if !has("nvim")
	throw "cartographer: can't install hooks - need neovim"
endif

lua require('cartographer').install()

if exists('g:plugs')
\ && !empty(filter(values(g:plugs)[:], { _, ent -> has_key(ent, 'for') || has_key(ent, 'on') }))
	echohl Error
	echom "Cartographer: lazy plugs detected, won't be able to analyse all commands/maps"
	echom "(remove any 'for' or 'on' entries in your plug config)"
	echohl None
endif

command! -bang -bar CartographerLog lua require('cartographer').show_log(<q-bang>)
command! -bar CartographerDontSave lua require('cartographer').dont_save()

augroup CartographerExit
	autocmd!
	autocmd VimLeave * lua require('cartographer').exit()
augroup END
