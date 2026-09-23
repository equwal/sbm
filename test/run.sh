#!/bin/sh

# Non-interactive tests for bm and the bm-* tools. Menus are scripted through
# test/fakemenu and test/fakefzf, and the clipboard and opener are stubs that
# write to files.
# usage: sh test/run.sh        (SBM_SH=dash sh test/run.sh to pick the shell)

# Several groups point BOOKMARKS somewhere else inside a subshell on purpose.
# shellcheck disable=SC2030,SC2031

here=$(cd "$(dirname "$0")" && pwd)
top=$(cd "$here/.." && pwd)
BM="${SBM_SH:-sh} $top/bm"
MIGRATE="${SBM_SH:-sh} $top/bm-migrate"
IMPORT="${SBM_SH:-sh} $top/bm-import"
CHECK="${SBM_SH:-sh} $top/bm-check"
HTML="${SBM_SH:-sh} $top/bm-html"
TITLE="${SBM_SH:-sh} $top/bm-title"
PAGE="${SBM_SH:-sh} $top/bm-page"
TAB=$(printf '\t')

work=${TMPDIR:-/tmp}/sbmtest.$$
mkdir -m 700 "$work" || exit 1
trap 'rm -rf "$work"' EXIT INT TERM

export BOOKMARKS="$work/bookmarks"
export USERTAGS="$work/usertags"
export SBM_TEST_ANSWERS="$work/answers"
export SBM_MENU="$here/fakemenu"
export SBM_COPY="$work/copy"
export SBM_PASTE="$work/paste"
export SBM_OPEN="$work/open"
export XDG_DATA_HOME="$work/xdg"
# Nothing here may touch the network or the user's git setup.
export SBM_FETCH=0
# bm starts bm-sync after each change when it is installed. This config is
# empty, so bm-sync cannot reach the account of the user.
export SBM_SYNC_CONFIG="$work/sync.conf"

cp "$here/../usertags" "$USERTAGS"

printf '#!/bin/sh\ncat > "%s"\n' "$work/clipboard" > "$SBM_COPY"
printf '#!/bin/sh\ncat "%s" 2>/dev/null\n' "$work/clipboard" > "$SBM_PASTE"
# shellcheck disable=SC2016
printf '#!/bin/sh\nprintf "%%s\\n" "$1" > "%s"\n' "$work/opened" > "$SBM_OPEN"
mkdir "$work/bin"
cp "$here/fakemenu" "$work/bin/dmenu"
chmod +x "$SBM_COPY" "$SBM_PASTE" "$SBM_OPEN" "$work/bin/dmenu"

pass=0
fail=0

ok () {
    pass=$((pass + 1))
    printf 'ok   %s\n' "$1"
}

notok () {
    fail=$((fail + 1))
    printf 'FAIL %s\n' "$1"
    [ -z "$2" ] || printf '     %s\n' "$2"
}

# eq <name> <actual> <expected>
eq () {
    if [ "$2" = "$3" ]; then
        ok "$1"
    else
        notok "$1" "expected [$3] got [$2]"
    fi
}

# answers <line>...: script the next menu answers, one per prompt.
answers () {
    : > "$SBM_TEST_ANSWERS"
    for a in "$@"; do
        printf '%s\n' "$a" >> "$SBM_TEST_ANSWERS"
    done
}

reset () {
    : > "$BOOKMARKS"
    rm -f "$work/clipboard" "$work/opened" "$BOOKMARKS.bak"
}

# ---- add ----

reset
answers 'Example site' 'sec code sec'
$BM --add https://example.com 2>/dev/null
eq 'add writes url<tab>desc<tab>sorted unique tags' \
    "$(cat "$BOOKMARKS")" "https://example.com${TAB}Example site${TAB}code sec"

reset
answers '100%s | done %d' 'lib'
$BM -a https://percent.example 2>/dev/null
eq 'add keeps % and | in the description' \
    "$(cut -f2 "$BOOKMARKS")" '100%s | done %d'

reset
printf 'https://clip.example/page\n' > "$work/clipboard"
answers '' 'From clipboard' 'org'
$BM -a 2>/dev/null
eq 'add with a closed url prompt adds nothing' "$(cat "$BOOKMARKS")" ''

reset
printf 'https://clip.example/page\n' > "$work/clipboard"
answers 'https://typed.example' 'Typed' 'org'
$BM -a 2>/dev/null
eq 'add takes the url from the prompt' \
    "$(cut -f1 "$BOOKMARKS")" 'https://typed.example'

reset
answers 'No tags' ''
$BM -a https://notags.example 2>/dev/null
eq 'add without tags leaves the tag field empty' \
    "$(cat "$BOOKMARKS")" "https://notags.example${TAB}No tags${TAB}"

# ---- duplicates ----

reset
answers 'First' 'code'
$BM -a https://www.Example.com/docs/ 2>/dev/null
for dup in http://example.com/docs https://example.com/docs/ \
           https://WWW.EXAMPLE.COM/docs example.com/docs; do
    answers 'Second' 'code'
    $BM -a "$dup" 2>/dev/null
    rc=$?
    eq "add rejects duplicate $dup with status 3" "$rc $(wc -l < "$BOOKMARKS" | tr -d ' ')" '3 1'
done
answers 'Other path' 'code'
$BM -a https://example.com/Docs 2>/dev/null
eq 'add keeps urls differing only in path case apart' \
    "$(wc -l < "$BOOKMARKS" | tr -d ' ')" '2'

# ---- copy, open, list, tag filter, delete ----

reset
printf '%s\n' \
    "https://b.example${TAB}Bee${TAB}code lib" \
    "https://a.example${TAB}Ay${TAB}sec" \
    "https://c.example${TAB}Sea${TAB}code" > "$BOOKMARKS"

answers 'Bee'
$BM -c
eq 'copy puts only the url on the clipboard' \
    "$(cat "$work/clipboard")" 'https://b.example'

answers ''
$BM -c
eq 'copy exits 1 when the menu is closed' "$?" '1'

answers 'Sea'
$BM --open
eq 'open hands the url to the opener' "$(cat "$work/opened")" 'https://c.example'

answers 'Ay'
$BM --plumb
eq '--plumb is an alias for --open' "$(cat "$work/opened")" 'https://a.example'

eq 'list prints sorted rows' "$($BM -l | cut -f1 | paste -sd ' ' -)" \
    'https://a.example https://b.example https://c.example'

eq 'list honours the tag filter' "$($BM -t code -l | cut -f1 | paste -sd ' ' -)" \
    'https://b.example https://c.example'

eq 'tag filter matches whole tags only' "$($BM -t cod -l)" ''

answers 'example' 'copy'
$BM -t sec
eq 'a tag filter narrows the browser' \
    "$(cat "$work/clipboard")" 'https://a.example'

$BM -t nosuchtag -c 2>/dev/null
eq 'copy with an unused tag fails' "$?" '1'

answers 'Sea' 'copy'
$BM
eq 'no arguments: pick the bookmark, then what to do' \
    "$(cat "$work/clipboard")" 'https://c.example'

answers 'Ay'
eq '--print prints the url' "$($BM --print)" 'https://a.example'
answers 'no such bookmark'
$BM -c 2>/dev/null
eq 'copy refuses text that is not a bookmark' "$?" '1'

answers 'Bee'
$BM -d >/dev/null
eq 'delete removes only the chosen row' "$(cut -f1 "$BOOKMARKS" | paste -sd ' ' -)" \
    'https://a.example https://c.example'

# ---- dmenu backend: closing the tag menu must not loop forever ----

reset
answers 'Escaped' 'sec'
(
    PATH="$work/bin:$PATH" SBM_MENU=dmenu $BM -a https://dmenu.example 2>/dev/null
) &
pid=$!
( sleep 10; kill "$pid" 2>/dev/null ) &
watchdog=$!
wait "$pid"
kill "$watchdog" 2>/dev/null
eq 'dmenu tag loop ends when the menu is closed' \
    "$(cat "$BOOKMARKS")" "https://dmenu.example${TAB}Escaped${TAB}sec"

# ---- bm-migrate ----

reset
printf '%s\n' 'https://old.example Old style | code sec' > "$BOOKMARKS"
eq 'bm warns about an old format file and names the tool' \
    "$($BM -l 2>&1 >/dev/null | grep -c 'bm-migrate')" '1'

# backups: how many backups sit beside the bookmark file.
backups () {
    set -- "$BOOKMARKS".bak*
    if [ -e "$1" ]; then echo $#; else echo 0; fi
}


