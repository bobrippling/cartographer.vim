Cartographer.vim
----------

Hook `:command`s and `:map`s to gather statistics on use, to help trim down a `.vimrc`

Currently WIP

Problems:

- [x] Hook commands
	- [x] Replacing `command Xyz call s:xyz()` // can't call into s:...
		- Fixed with s:script_fns
	- [x] Replacing `<q-mods>` // doesn't seem to be replaced at this point
		- Works with the new dispatch technique (keeping <q-mods> inside the :command)
- [ ] Hook mappings
