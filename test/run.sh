#!/bin/sh

# Non-interactive tests for bm. Menus are scripted through test/fakemenu, and
# the clipboard and opener are stubs that write to files.
# usage: sh test/run.sh        (SBM_SH=dash sh test/run.sh to pick the shell)

# Several groups point BOOKMARKS somewhere else inside a subshell on purpose.
# shellcheck disable=SC2030,SC2031

here=$(cd "$(dirname "$0")" && pwd)
BM="${SBM_SH:-sh} $here/../bm"
TAB=$(printf '\t')

work=$(mktemp -d "${TMPDIR:-/tmp}/sbmtest.XXXXXX") || exit 1
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
    eq "add rejects duplicate $dup" "$rc $(wc -l < "$BOOKMARKS" | tr -d ' ')" '1 1'
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

answers 'example'
$BM -t sec
eq 'a tag filter alone implies copy' \
    "$(cat "$work/clipboard")" 'https://a.example'

$BM -t nosuchtag -c 2>/dev/null
eq 'copy with an unused tag fails' "$?" '1'

answers 'copy' 'Sea'
$BM
eq 'no arguments prompts for the action' \
    "$(cat "$work/clipboard")" 'https://c.example'

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

# ---- migrate ----

reset
printf '%s\n' \
    'https://old.example Old style | code sec' \
    'https://equwal.com  Spenser Truex'"'"'s website.' \
    'https://pipe.example a | b | lib' \
    "https://new.example${TAB}Already TSV${TAB}org" > "$BOOKMARKS"
expected=$(printf '%s\n' \
    "https://old.example${TAB}Old style${TAB}code sec" \
    "https://equwal.com${TAB}Spenser Truex's website.${TAB}" \
    "https://pipe.example${TAB}a | b${TAB}lib" \
    "https://new.example${TAB}Already TSV${TAB}org")

eq 'old format triggers a warning' \
    "$($BM -l 2>&1 >/dev/null | grep -c -- '--migrate')" '1'
$BM --migrate >/dev/null
eq 'migrate converts old lines to TSV' "$(cat "$BOOKMARKS")" "$expected"
eq 'migrate leaves a backup' "$(grep -c . "$BOOKMARKS.bak")" '4'
$BM --migrate >/dev/null
eq 'migrate is idempotent' "$(cat "$BOOKMARKS")" "$expected"
eq 'no warning after migrating' "$($BM -l 2>&1 >/dev/null)" ''
# backups: how many backups sit beside the bookmark file.
backups () {
    set -- "$BOOKMARKS".bak*
    if [ -e "$1" ]; then echo $#; else echo 0; fi
}
eq 'migrating again leaves the backup of the original alone' \
    "$(grep -c ' | ' "$BOOKMARKS.bak") $(backups)" '2 1'

printf '%s\n' 'https://late.example Added by hand | org' >> "$BOOKMARKS"
$BM --migrate >/dev/null
eq 'a later migration backs up beside the first, not over it' \
    "$(grep -c ' | ' "$BOOKMARKS.bak") $(grep -c 'late.example' "$BOOKMARKS.bak.1")" '2 1'

# ---- bm-migrate, the standalone script ----

MIGRATE="${SBM_SH:-sh} $here/../bm-migrate"
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

old_file
$BM --migrate >/dev/null
eq 'bm --migrate and bm-migrate agree' "$(cat "$BOOKMARKS")" "$migrated"

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
for flag in --copy --open --plumb --add --edit --delete --list --migrate --tag; do
    $BM -h | grep -q -e "$flag" || missing="$missing $flag"
done
eq 'help mentions every flag' "$missing" ''

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
    "$(grep -c "^https://c.example${TAB}2${TAB}" "$BOOKMARKS.usage")" '1'
answers 'Alpha'; $BM -d >/dev/null
eq 'delete forgets the use count' "$(grep -c 'c.example' "$BOOKMARKS.usage")" '0'

# ---- search and --print ----

seed
eq 'search matches any field, ignoring case' \
    "$($BM -s 'ZED|sec' | cut -f1 | paste -sd ' ' -)" 'https://a.example https://b.example'
$BM -s nothinglikethis >/dev/null
eq 'search without a match exits 1' "$?" '1'
eq 'search honours the tag filter' "$($BM -t code -s example | wc -l | tr -d ' ')" '2'
answers 'Mid'
eq '--print writes the url to stdout' "$($BM -c --print)" 'https://a.example'
eq '--print leaves the clipboard alone' "$([ -e "$work/clipboard" ] || echo untouched)" 'untouched'

# ---- add: fetched titles, new tags ----

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

reset
: > "$SBM_TEST_CURLLOG"
answers '<default>' 'code'
PATH="$work/net:$PATH" SBM_FETCH=1 $BM -a https://fetch.example 2>/dev/null
eq 'add offers the fetched <title> as the description' \
    "$(cut -f2 "$BOOKMARKS")" "Fetched & decoded 'title'"

reset
: > "$SBM_TEST_CURLLOG"
answers 'Mine' 'code'
PATH="$work/net:$PATH" SBM_FETCH=1 $BM -a https://fetch.example 2>/dev/null
eq 'a typed description beats the fetched title' "$(cut -f2 "$BOOKMARKS")" 'Mine'

reset
: > "$SBM_TEST_CURLLOG"
answers 'Offline' 'code'
PATH="$work/net:$PATH" SBM_FETCH=0 $BM -a https://fetch.example 2>/dev/null
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