old_file () {
    rm -f "$BOOKMARKS".bak*
    printf '%s\n' \
        '# my bookmarks' \
        '' \
        'https://old.example Old style | code sec' \
        'https://equwal.com  Spenser Truex'"'"'s website.' \
        'https://pipe.example a | b | lib' \
        '  https://indented.example   spaced   out  |  org  ' \
        'https://bare.example' \
        'https://100.example 100%s done \n | lib' \
        "https://new.example${TAB}Already TSV${TAB}org" > "$BOOKMARKS"
}
migrated=$(printf '%s\n' \
    '# my bookmarks' \
    '' \
    "https://old.example${TAB}Old style${TAB}code sec" \
    "https://equwal.com${TAB}Spenser Truex's website.${TAB}" \
    "https://pipe.example${TAB}a | b${TAB}lib" \
    "https://indented.example${TAB}spaced   out${TAB}org" \
    "https://bare.example${TAB}${TAB}" \
    "https://100.example${TAB}100%s done \\n${TAB}lib" \
    "https://new.example${TAB}Already TSV${TAB}org")

old_file
original=$(cat "$BOOKMARKS")
eq 'bm-migrate -n prints the converted file' "$($MIGRATE -n "$BOOKMARKS")" "$migrated"
eq 'bm-migrate -n changes nothing' \
    "$(cat "$BOOKMARKS")|$(backups)" "$original|0"
eq 'bm-migrate - is a filter' "$($MIGRATE - < "$BOOKMARKS")" "$migrated"
eq 'bm-migrate reports what it did' "$($MIGRATE "$BOOKMARKS")" \
    "migrated 6 lines in $BOOKMARKS (original kept as $BOOKMARKS.bak)"
eq 'bm-migrate converts in place' "$(cat "$BOOKMARKS")" "$migrated"
eq 'bm-migrate keeps the original as .bak' "$(cat "$BOOKMARKS.bak")" "$original"
eq 'bm-migrate has nothing to do the second time' "$($MIGRATE "$BOOKMARKS")" \
    "nothing to migrate in $BOOKMARKS"
eq 'bm-migrate then leaves file and backup alone' \
    "$(cat "$BOOKMARKS")|$(cat "$BOOKMARKS.bak")|$(backups)" \
    "$migrated|$original|1"

printf '%s\n' 'https://late.example Added by hand | org' >> "$BOOKMARKS"
$MIGRATE "$BOOKMARKS" >/dev/null
eq 'bm-migrate never overwrites an earlier backup' \
    "$(cat "$BOOKMARKS.bak")|$(grep -c late.example "$BOOKMARKS.bak.1")" "$original|1"

old_file
eq 'bm-migrate defaults to the BOOKMARKS variable' "$($MIGRATE >/dev/null; cat "$BOOKMARKS")" "$migrated"

eq 'bm is quiet once the file is migrated' "$($BM -l 2>&1 >/dev/null)" ''

old_file
ln -s "$BOOKMARKS" "$work/link"
chmod 600 "$BOOKMARKS"
$MIGRATE "$work/link" >/dev/null
eq 'bm-migrate keeps a symlinked file a symlink, and its mode' \
    "$([ -L "$work/link" ] && echo link) $(find "$BOOKMARKS" -perm 600 | wc -l | tr -d ' ') $(grep -c "$TAB" "$BOOKMARKS")" \
    'link 1 7'
chmod 644 "$BOOKMARKS"

$MIGRATE "$work/nosuchfile" 2>/dev/null
eq 'bm-migrate fails on a missing file' "$?" '1'
$MIGRATE --bogus 2>/dev/null
eq 'bm-migrate rejects unknown options' "$?" '2'
$MIGRATE a b 2>/dev/null
eq 'bm-migrate takes one file' "$?" '2'
rm -f "$BOOKMARKS".bak* "$work/link" "$work/link".bak*

# ---- argument handling ----

reset
$BM --bogus 2>/dev/null
eq 'unknown flag exits 2' "$?" '2'

answers 'x' 'code'
$BM -c -a https://two.example 2>/dev/null
eq 'two actions exit 2 without side effects' "$? $(cat "$BOOKMARKS")" '2 '

$BM -t 2>/dev/null
eq '-t without a tag exits 2' "$?" '2'

missing=
for flag in --copy --open --plumb --print --add --edit --delete --list --merge --tag --sort; do
    $BM -h | grep -q -e "$flag" || missing="$missing $flag"
done
eq 'help mentions every flag' "$missing" ''

for gone in '--import x' --check --migrate '-s x'; do
    # shellcheck disable=SC2086
    $BM $gone 2>/dev/null
    eq "bm no longer does $gone itself" "$?" '2'
done

bad=
for script in bm bm-migrate bm-import bm-check bm-html bm-title bm-page bm-commit bm-watch; do
    [ "$(sed -n 1p "$top/$script")" = '#!/bin/sh' ] || bad="$bad $script"
done
eq 'every script asks for /bin/sh' "$bad" ''

# ---- sorting and use counts ----

seed () {
    reset
    rm -f "$BOOKMARKS.usage"
    printf '%s\n' \
        "https://b.example${TAB}Zed${TAB}code lib" \
        "https://a.example${TAB}Mid${TAB}sec" \
        "https://c.example${TAB}Alpha${TAB}code" > "$BOOKMARKS"
}

# order <bm arguments>: the hosts' first letters, in listed order.
order () {
    $BM "$@" -l | sed 's|https://\(.\).*|\1|' | paste -sd ' ' -
}

seed
eq 'default order without use counts is by url' "$(order)" 'a b c'
eq 'sort url'    "$(order -S url)" 'a b c'
eq 'sort recent' "$(order --sort recent)" 'c a b'
eq 'sort desc'   "$(order -S desc)" 'c a b'
eq 'sort tag'    "$(order -S tag)" 'c b a'
eq 'SBM_SORT sets the default' "$(SBM_SORT=recent order)" 'c a b'
$BM -S bogus -l 2>/dev/null
eq 'unknown sort order exits 2' "$?" '2'

answers 'Alpha'; $BM -c
answers 'Alpha'; $BM -o
answers 'Zed';   $BM -c
eq 'sort used puts the most used first' "$(order -S used)" 'c b a'
eq 'use counts are kept beside the bookmarks' \
    "$(grep -c "^https://c.example${TAB}2${TAB}[0-9]\{10,\}\$" "$BOOKMARKS.usage")" '1'
answers 'Alpha'; $BM -d >/dev/null
eq 'delete forgets the use count' "$(grep -c 'c.example' "$BOOKMARKS.usage")" '0'

# A writable file in a directory that is not: temporary files go to $TMPDIR.
if [ "$(id -u)" -ne 0 ]; then
    mkdir "$work/locked" "$work/tmp"
    printf '%s\n' "https://keep.example${TAB}Keep${TAB}" "https://drop.example${TAB}Drop${TAB}" \
        > "$work/locked/bookmarks"
    : > "$work/locked/bookmarks.usage"
    chmod 555 "$work/locked"
    (
        BOOKMARKS="$work/locked/bookmarks" TMPDIR="$work/tmp"
        export BOOKMARKS TMPDIR
        answers 'Drop'; $BM -d >/dev/null
        answers 'Keep'; $BM -c
        printf 'https://merged.example\n' | $BM -m >/dev/null
    )
    eq 'a read-only directory does not stop delete, merge or use counts' \
        "$(cut -f1 "$work/locked/bookmarks" | paste -sd ' ' -) $(cut -f1,2 "$work/locked/bookmarks.usage")" \
        "https://keep.example https://merged.example https://keep.example${TAB}1"
    eq 'and no temporary file is left behind' "$(find "$work/tmp" "$work/locked" -name '*sbm*' -o -name '*.tmp.*' | wc -l | tr -d ' ')" '0'
    ln -s "$work/locked/bookmarks" "$work/tmp/sbm.planted"
    # tmpfile relies on this: with noclobber, ">" refuses a name that exists,
    # a symlink included, instead of writing through it.
    # shellcheck disable=SC2016
    eq 'a name planted in the temporary directory is refused, not written through' \
        "$( if ${SBM_SH:-sh} -c 'set -C; : > "$1"' sh "$work/tmp/sbm.planted" 2>/dev/null
            then echo written; else echo refused; fi) $(grep -c . "$work/locked/bookmarks")" 'refused 2'
    chmod 755 "$work/locked"
fi

# ---- bm-title, and add with it installed ----

mkdir "$work/net"
cat > "$work/net/curl" <<'FAKE'
#!/bin/sh
printf 'curl %s\n' "$*" >> "$SBM_TEST_CURLLOG"
probe= head=
for arg in "$@"; do
    case $arg in
        -w)  probe=1 ;;
        -sI) head=1 ;;
    esac
    url=$arg
