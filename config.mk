VERSION=0.6.2
SHELL = /bin/sh

PREFIX=/usr/local
MANPREFIX=${PREFIX}/share/man

# What make install installs. bm is all you need; delete what you do not use.
#   bm-migrate  convert a file from the old "url desc | tags" format
#   bm-import   browser bookmarks to bm's format (Chromium files need jq)
#   bm-check    report dead links (curl)
#   bm-html     the bookmarks as a searchable web page
#   bm-title    lets bm --add suggest the page title as description (curl)
#   bm-page     shows the text of the page in the fzf preview of bm (curl)
#   bm-commit   lets bm keep the file's history in git
#   bm-watch    brings new browser bookmarks into bm (bm-import, jq)
#   bm-sync     keeps the file the same on all your devices (curl)
TOOLS = bm bm-migrate bm-import bm-check bm-html bm-title bm-page bm-commit bm-watch bm-sync
