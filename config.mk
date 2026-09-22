VERSION=0.4.1
SHELL = /bin/sh

PREFIX=/usr/local
MANPREFIX=${PREFIX}/share/man

CC = cc
CPPFLAGS = -D_POSIX_C_SOURCE=200809L
CFLAGS = -std=c99 -pedantic -Wall -Wextra -Os ${CPPFLAGS}
LDFLAGS =

# What make install installs. bm is all you need; delete what you do not use.
#   bm-migrate  convert a file from the old "url desc | tags" format
#   bm-import   browser bookmarks to bm's format (sh; Chromium files need jq)
#   bm-check    report dead links (curl)
#   bm-html     the bookmarks as a searchable web page
#   bm-title    lets bm --add suggest the page title as description (sh, curl)
#   bm-commit   lets bm keep the file's history in git (sh)
#   bm-watch    brings new browser bookmarks into bm (sh; bm-import, jq)
#   bm-sync     keeps the file the same on all your devices (sh, curl)
TOOLS = bm bm-migrate bm-import bm-check bm-html bm-title bm-commit bm-watch bm-sync