done
if [ -z "$probe" ]; then
    case $url in
        *oneline*)
            # A minified page: one line, the title beyond the first 64k.
            awk 'BEGIN { for (i = 0; i < 70000; i++) printf "x"; print "<title>too far</title>" }'
            exit 0
            ;;
        *nearline*)
            awk 'BEGIN { for (i = 0; i < 60000; i++) printf "x"; print "<title>near enough</title>" }'
            exit 0
            ;;
    esac
    printf '<html><head>\n<meta charset="utf-8"><TITLE lang="en">\n  Fetched &amp; decoded\n  &#39;title&#39; </Title></head><body><title>no</title>'
    exit 0
fi
case $url in
    *dead*)   printf '404 ' ;;
    *moved*)  printf '301 https://new.example/' ;;
    *nohead*) if [ -n "$head" ]; then printf '405 '; else printf '206 '; fi ;;
    *gone*)   printf '000 ' ;;
    *)        printf '200 ' ;;
esac
FAKE
chmod +x "$work/net/curl"
export SBM_TEST_CURLLOG="$work/curllog"

eq 'bm-title prints a decoded, squeezed title' \
    "$(PATH="$work/net:$PATH" SBM_FETCH=1 $TITLE https://fetch.example)" "Fetched & decoded 'title'"
eq 'bm-title stops reading a one-line page at 64k' \
    "$(PATH="$work/net:$PATH" SBM_FETCH=1 $TITLE https://oneline.example)|$(PATH="$work/net:$PATH" SBM_FETCH=1 $TITLE https://nearline.example)" \
    '|near enough'
$TITLE 2>/dev/null
eq 'bm-title wants exactly one url' "$?" '2'

reset
: > "$SBM_TEST_CURLLOG"
answers '<default>' 'code'
PATH="$top:$work/net:$PATH" SBM_FETCH=1 $BM -a https://fetch.example 2>/dev/null
eq 'add offers the fetched <title> as the description' \
    "$(cut -f2 "$BOOKMARKS")" "Fetched & decoded 'title'"

reset
: > "$SBM_TEST_CURLLOG"
answers 'Mine' 'code'
PATH="$top:$work/net:$PATH" SBM_FETCH=1 $BM -a https://fetch.example 2>/dev/null
eq 'a typed description beats the fetched title' "$(cut -f2 "$BOOKMARKS")" 'Mine'

reset
: > "$SBM_TEST_CURLLOG"
answers 'Offline' 'code'
PATH="$top:$work/net:$PATH" SBM_FETCH=0 $BM -a https://fetch.example 2>/dev/null
eq 'SBM_FETCH=0 never runs curl' "$(cat "$SBM_TEST_CURLLOG")" ''

reset
cp "$here/../usertags" "$USERTAGS"
answers 'New tag' 'code brandnew'
$BM -a https://newtag.example 2>/dev/null
answers 'Again' 'brandnew'
$BM -a https://newtag2.example 2>/dev/null
eq 'a new tag is used' "$(sed -n 1p "$BOOKMARKS" | cut -f3)" 'brandnew code'
eq 'a new tag is remembered once' "$(grep -c '^brandnew | $' "$USERTAGS")" '1'

reset
rm -f "$USERTAGS"
answers 'No tag file' 'first'
$BM -a https://notagfile.example 2>/dev/null
eq 'a missing tag file is created from the first new tag' \
    "$(cat "$USERTAGS")|$(cut -f3 "$BOOKMARKS")" 'first | |first'
cp "$here/../usertags" "$USERTAGS"

# ---- bm-page, and the page in the fzf preview ----

mkdir "$work/page"
cat > "$work/page/curl" <<'FAKE'
#!/bin/sh
printf 'curl %s\n' "$*" >> "$SBM_TEST_CURLLOG"
for arg in "$@"; do url=$arg; done
case $url in
    *rich*)
        printf '<!doctype html><html><head><TITLE lang=en>\n A &amp; B &#8212; &#x263A; </Title>\n'
        printf '<style>p { color: red } a < b</style><script>if (a < b) document.write("<p>no</p>")</script></head>\n'
        printf '<body><!-- a < comment -->\n<h1>Head</h1><p>One\n   two <a href="x">link</a>&nbsp;three.</p>\n'
        printf '<ul><li>first</li><li>second</li></ul><svg><title>no</title><text>no</text></svg>\n'
        printf '<noscript>no</noscript><p>5 &lt; 6 &bogus; &#65;</p></body></html>\n'
        ;;
    *ctrl*)
        printf '<p>esc:\033[31mred\033[0m bel:\007 c1:\302\233x end</p>\n'
        ;;
    *main*)
        printf '<title>T</title><nav>Menu one<br>Menu two</nav><main><h1>Article</h1><p>Body</p></main><footer>Foot</footer>\n'
        ;;
    *pdf*)
        printf '%%PDF-1.7\n1 0 obj\n'
        ;;
    *big*)
        # More than 512k before the text.
        awk 'BEGIN { for (i = 0; i < 540000; i++) printf "x"; print "<p>too far</p>" }'
        ;;
esac
FAKE
chmod +x "$work/page/curl"

# page <url>: bm-page with the stand-in curl.
page () {
    PATH="$work/page:$PATH" SBM_FETCH=1 $PAGE "$@"
}
nl='
'

eq 'bm-page prints the title, then the text without scripts, styles, comments and svg' \
    "$(page https://rich.example/)" \
    "A & B — ☺${nl}${nl}Head${nl}${nl}One two link three.${nl}${nl}first${nl}second${nl}${nl}5 < 6 &bogus; A"
out=$(page https://ctrl.example/)
eq 'bm-page removes control characters, so that a page cannot drive the terminal' \
    "$out|$(printf '%s' "$out" | LC_ALL=C tr -d '\040-\176' | wc -c | tr -d ' ')" 'esc:[31mred[0m bel: c1:x end|0'
eq 'bm-page shows only the main part of a page that marks one' \
    "$(page https://main.example/)" "T${nl}${nl}Article${nl}${nl}Body"
eq 'bm-page names a PDF document' "$(page https://pdf.example/)" '(a PDF document)'
eq 'bm-page reads at most 512k of a page' "$(page https://big.example/ | grep -c 'too far')" '0'
: > "$SBM_TEST_CURLLOG"
eq 'bm-page with SBM_FETCH=0 prints nothing' \
    "$(PATH="$work/page:$PATH" SBM_FETCH=0 $PAGE https://rich.example/)" ''
eq 'bm-page fetches only http and https pages' \
    "$(page ftp://rich.example/)$(page 'javascript:alert(1)')$(page rich.example)" ''
eq 'bm-page with SBM_FETCH=0, or for another scheme, never runs curl' "$(cat "$SBM_TEST_CURLLOG")" ''
eq 'bm-page takes an HTTPS address in capitals' "$(page HTTPS://main.example/ | sed -n 1p)" 'T'
$PAGE 2>/dev/null
eq 'bm-page wants exactly one url' "$?" '2'
$PAGE https://a.example https://b.example 2>/dev/null
eq 'bm-page wants exactly one url, not two' "$?" '2'

# The preview command of the fzf list, as fzf runs it: each placeholder
# becomes its field in single quotes.
preview=$(sed -n 's/^PREVIEW="\(.*\)"$/\1/p' "$top/bm" |
    sed "s|{1}|'https://main.example/'|g; s|{2}|'Main page'|; s|{3}|'code'|; s|{4}|'3'|")
eq 'the fzf preview shows the bookmark, then the text of its page' \
    "$(PATH="$top:$work/page:$PATH" SBM_FETCH=1 ${SBM_SH:-sh} -c "$preview")" \
    "https://main.example/${nl}Main page${nl}tags: code${nl}used: 3${nl}${nl}T${nl}${nl}Article${nl}${nl}Body"
eq 'the fzf preview shows the bookmark without bm-page' \
    "$(PATH="$work/page:/usr/bin:/bin" SBM_FETCH=1 ${SBM_SH:-sh} -c "$preview" 2>&1)" \
    "https://main.example/${nl}Main page${nl}tags: code${nl}used: 3"

# ---- bm-import and bm --merge ----

reset
printf '%s\n' "https://old.example${TAB}Kept${TAB}org" > "$BOOKMARKS"
eq 'bm-import html prints rows: entities decoded, folders as tags, web urls only' \
    "$($IMPORT "$here/fixtures/netscape.html")" "$(printf '%s\n' \
        "https://top.example/${TAB}Top level${TAB}" \
        "https://git.example/?a=1&b=2${TAB}Git & friends${TAB}dev-tools" \
        "https://sh.example/posix${TAB}POSIX sh${TAB}dev-tools shell" \
        "http://www.top.example${TAB}Top level again${TAB}")"
