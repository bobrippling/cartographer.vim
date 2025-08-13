# Cartographer.vim

Hook `:command`s and `:map`s to gather statistics on use, to help trim down a `.vimrc` and co.

## Installation

```vim
Plug 'bobrippling/cartographer.vim'
```

Or via your favourite package manager

## Usage

All your user-commands and mappings will be seamlessly hooked by cartographer and statistics on their use will be gathered.
A short summary of used scripts can be viewed with `:CartographerLog`. Pass `!` to view unused scripts.

For a more detailed summary, Cartographer uses Neovim's `:checkhealth` to display unused commands and mappings. These are shown as warnings and used mappings have their usage count shown, along with the time of their first and last use. An error is shown if no mappings or no commands in a script are used.

## TODO

A way to re-source files and re-hook their commands/mappings. `:CartographerUnhook` to restore, then `:CartographerHook` ?
