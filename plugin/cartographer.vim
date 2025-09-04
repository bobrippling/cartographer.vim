" Replaces all maps, gathers statistics on use

" inspired by plug.vim, plug#end()

if !get(g:, 'cartographer_enabled', 1)
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

command! -bang -bar CartographerLog lua require('cartographer').show_log(<q-bang>)
command! -bar -nargs=* -bang CartographerHook lua require('cartographer').hook({<f-args>}, <q-bang>)
command! -bar -nargs=* -bang CartographerUnhook lua require('cartographer').unhook({<f-args>}, <q-bang>)

command! -bar CartographerDontSave aug CartographerExit | au! | aug END

augroup CartographerExit
	autocmd!
	autocmd VimLeave * lua require('cartographer').save_stats()
augroup END