eq 'bm-import leaves the bookmark file alone' "$(grep -c . "$BOOKMARKS")" '1'
eq 'merge reports its counts' \
    "$($IMPORT "$here/fixtures/netscape.html" | $BM --merge)" 'added 3, skipped 1 duplicates'
eq 'merge appends only what is new' "$(cut -f1 "$BOOKMARKS" | paste -sd ' ' -)" \
    'https://old.example https://top.example/ https://git.example/?a=1&b=2 https://sh.example/posix'
eq 'merge teaches the tags' "$(grep -c -e '^dev-tools | $' -e '^shell | $' "$USERTAGS")" '2'
eq 'merging twice adds nothing' \
    "$($IMPORT "$here/fixtures/netscape.html" | $BM -m)" 'added 0, skipped 4 duplicates'
eq 'merge takes a bare list of urls' \
    "$(printf 'https://bare.example\n\n# note\n' | $BM -m; tail -n 1 "$BOOKMARKS")" \
    "$(printf 'added 1, skipped 0 duplicates\nhttps://bare.example\t\t')"
$IMPORT "$work/nosuchfile" 2>/dev/null
eq 'bm-import fails on a missing file' "$?" '1'
$IMPORT 2>/dev/null
eq 'bm-import wants one source' "$?" '2'

if command -v jq >/dev/null 2>&1; then
    eq 'bm-import json skips the trash and non-web urls, tags by folder' \
        "$($IMPORT "$here/fixtures/chromium.json")" "$(printf '%s\n' \
            "https://bar.example/${TAB}Bar site${TAB}" \
            "https://blog.example/feed${TAB}A blog${TAB}news-blogs" \
            "https://deep.example/${TAB}Deep${TAB}news-blogs tech" \
            "http://www.bar.example${TAB}Bar dupe${TAB}")"

    # profiles <dir> <folder>...: a browser directory with these profiles,
    # each with the fixture as its bookmarks.
    profiles () {
        dir=$1
        shift
        for folder; do
            mkdir -p "$dir/$folder"
            cp "$here/fixtures/chromium.json" "$dir/$folder/Bookmarks"
        done
    }
    json_rows=$(printf '%s\n' \
        "https://bar.example/${TAB}Bar site${TAB}" \
        "https://blog.example/feed${TAB}A blog${TAB}news-blogs" \
        "https://deep.example/${TAB}Deep${TAB}news-blogs tech" \
        "http://www.bar.example${TAB}Bar dupe${TAB}")
    profiles "$work/linux/.config/BraveSoftware/Brave-Browser" Default 'Profile 1'
    eq 'bm-import brave reads the bookmarks of every profile' \
        "$(HOME=$work/linux XDG_CONFIG_HOME='' LOCALAPPDATA='' $IMPORT brave)" \
        "$(printf '%s\n%s\n' "$json_rows" "$json_rows")"
    profiles "$work/mac/Library/Application Support/Google/Chrome" Default 'Profile 2'
    eq 'bm-import finds a browser in ~/Library/Application Support' \
        "$(HOME=$work/mac XDG_CONFIG_HOME='' LOCALAPPDATA='' $IMPORT chrome | wc -l | tr -d ' ')" '8'
    profiles "$work/win/Microsoft/Edge/User Data" Default
    eq 'bm-import finds a browser in LOCALAPPDATA' \
        "$(HOME=$work/nohome XDG_CONFIG_HOME='' LOCALAPPDATA=$work/win $IMPORT edge)" "$json_rows"
    HOME=$work/nohome XDG_CONFIG_HOME='' LOCALAPPDATA='' $IMPORT brave 2>/dev/null
    eq 'bm-import fails when it finds no profiles of the browser' "$?" '1'
    eq 'bm-import --files lists the bookmark file of each profile' \
        "$(HOME=$work/linux XDG_CONFIG_HOME='' LOCALAPPDATA='' $IMPORT --files brave | sed "s|^$work/linux/||")" \
        "$(printf '%s\n' '.config/BraveSoftware/Brave-Browser/Default/Bookmarks' \
            '.config/BraveSoftware/Brave-Browser/Profile 1/Bookmarks')"
    $IMPORT --files "$here/fixtures/chromium.json" 2>/dev/null
    eq 'bm-import --files wants a browser name' "$?" '2'

    # bm-watch runs bm-import and bm by name.
    WATCH="${SBM_SH:-sh} $top/bm-watch"
    reset
    eq 'bm-watch -1 imports the bookmarks of every profile' \
        "$(PATH="$top:$PATH" HOME=$work/linux XDG_CONFIG_HOME='' LOCALAPPDATA='' $WATCH -1 brave)" \
        'added 3, skipped 5 duplicates'
    eq 'bm-watch -1 again adds nothing' \
        "$(PATH="$top:$PATH" HOME=$work/linux XDG_CONFIG_HOME='' LOCALAPPDATA='' $WATCH -1 brave)" \
        'added 0, skipped 8 duplicates'
    $WATCH -1 2>/dev/null
    eq 'bm-watch wants a browser' "$?" '2'
    PATH="$top:$PATH" HOME=$work/nohome XDG_CONFIG_HOME='' LOCALAPPDATA='' $WATCH -1 brave 2>/dev/null
    eq 'bm-watch fails when it finds no profiles' "$?" '1'

    reset
    PATH="$top:$PATH" HOME=$work/linux XDG_CONFIG_HOME='' LOCALAPPDATA='' \
        $WATCH -i 1 brave >/dev/null 2>&1 &
    watcher=$!
    trap 'kill "$watcher" 2>/dev/null; rm -rf "$work"' EXIT INT TERM
    i=0
    while [ $i -lt 30 ] && ! grep -q deep.example "$BOOKMARKS"; do
        sleep 1
        i=$((i + 1))
    done
    sed 's|https://deep.example/|https://new.example/|' "$here/fixtures/chromium.json" \
        > "$work/linux/.config/BraveSoftware/Brave-Browser/Profile 1/Bookmarks"
    i=0
    while [ $i -lt 30 ] && ! grep -q new.example "$BOOKMARKS"; do
        sleep 1
        i=$((i + 1))
    done
    kill "$watcher" 2>/dev/null
    trap 'rm -rf "$work"' EXIT INT TERM
    eq 'bm-watch imports again when a bookmark file changes' \
        "$(grep -c new.example "$BOOKMARKS")" '1'
else
    printf 'skip bm-import json: no jq\n'
fi
cp "$here/../usertags" "$USERTAGS"

# ---- bm-check ----


reset
printf '%s\n' \
    "https://ok.example${TAB}Fine${TAB}" \
    "https://dead.example${TAB}Dead${TAB}" \
    "https://moved.example${TAB}Moved${TAB}" \
    "https://nohead.example${TAB}Refuses HEAD${TAB}" \
    "https://gone.example${TAB}No answer${TAB}" > "$BOOKMARKS"
out=$(PATH="$work/net:$PATH" $CHECK "$BOOKMARKS" | sort)
eq 'bm-check lists dead and moved links only' "$out" "$(printf '%s\n' \
    "000${TAB}https://gone.example" \
    "301${TAB}https://moved.example${TAB}https://new.example/" \
    "404${TAB}https://dead.example")"
PATH="$work/net:$PATH" $CHECK "$BOOKMARKS" >/dev/null
eq 'bm-check exits 1 when something is wrong' "$?" '1'
eq 'bm-check is a filter' \
    "$($BM -l | PATH="$work/net:$PATH" $CHECK - | cut -f2 | sort | paste -sd ' ' -)" \
    'https://dead.example https://gone.example https://moved.example'
eq 'bm-check takes a plain list of urls' \
    "$(printf 'https://dead.example\nhttps://ok.example\n' | PATH="$work/net:$PATH" $CHECK -)" \
    "404${TAB}https://dead.example"
many=$(i=0; while [ $i -lt 40 ]; do printf 'https://dead%d.example\n' $i; i=$((i + 1)); done)
eq 'bm-check reports every link of a long list exactly once' \
    "$(printf '%s\n' "$many" | PATH="$work/net:$PATH" $CHECK - | cut -f2 | sort -u | wc -l | tr -d ' ')" '40'
eq 'bm-check copes with an empty list' "$(: | PATH="$work/net:$PATH" $CHECK -; echo $?)" '0'
eq 'bm-check says nothing about healthy links' \
    "$(printf 'https://ok.example\n' | PATH="$work/net:$PATH" $CHECK -; echo $?)" '0'

# ---- bm-commit ----

