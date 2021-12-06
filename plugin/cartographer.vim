" Replaces all maps, gathers statistics on use

" inspired by plug.vim, plug#end()

if get(g:, 'cargographer_enabled', 0)
	call cartographer#install()

	command! CartographerLog call cartographer#show_log()
endif
