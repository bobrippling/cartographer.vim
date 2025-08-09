function! cartographer#show_log()
	lua require('cartographer').show_log()
endfunction

function! cartographer#install()
	if !has("nvim")
		throw "cartographer: can't hook maps - need neovim"
	endif

	lua require('cartographer').install()
endfunction

function! cartographer#exit()
	lua require('cartographer').exit()
endfunction