if command -v git >/dev/null 2>&1; then
    export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
    export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
    repo="$work/repo"
    git init -q "$repo"
    mkdir "$repo/nested"
    commits () { git -C "$repo" rev-list --count HEAD 2>/dev/null || echo 0; }
    PATH_WAS=$PATH
    PATH="$top:$PATH"

    (
        BOOKMARKS="$repo/bookmarks" USERTAGS="$repo/usertags"
        cp "$here/../usertags" "$USERTAGS"
        answers 'In repo' 'code viagit'
        $BM -a https://git1.example 2>/dev/null
        answers 'In repo'
        $BM -c
        answers 'In repo'
        $BM -d >/dev/null
    )
    eq 'add and delete are committed in a dedicated repository' "$(commits)" '2'
    eq 'commit messages say what happened' \
        "$(git -C "$repo" log --format=%s | paste -sd '|' -)" \
        'bm: delete https://git1.example|bm: add https://git1.example'
    eq 'bookmarks and tags are tracked, use counts are not' \
        "$(git -C "$repo" ls-files | paste -sd ' ' -)" 'bookmarks usertags'

    (
        BOOKMARKS="$repo/nested/bookmarks"
        answers 'Nested' 'code'
        $BM -a https://git2.example 2>/dev/null
    )
    eq 'a shared repository is left alone' "$(commits)" '2'
    (
        BOOKMARKS="$repo/nested/bookmarks"
        answers 'Forced' 'code'
        SBM_GIT=1 $BM -a https://git3.example 2>/dev/null
    )
    eq 'SBM_GIT=1 commits in a shared repository' "$(commits)" '3'
    (
        BOOKMARKS="$repo/bookmarks" USERTAGS="$repo/usertags"
        answers 'Off' 'code'
        SBM_GIT=0 $BM -a https://git4.example 2>/dev/null
    )
    eq 'SBM_GIT=0 never commits' "$(commits)" '3'
    PATH=$PATH_WAS
    (
        BOOKMARKS="$repo/bookmarks"
        answers 'Not installed' 'code'
        $BM -a https://git5.example 2>/dev/null
    )
    eq 'without bm-commit on PATH bm does not touch git' "$(commits)" '3'
else
    printf 'skip git: no git\n'
fi

# ---- fzf backend: the browser ----

mkdir "$work/fzfbin"
cp "$here/fakefzf" "$work/fzfbin/fzf"
chmod +x "$work/fzfbin/fzf"
export SBM_TEST_LOG="$work/menulog"

# fz <bm arguments>: run bm against the fake fzf.
fz () {
    PATH="$work/fzfbin:$PATH" SBM_MENU=fzf $BM "$@"
}

seed
answers 'enter:Zed'
fz </dev/null
eq 'browse: ENTER opens' "$(cat "$work/opened")" 'https://b.example'

answers 'ctrl-y:Alpha'
fz </dev/null
eq 'browse: ctrl-y copies' "$(cat "$work/clipboard")" 'https://c.example'

answers ''
fz </dev/null
eq 'browse: ESC exits 1' "$?" '1'

: > "$SBM_TEST_LOG"
answers 'ctrl-s:' 'ctrl-s:' ''
fz </dev/null
eq 'browse: ctrl-s cycles the sort order' \
    "$(grep -o 'sort \[[a-z]*\]' "$SBM_TEST_LOG" | paste -sd ' ' -)" \
    'sort [used] sort [recent] sort [url]'

# Tags need no key of their own: fzf matches the tags column like the rest.
: > "$SBM_TEST_LOG"
answers ''
fz </dev/null
eq 'browse: no tag filter key' "$(grep -c -e 'ctrl-t' -e '\^T' "$SBM_TEST_LOG")" '0'

answers 'ctrl-d:Zed' ''
printf 'n\n' | fz 2>/dev/null
eq 'browse: ctrl-d asks first' "$(grep -c . "$BOOKMARKS")" '3'
answers 'ctrl-d:Zed' ''
printf 'y\n' | fz 2>/dev/null
eq 'browse: ctrl-d deletes after a yes' "$(cut -f1 "$BOOKMARKS" | paste -sd ' ' -)" \
    'https://a.example https://c.example'

answers 'ctrl-a:' 'fresh:' ':code' ''
printf 'https://added.example\nAdded here\n' | fz 2>/dev/null
eq 'browse: ctrl-a adds, fzf tag picker creates typed tags' \
    "$(grep added.example "$BOOKMARKS")" "https://added.example${TAB}Added here${TAB}code fresh"

answers 'ctrl-a:' 'enter:Mid'
out=$(printf 'https://a.example\n\n' | fz 2>&1)
eq 'browse: a refused duplicate is shown, then the list comes back' \
    "$(printf '%s\n' "$out" | grep -c 'already bookmarked; press ENTER') $(cat "$work/opened")" \
    '1 https://a.example'

rm -f "$work/opened"
answers 'enter:posix sh printf'
fz </dev/null
eq 'browse: text that matches nothing is searched for on the web' \
    "$(cat "$work/opened")" 'https://duckduckgo.com/?q=posix+sh+printf'

: > "$SBM_TEST_LOG"
answers 'ctrl-s:' ''
fz </dev/null
eq 'browse: the preview follows the cursor' \
    "$(grep -c -e "--preview=printf '%s.n%s.ntags: %s.nused: %s.n.n' {1} {2} {3} {4}; sleep 0.3 2>/dev/null; bm-page {1} 2>/dev/null" "$SBM_TEST_LOG")" '2'

: > "$SBM_TEST_LOG"
answers 'Mid'
fz -c </dev/null
eq 'fzf: rows are listed by their display column, with a live preview' \
    "$(grep -c -e "--with-nth=5.. --preview-window=right:50%:wrap --preview=printf '%s" "$SBM_TEST_LOG")" '1'
: > "$SBM_TEST_LOG"
answers 'Mid'
SBM_FZF_OPTS='--height=100%' fz -c </dev/null
eq 'fzf: SBM_FZF_OPTS is passed along' "$(grep -c -e '--height=40% --height=100%' "$SBM_TEST_LOG")" '1'
cp "$here/../usertags" "$USERTAGS"

# ---- dmenu backend: its behaviour must not change ----

# dm <bm arguments>: run bm against the fake dmenu.
dm () {
    PATH="$work/bin:$PATH" SBM_MENU=dmenu $BM "$@"
}

seed
: > "$SBM_TEST_LOG"
answers 'Zed' 'copy'
dm
eq 'dmenu: no arguments asks for the bookmark, then what to do' \
    "$(cat "$work/clipboard")" 'https://b.example'
eq 'dmenu: the two menus' "$(sed 's/.* -p //' "$SBM_TEST_LOG" | paste -sd ' ' -)" 'bookmark: do:'
eq 'dmenu: is called with its usual flags' "$(sed 's/ -p .*//' "$SBM_TEST_LOG" | sort -u)" \
    'dmenu -i -l 15'
eq 'dmenu: DMENULINES is honoured' \
    "$(: > "$SBM_TEST_LOG"; answers 'Zed'; DMENULINES=7 dm -c; cat "$SBM_TEST_LOG")" \
    'dmenu -i -l 7 -p copy:'

answers 'Mid'
dm -o
eq 'dmenu: open' "$(cat "$work/opened")" 'https://a.example'

answers 'Alpha'
dm -d >/dev/null
eq 'dmenu: delete' "$(cut -f1 "$BOOKMARKS" | paste -sd ' ' -)" 'https://b.example https://a.example'

reset
printf 'not a url\n' > "$work/clipboard"
: > "$SBM_TEST_LOG"
answers 'https://typed-dm.example' 'Typed in dmenu' 'code' 'sec' 'typednew' 'done'
dm -a 2>/dev/null
eq 'dmenu: add loops over tags until done, typed tags included' \
    "$(cat "$BOOKMARKS")" "https://typed-dm.example${TAB}Typed in dmenu${TAB}code sec typednew"
eq 'dmenu: prompts keep their order' \
    "$(sed 's/.* -p //' "$SBM_TEST_LOG" | paste -sd ' ' -)" \
    'url: description: tags: tags: tags: tags:'

reset
printf 'https://selection.example\n' > "$work/clipboard"
answers '<default>' 'From selection' 'done'
dm -a 2>/dev/null
eq 'dmenu: the selection is offered as the url' \
    "$(cut -f1 "$BOOKMARKS")" 'https://selection.example'
cp "$here/../usertags" "$USERTAGS"

# Which menu is picked when the user has not said.
seed
both="$work/bin:$work/fzfbin"
: > "$SBM_TEST_LOG"
answers 'Zed' 'copy'
( unset SBM_MENU WAYLAND_DISPLAY; PATH="$both:$PATH" DISPLAY=:0 $BM </dev/null )
eq 'a display without a terminal means dmenu even when fzf exists' \
    "$(cut -d' ' -f1 "$SBM_TEST_LOG" | sort -u)" 'dmenu'