# ---- import ----

reset
printf '%s\n' "https://old.example${TAB}Kept${TAB}org" > "$BOOKMARKS"
eq 'import html reports its counts' \
    "$($BM --import "$here/fixtures/netscape.html")" 'imported 3, skipped 1 duplicates'
eq 'import html appends, keeps entities decoded and folders as tags' \
    "$(cat "$BOOKMARKS")" "$(printf '%s\n' \
        "https://old.example${TAB}Kept${TAB}org" \
        "https://top.example/${TAB}Top level${TAB}" \
        "https://git.example/?a=1&b=2${TAB}Git & friends${TAB}dev-tools" \
        "https://sh.example/posix${TAB}POSIX sh${TAB}dev-tools shell")"
eq 'import teaches the folder tags' "$(grep -c -e '^dev-tools | $' -e '^shell | $' "$USERTAGS")" '2'
eq 'importing twice adds nothing' \
    "$($BM --import "$here/fixtures/netscape.html")" 'imported 0, skipped 4 duplicates'
$BM --import "$work/nosuchfile" 2>/dev/null
eq 'import of a missing file fails' "$?" '1'

if command -v jq >/dev/null 2>&1; then
    reset
    eq 'import json reports its counts' \
        "$($BM --import "$here/fixtures/chromium.json")" 'imported 3, skipped 1 duplicates'
    eq 'import json skips the trash and non-web urls, tags by folder' \
        "$(cat "$BOOKMARKS")" "$(printf '%s\n' \
            "https://bar.example/${TAB}Bar site${TAB}" \
            "https://blog.example/feed${TAB}A blog${TAB}news-blogs" \
            "https://deep.example/${TAB}Deep${TAB}news-blogs tech")"
else
    printf 'skip import json: no jq\n'
fi
cp "$here/../usertags" "$USERTAGS"

# ---- check ----

reset
printf '%s\n' \
    "https://ok.example${TAB}Fine${TAB}" \
    "https://dead.example${TAB}Dead${TAB}" \
    "https://moved.example${TAB}Moved${TAB}" \
    "https://nohead.example${TAB}Refuses HEAD${TAB}" \
    "https://gone.example${TAB}No answer${TAB}" > "$BOOKMARKS"
out=$(PATH="$work/net:$PATH" $BM --check | sort)
rc=$?
eq 'check lists dead and moved links only' "$out" "$(printf '%s\n' \
    "000${TAB}https://gone.example" \
    "301${TAB}https://moved.example${TAB}https://new.example/" \
    "404${TAB}https://dead.example")"
PATH="$work/net:$PATH" $BM --check >/dev/null
eq 'check exits 1 when something is wrong' "$?" '1'
printf '%s\n' "https://ok.example${TAB}Fine${TAB}" > "$BOOKMARKS"
eq 'check is quiet about healthy links' "$(PATH="$work/net:$PATH" $BM --check; echo $?)" \
    "$(printf 'all links ok\n0')"

# ---- git ----

if command -v git >/dev/null 2>&1; then
    export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
    export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
    repo="$work/repo"
    git init -q "$repo"
    mkdir "$repo/nested"
    commits () { git -C "$repo" rev-list --count HEAD 2>/dev/null || echo 0; }

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

rm -f "$work/opened"
answers 'ctrl-t:' 'sec' 'enter:example'
fz </dev/null
eq 'browse: ctrl-t narrows to a tag' "$(cat "$work/opened")" 'https://a.example'

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

answers 'ctrl-a:' '' 'enter:Mid'
printf 'https://a.example\n\n' | fz 2>/dev/null
eq 'browse: a refused duplicate returns to the list' "$(cat "$work/opened")" 'https://a.example'

: > "$SBM_TEST_LOG"
answers 'Mid'
fz -c </dev/null
eq 'fzf: pickers hide the raw url column' "$(grep -c -e '--with-nth=2..' "$SBM_TEST_LOG")" '1'
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
answers 'copy' 'Zed'
dm
eq 'dmenu: no arguments asks for the action, then the bookmark' \
    "$(cat "$work/clipboard")" 'https://b.example'
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
answers 'copy' 'Zed'
( unset SBM_MENU WAYLAND_DISPLAY; PATH="$both:$PATH" DISPLAY=:0 $BM </dev/null )
eq 'a display means dmenu even when fzf exists' \
    "$(cut -d' ' -f1 "$SBM_TEST_LOG" | sort -u)" 'dmenu'

: > "$SBM_TEST_LOG"
answers 'copy' 'Zed'
( unset SBM_MENU DISPLAY; PATH="$both:$PATH" WAYLAND_DISPLAY=wayland-0 $BM </dev/null )
eq 'Wayland means dmenu too' "$(cut -d' ' -f1 "$SBM_TEST_LOG" | sort -u)" 'dmenu'

: > "$SBM_TEST_LOG"
answers 'enter:Zed'
( unset SBM_MENU DISPLAY WAYLAND_DISPLAY; PATH="$both:$PATH" $BM </dev/null )
eq 'no display falls back to fzf' "$(cut -d' ' -f1 "$SBM_TEST_LOG" | sort -u)" 'fzf'

unset SBM_TEST_LOG

# ---- defaults ----

(
    unset BOOKMARKS
    $BM -l
)
eq 'default bookmark file is created under XDG_DATA_HOME' \
    "$([ -f "$work/xdg/sbm/bookmarks" ] && echo yes)" 'yes'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
