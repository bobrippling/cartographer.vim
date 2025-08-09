" Replaces all maps, gathers statistics on use

" inspired by plug.vim, plug#end()

if !get(g:, 'cartographer_enabled', 1)
	finish
endif

if !has("nvim")
	throw "cartographer: can't install hooks - need neovim"
endif

lua require('cartographer').install()

command! -bang -bar CartographerLog lua require('cartographer').show_log(<q-bang>)

augroup CartographerExit
	autocmd!
	autocmd VimLeave * lua require('cartographer').exit()
augroup END