: > "$SBM_TEST_LOG"
answers 'Zed' 'copy'
( unset SBM_MENU DISPLAY; PATH="$both:$PATH" WAYLAND_DISPLAY=wayland-0 $BM </dev/null )
eq 'Wayland means dmenu too' "$(cut -d' ' -f1 "$SBM_TEST_LOG" | sort -u)" 'dmenu'

: > "$SBM_TEST_LOG"
answers 'enter:Zed'
( unset SBM_MENU DISPLAY WAYLAND_DISPLAY; PATH="$both:$PATH" $BM </dev/null )
eq 'no display falls back to fzf' "$(cut -d' ' -f1 "$SBM_TEST_LOG" | sort -u)" 'fzf'

# In a terminal bm picks fzf even with a display, because the fzf preview
# shows the page. script (util-linux) gives bm a terminal; without it the
# test cannot run.
if SHELL=/bin/sh script -eqc 'test -t 0' /dev/null </dev/null >/dev/null 2>&1; then
    : > "$SBM_TEST_LOG"
    answers 'enter:Zed'
    ( unset SBM_MENU WAYLAND_DISPLAY; export PATH="$both:$PATH" DISPLAY=:0
      SHELL=/bin/sh script -eqc "$BM" /dev/null </dev/null >/dev/null 2>&1 )
    eq 'a display with a terminal means fzf, whose preview shows the page' \
        "$(cut -d' ' -f1 "$SBM_TEST_LOG" | sort -u)" 'fzf'
    : > "$SBM_TEST_LOG"
    answers 'Zed' 'copy'
    ( unset WAYLAND_DISPLAY; export PATH="$both:$PATH" DISPLAY=:0 SBM_MENU=dmenu
      SHELL=/bin/sh script -eqc "$BM" /dev/null </dev/null >/dev/null 2>&1 )
    eq 'SBM_MENU=dmenu keeps dmenu in a terminal' "$(cut -d' ' -f1 "$SBM_TEST_LOG" | sort -u)" 'dmenu'
else
    printf 'skip the menu in a terminal: util-linux script is not installed\n'
fi

unset SBM_TEST_LOG

# ---- one-screen browsing without key bindings (dmenu, custom menus) ----

seed
export SBM_TEST_SEEN="$work/seen"

answers 'Zed' 'open'
$BM
eq 'browse: pick, then open' "$(cat "$work/opened")" 'https://b.example'

: > "$SBM_TEST_SEEN"
answers 'Zed' 'copy'
$BM
eq 'browse: the second menu shows the bookmark in full, below the actions' \
    "$(sed -n '/^--- pick do:/,$p' "$SBM_TEST_SEEN" | sed 1d | paste -sd '|' -)" \
    'open|copy|edit|delete|  https://b.example|  Zed|  tags: code lib|  used: 1'
eq 'browse: the list starts with [add] and hides the use counts' \
    "$(sed -n '2,3p' "$SBM_TEST_SEEN" | paste -sd '|' -)" \
    "[add]|https://b.example${TAB}Zed${TAB}code lib"

rm -f "$work/opened"
answers 'Zed' '' 'Mid' 'open'
$BM
eq 'browse: closing the second menu goes back to the list' \
    "$(cat "$work/opened")" 'https://a.example'

answers 'Zed' '  tags: code lib' 'Mid' 'open'
$BM
eq 'browse: picking a detail line does nothing' "$(cat "$work/opened")" 'https://a.example'

answers 'Alpha' 'delete' ''
$BM
eq 'browse: delete comes back to the list, closing the list leaves' \
    "$? $(cut -f1 "$BOOKMARKS" | paste -sd ' ' -)" '1 https://b.example https://a.example'

answers '[add]' 'https://viamenu.example' 'Via menu' 'code' ''
$BM 2>/dev/null
eq 'browse: [add] adds and comes back' "$(grep -c "^https://viamenu.example${TAB}Via menu${TAB}code$" "$BOOKMARKS")" '1'

: > "$SBM_TEST_SEEN"
answers '[add]' 'https://www.a.example/' 'seen' ''
$BM 2>/dev/null
eq 'browse: a refused duplicate is announced in a menu' \
    "$(grep -c '^--- ask already bookmarked; press ENTER' "$SBM_TEST_SEEN")" '1'

: > "$SBM_TEST_SEEN"
answers '[add]' '' ''
$BM 2>/dev/null
eq 'browse: a cancelled add just comes back' \
    "$(grep -c 'already bookmarked' "$SBM_TEST_SEEN") $(grep -c '^--- pick bookmark:' "$SBM_TEST_SEEN")" '0 2'
unset SBM_TEST_SEEN

# ---- web search from the bookmark menu ----

seed
rm -f "$work/opened" "$BOOKMARKS.usage"
printf '%s\n' 'w   | https://en.wikipedia.org/w/index.php?search=%s' \
              'gh | https://github.com/search?q=%s&type=repositories' > "$work/engines"
export SBM_ENGINES="$work/engines"

# went <typed text> [bm arguments]: where typing that into the menu leads.
went () {
    typed=$1
    shift
    rm -f "$work/opened"
    answers "$typed"
    $BM "$@" 2>/dev/null
    cat "$work/opened" 2>/dev/null
}

eq 'open: a bookmark is opened' "$(went Zed -o)" 'https://b.example'
eq 'open: other words are searched for' "$(went 'posix sh printf' -o)" \
    'https://duckduckgo.com/?q=posix+sh+printf'
eq 'open: the query is url-encoded, byte by byte' "$(went 'c++ & más?' -o)" \
    'https://duckduckgo.com/?q=c%2B%2B+%26+m%C3%A1s%3F'
eq 'open: one word is searched for too' "$(went suckless -o)" \
    'https://duckduckgo.com/?q=suckless'
eq 'open: something with a dot is an address' "$(went 'example.org/a?b=c' -o)" \
    'https://example.org/a?b=c'
eq 'open: a url is opened as it is' "$(went 'ftp://files.example/x' -o)" 'ftp://files.example/x'
eq 'open: an engine keyword picks the engine' "$(went 'w dynamic menu' -o)" \
    'https://en.wikipedia.org/w/index.php?search=dynamic+menu'
eq 'open: an engine url may go on after the query' "$(went 'gh dmenu' -o)" \
    'https://github.com/search?q=dmenu&type=repositories'
eq 'open: a keyword alone is just a word' "$(went w -o)" 'https://duckduckgo.com/?q=w'
eq 'open: an unknown keyword is part of the query' "$(went 'zz top' -o)" \
    'https://duckduckgo.com/?q=zz+top'
eq 'open: SBM_SEARCH sets the default engine' \
    "$(SBM_SEARCH='https://search.example/?s=%s' went 'two words' -o)" \
    'https://search.example/?s=two+words'
eq 'open: works without an engines file' "$(SBM_ENGINES="$work/none" went 'w dynamic menu' -o)" \
    'https://duckduckgo.com/?q=w+dynamic+menu'
eq 'browse: typed text is searched for as well' "$(went 'w dmenu')" \
    'https://en.wikipedia.org/w/index.php?search=dmenu'
eq 'only bookmarks are counted as used' "$(cut -f1 "$BOOKMARKS.usage")" 'https://b.example'
went '' -o >/dev/null
eq 'open: closing the menu exits 1' "$?" '1'
unset SBM_ENGINES

# ---- bm-html ----

reset
printf '%s\n' \
    "https://b.example/?a=1&b=2${TAB}B <b>bold</b> & \"quoted\"${TAB}code lib" \
    "https://a.example${TAB}${TAB}" \
    '# a comment' \
    "javascript:alert(1)${TAB}Bookmarklet${TAB}code" \
    "https://c.example/x${TAB}see${TAB}code" > "$BOOKMARKS"
