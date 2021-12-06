" Replaces all maps, gathers statistics on use

" inspired by plug.vim, plug#end()

if get(g:, 'cartographer_enabled', 1)
	call cartographer#install()

	command! CartographerLog call cartographer#show_log()
endif
