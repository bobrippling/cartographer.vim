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

nvim +"set rtp+=$vader_rtp" +"set rtp+=." -c 'Vader! test/*' >/dev/null