page=$($HTML -t 'My <marks>' "$BOOKMARKS")
eq 'bm-html lists a bookmark under each of its tags, and the untagged' \
    "$(printf '%s\n' "$page" | grep -c '^<li>') $(printf '%s\n' "$page" | grep '<h2' | sed 's/.*id="\([^"]*\)".*/\1/' | paste -sd ' ' -)" \
    '4 code lib untagged'
eq 'bm-html escapes text and attributes' \
    "$(printf '%s\n' "$page" | grep -c '<li><a href="https://b.example/?a=1&amp;b=2">B &lt;b&gt;bold&lt;/b&gt; &amp; &quot;quoted&quot;</a> <small>b.example</small>')" '2'
eq 'bm-html escapes the title' "$(printf '%s\n' "$page" | grep -c '<title>My &lt;marks&gt;</title>')" '1'
eq 'bm-html never links to script' "$(printf '%s\n' "$page" | grep -ci 'javascript:')" '0'
eq 'bm-html shows the url when there is no description' \
    "$(printf '%s\n' "$page" | grep -c '<a href="https://a.example">https://a.example</a>')" '1'
eq 'bm-html sorts by description within a tag' \
    "$(printf '%s\n' "$page" | sed -n '/id="code"/,/<\/ul>/p' | grep -c .) $(printf '%s\n' "$page" | sed -n '/id="code"/,/<\/ul>/p' | sed -n 3p | grep -c 'B &lt;b')" '5 1'
eq 'bm-html has one inline script, a filter box hidden without it, and ?q=' \
    "$(printf '%s\n' "$page" | grep -c '<script>') $(printf '%s\n' "$page" | grep -c '<input id=q type=search placeholder="filter 3 bookmarks" hidden>') $(printf '%s\n' "$page" | grep -c 'URLSearchParams(location.search).get("q")')" \
    '1 1 1'
eq 'bm-html loads nothing from elsewhere' "$(printf '%s\n' "$page" | grep -c -e ' src=' -e '<link' -e '@import')" '0'
eq 'bm-html has a preview pane that only its script shows, with a sandboxed frame and no referrer' \
    "$(printf '%s\n' "$page" | grep -c '^<aside id=preview hidden>') $(printf '%s\n' "$page" | grep -c '<iframe title="Preview of the page" sandbox="allow-scripts allow-same-origin" referrerpolicy=no-referrer></iframe></aside>') $(printf '%s\n' "$page" | grep -c 'pane.hidden=false')" \
    '1 1 1'
eq 'bm-html is a filter' "$($BM -t lib -l | $HTML - | grep -c '^<li>')" '2'
eq 'bm-html reads the bookmark file by default, whatever stdin is' \
    "$($HTML </dev/null | grep -c '^<li>')" '4'
eq 'bm-check reads the bookmark file by default too' \
    "$(PATH="$work/net:$PATH" $CHECK </dev/null; echo $?)" '0'
$HTML --bogus 2>/dev/null </dev/null
eq 'bm-html rejects unknown options' "$?" '2'
if command -v node >/dev/null 2>&1; then
    printf '%s\n' "$page" | sed -n '/<script>/,/<\/script>/p' | sed '1d;$d' > "$work/page.js"
    node --check "$work/page.js" 2>/dev/null
    eq 'bm-html: the script parses' "$?" '0'
fi

# ---- bm-sync ----

# A stand-in for curl that plays an sbm-sync server. The file of the server
# is $srv/file. Lines in $srv/other come from another device, once. With
# $srv/code, the server refuses with that status. With $srv/touch, bm adds a
# bookmark while the request runs. Without a version, the server deletes
# nothing, as the real one: it keeps its file and adds the new lines. With
# $srv/broken, the answer is a directory, so bm-sync cannot write it. With
# $srv/hold, a process takes the write lock of bm while the request runs,
# and keeps it; its pid goes to $srv/holder.
srv="$work/srv"
mkdir "$srv" "$work/syncnet"
cat > "$work/syncnet/curl" <<'FAKE'
#!/bin/sh
printf '%s\n' "$*" >> "$SBM_TEST_SRV/argv"
out= head= data= auth= url= password=
while [ $# -gt 0 ]; do
    case $1 in
        -o) out=$2; shift ;;
        -D) head=$2; shift ;;
        -w|--max-time|-X) shift ;;
        -H) case $2 in @*) auth=$(cat "${2#@}") ;; esac; shift ;;
        --data-binary) data=${2#@}; shift ;;
        --data-urlencode) case $2 in password@-) password=$(cat) ;; esac; shift ;;
        -*) ;;
        *) url=$1 ;;
    esac
    shift
done
answer () { printf '%s\n' "$2" > "$out"; printf '%s' "$1"; exit 0; }
case $url in
    */api/login)
        [ "$password" = 'secret pass ' ] || answer 401 'wrong email or password'
        answer 200 tok123 ;;
    */api/logout)
        echo logout >> "$SBM_TEST_SRV/log"
        exit 0 ;;
