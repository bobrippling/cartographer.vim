#!/bin/bash

if test $# -ne 0
then
	echo >&2 "Usage: $0"
	exit 2
fi

if test -e vader.vim
then vader_rtp='vader.vim'
else vader_rtp='../vader.vim'
fi

# for running locally, may need:
# :so plugin/cartographer.vim
# :so ../vader.vim/plugin/vader.vim

nvim -u NONE -i NONE +"set rtp+=$vader_rtp" +"set rtp+=." -c 'Vader! test/*' >/dev/null