esac
[ "$auth" = 'Authorization: Bearer tok123' ] || answer 401 'not signed in'
[ ! -e "$SBM_TEST_SRV/code" ] || answer "$(cat "$SBM_TEST_SRV/code")" 'sync is paused'
base=${url#*base=}
printf '%s\n' "$base" >> "$SBM_TEST_SRV/bases"
if [ -z "$base" ]; then
    cat "$SBM_TEST_SRV/file" "$data" 2>/dev/null | awk '!seen[$0]++' > "$SBM_TEST_SRV/union"
    data=$SBM_TEST_SRV/union
fi
cat "$data" "$SBM_TEST_SRV/other" > "$SBM_TEST_SRV/file" 2>/dev/null
rm -f "$SBM_TEST_SRV/other"
version=v$(cksum < "$SBM_TEST_SRV/file" | cut -d' ' -f1)
echo "$version" >> "$SBM_TEST_SRV/versions"
cp "$SBM_TEST_SRV/file" "$out"
[ ! -e "$SBM_TEST_SRV/broken" ] || { rm -f "$out"; mkdir "$out"; }
printf 'HTTP/1.1 200 OK\r\nsbm-version: %s\r\n\r\n' "$version" > "$head"
if [ -e "$SBM_TEST_SRV/touch" ]; then
    rm -f "$SBM_TEST_SRV/touch"
    printf 'https://c.example\tC\t\n' >> "$BOOKMARKS"
fi
if [ -e "$SBM_TEST_SRV/hold" ]; then
    sleep 30 >/dev/null 2>&1 &
    echo $! > "$SBM_TEST_SRV/holder"
    mkdir "$BOOKMARKS.lock" && echo $! > "$BOOKMARKS.lock/pid"
fi
printf 200
FAKE
chmod +x "$work/syncnet/curl"
export SBM_TEST_SRV="$srv"
bmsync () {
    PATH="$work/syncnet:$PATH" ${SBM_SH:-sh} "$top/bm-sync" "$@"
}

reset
printf 'https://a.example\tA\t\n' > "$BOOKMARKS"
bmsync 2>"$work/err"
eq 'bm-sync without an account says how to sign in' "$?:$(grep -c 'bm-sync login' "$work/err")" '1:1'

printf 'me@example.org\nsecret pass \n' | bmsync login https://sync.example/ >/dev/null 2>&1
eq 'bm-sync login keeps the token in a file that only you can read' \
    "$(ls -l "$SBM_SYNC_CONFIG" | cut -c1-10) $(paste -sd ' ' - < "$SBM_SYNC_CONFIG")" \
    '-rw------- server=https://sync.example token=tok123'
eq 'the password and the token never go on the command line' \
    "$(grep -c -e secret -e tok123 "$srv/argv")" '0'
eq 'bm-sync login syncs at once, from no version' \
    "$(cat "$srv/file"):$(sed -n 1p "$srv/bases")" "https://a.example${TAB}A${TAB}:"

printf 'https://b.example\tB\t\n' > "$srv/other"
bmsync -q
eq 'bm-sync brings the bookmarks of other devices' \
    "$(cut -f1 "$BOOKMARKS" | paste -sd ' ' -)" 'https://a.example https://b.example'
eq 'bm-sync sends the version of the last sync' "$(sed -n 2p "$srv/bases")" "$(sed -n 1p "$srv/versions")"

: > "$srv/touch"
bmsync -q
eq 'a bookmark added during a sync gets to the server too' \
    "$(grep -c c.example "$srv/file") $(grep -c c.example "$BOOKMARKS")" '1 1'

echo 402 > "$srv/code"
cp "$BOOKMARKS" "$work/before"
bmsync -q 2>"$work/err"
eq 'bm-sync shows why the server refused, and keeps the file' \
    "$?:$(cat "$work/err"):$(cmp -s "$work/before" "$BOOKMARKS" && echo same)" \
    '1:bm-sync: sync is paused:same'
rm -f "$srv/code"

chmod 644 "$SBM_SYNC_CONFIG"
printf 'me@example.org\nsecret pass \n' | bmsync login https://sync.example/ >/dev/null 2>&1
eq 'bm-sync login makes a config file that exists already private too' \
    "$(ls -l "$SBM_SYNC_CONFIG" | cut -c1-10)" '-rw-------'

# kept: the version that bm-sync sent last, then "kept" if the server still
# has all bookmarks, then "back" if the file has all of them again.
cp "$srv/file" "$work/before"
kept () {
    printf '%s:%s:%s' "$(sed -n '$p' "$srv/bases")" \
        "$(cmp -s "$work/before" "$srv/file" && echo kept)" \
        "$(cmp -s "$work/before" "$BOOKMARKS" && echo back)"
}
: > "$BOOKMARKS"
bmsync -q
eq 'bm-sync sends an empty file without a version, so the server deletes nothing' \
    "$(kept)" ':kept:back'
rm -f "$BOOKMARKS"
bmsync -q
eq 'bm-sync sends a missing file without a version too' "$(kept)" ':kept:back'

: > "$srv/broken"
bmsync -q 2>"$work/err"
eq 'when bm-sync cannot write the file, it says so and forgets the version' \
    "$?:$(grep -c 'cannot write' "$work/err"):$([ -e "$BOOKMARKS.sync" ] || echo none)" '1:1:none'
rm -f "$srv/broken"
# The write stopped after the first line.
sed -n 1p "$work/before" > "$BOOKMARKS"
bmsync -q
eq 'after a failed write, the next sync has no version, so the server deletes nothing' \
    "$(kept)" ':kept:back'

# While bm holds its write lock, bm-sync neither reads nor writes the file.
export SBM_LOCK_WAIT=1
cp "$BOOKMARKS" "$work/before"
cp "$BOOKMARKS.sync" "$work/state"
printf 'https://other.example\tOther\t\n' > "$srv/other"
sleep 30 >/dev/null 2>&1 &
holder=$!
mkdir "$BOOKMARKS.lock" && echo "$holder" > "$BOOKMARKS.lock/pid"
bmsync -q 2>"$work/err"
rc=$?
kill "$holder"
rm -rf "$BOOKMARKS.lock"
eq 'bm-sync does not read the file while bm holds the lock, and says why' \
    "$rc:$(grep -c 'in use' "$work/err"):$(cmp -s "$work/before" "$BOOKMARKS" && echo same)" \
    '1:1:same'
# bm takes the lock while the request runs: bm-sync must not write.
: > "$srv/hold"
bmsync -q 2>"$work/err"
rc=$?
kill "$(cat "$srv/holder")"
rm -rf "$BOOKMARKS.lock" "$srv/hold"
eq 'bm-sync does not write while bm holds the lock, and keeps the old version' \
    "$rc:$(cmp -s "$work/before" "$BOOKMARKS" && echo same):$(cmp -s "$work/state" "$BOOKMARKS.sync" && echo same)" \
    '1:same:same'
printf 'https://other.example\tOther\t\n' > "$srv/other"
bmsync -q
eq 'after the lock is free, the next sync brings the change of the other device' \
    "$(grep -c other.example "$BOOKMARKS"):$(ls -d "$BOOKMARKS.lock" 2>/dev/null)" '1:'
unset SBM_LOCK_WAIT

bmsync -q logout
eq 'bm-sync logout forgets the token and signs out on the server' \
    "$([ -e "$SBM_SYNC_CONFIG" ] || echo gone) $(cat "$srv/log")" 'gone logout'
eq 'bm-sync leaves no lock behind' "$(ls -d "$BOOKMARKS.sync.lock" 2>/dev/null)" ''

printf 'me@example.org
secret pass 
' | bmsync login >/dev/null 2>&1
eq 'bm-sync login without a server uses sbmsync.com'     "$(sed -n 1p "$SBM_SYNC_CONFIG")" 'server=https://sbmsync.com'
bmsync -q logout
unset SBM_TEST_SRV

# bm starts bm-sync after each change. A stand-in bm-sync records the config
# that it gets: it must be the one of the tests, never that of the user.
mkdir "$work/stubsync"
# shellcheck disable=SC2016
printf '#!/bin/sh\nprintf "%%s\\n" "$SBM_SYNC_CONFIG" >> "%s"\n' "$work/stubsync.log" \
    > "$work/stubsync/bm-sync"
chmod +x "$work/stubsync/bm-sync"
reset
answers 'Stub' ''
PATH="$work/stubsync:$PATH" $BM -a https://stub.example 2>/dev/null
i=0
while [ ! -s "$work/stubsync.log" ] && [ $i -lt 5 ]; do
    sleep 1
    i=$((i + 1))
done
eq 'bm starts bm-sync with the config of the tests, never the real one' \
    "$(sort -u "$work/stubsync.log")" "$work/sync.conf"

# ---- the write lock of the bookmark file ----

# hold: a live process takes the write lock; its pid goes to $holder.
hold () {
    sleep 30 >/dev/null 2>&1 &
    holder=$!
    mkdir "$BOOKMARKS.lock" && echo "$holder" > "$BOOKMARKS.lock/pid"
}
free () {
    kill "$holder" 2>/dev/null
    rm -rf "$BOOKMARKS.lock"
}

reset
# The other process adds a line after two seconds, and then frees the lock.
mkdir "$BOOKMARKS.lock"
( sleep 2; printf 'https://first.example\tFirst\t\n' >> "$BOOKMARKS"
  rm -rf "$BOOKMARKS.lock" ) &
first=$!
echo "$first" > "$BOOKMARKS.lock/pid"
answers 'Second' ''
SBM_LOCK_WAIT=10 $BM -a https://second.example 2>/dev/null
wait "$first"
eq 'add waits for the lock, and adds after the change of the other process' \
    "$(cut -f1 "$BOOKMARKS" | paste -sd ' ' -)" 'https://first.example https://second.example'

reset
printf 'https://kept.example\tKept\t\n' > "$BOOKMARKS"
hold
answers 'New' ''
SBM_LOCK_WAIT=1 $BM -a https://new.example 2>"$work/err"
eq 'add stops when the lock stays, says why, and changes nothing' \
    "$?:$(grep -c 'in use' "$work/err"):$(cut -f1 "$BOOKMARKS")" '1:1:https://kept.example'
answers 'Kept'
SBM_LOCK_WAIT=1 $BM -d >/dev/null 2>&1
eq 'delete waits for the lock too' "$(cut -f1 "$BOOKMARKS")" 'https://kept.example'
printf 'https://merged.example\n' | SBM_LOCK_WAIT=1 $BM -m >/dev/null 2>&1
eq 'merge waits for the lock too' "$(cut -f1 "$BOOKMARKS")" 'https://kept.example'
free

reset
sh -c 'exit 0' &
gone=$!
wait "$gone"
mkdir "$BOOKMARKS.lock" && echo "$gone" > "$BOOKMARKS.lock/pid"
answers 'After' ''
SBM_LOCK_WAIT=1 $BM -a https://after.example 2>/dev/null
eq 'add takes over the lock of a process that is gone, and frees it' \
    "$(cut -f1 "$BOOKMARKS"):$(ls -d "$BOOKMARKS.lock" 2>/dev/null)" 'https://after.example:'

reset
printf 'https://ed.example\tEd\t\n' > "$BOOKMARKS"
printf '#!/bin/sh\n[ -d "%s" ] && echo locked > "%s"\n' \
    "$BOOKMARKS.lock" "$work/edit.log" > "$work/editor"
chmod +x "$work/editor"
answers 'Ed'
VISUAL="$work/editor" $BM -e 2>/dev/null
eq 'edit holds the lock while the editor runs, and frees it after' \
    "$(cat "$work/edit.log" 2>/dev/null):$(ls -d "$BOOKMARKS.lock" 2>/dev/null)" 'locked:'

# ---- make install ----

if command -v make >/dev/null 2>&1; then
    make -s -C "$top" install DESTDIR="$work/dest" PREFIX=/usr TOOLS='bm bm-html' >/dev/null
    eq 'make install installs what TOOLS names, and only that' \
        "$(cd "$work/dest/usr/bin" && for f in *; do [ -x "$f" ] && printf '%s ' "$f"; done)" 'bm bm-html '
    eq 'make install puts sbm in the app menu: bm in a terminal, so fzf with the preview' \
        "$(grep -E '^(Exec|Terminal)=' "$work/dest/usr/share/applications/sbm.desktop" | paste -sd '|' -)" \
        'Exec=env SBM_FZF_OPTS=--no-height bm|Terminal=true'
    make -s -C "$top" uninstall DESTDIR="$work/dest" PREFIX=/usr >/dev/null
    eq 'make uninstall removes the app-menu entry' \
        "$(ls "$work/dest/usr/share/applications" | wc -l | tr -d ' ')" '0'
fi

# ---- Windows installer ----

# The installer runs sbm-setup with the PATH of Windows. That PATH has no
# Cygwin tools.
case $(uname -s) in
    CYGWIN*)
        XDG_DATA_HOME="$work/setup" PATH="$work/nobin" \
            "$(command -v "${SBM_SH:-sh}")" "$top/contrib/windows/sbm-setup" data 2>/dev/null
        eq 'sbm-setup finds the Cygwin tools when the PATH has none' \
            "$([ -d "$work/setup/sbm" ] && echo yes)" 'yes'
        ;;
esac

# ---- defaults ----

(
    unset BOOKMARKS
    $BM -l
)
eq 'default bookmark file is created under XDG_DATA_HOME' \
    "$([ -f "$work/xdg/sbm/bookmarks" ] && echo yes)" 'yes'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
