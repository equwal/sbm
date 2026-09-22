/*
 * bm: bookmarks in a plain file, picked with dmenu (or fzf).
 *
 *     URL<tab>description<tab>tag tag tag
 *
 * bm owns that file and nothing else. Importing, link checking, the web page
 * and so on are separate bm-* filters; see README.
 */

#include "config.h"
#include "util.h"

#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <search.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

/* The first four fields of an fzf row feed the preview. No shell sees a URL:
 * fzf quotes what it puts in the place of {1}. */
#define PREVIEW "printf '%s\\n%s\\ntags: %s\\nused: %s\\n' {1} {2} {3} {4}"
#define KEYS "ctrl-y,ctrl-a,ctrl-d,ctrl-e,ctrl-s"
#define TAGHELP "TAB marks, ENTER confirms. No match: ENTER creates the typed tag, ESC finishes."

enum { MENU_DMENU, MENU_FZF, MENU_CUSTOM };
enum { NONE, HELP, COPY, PRINT, OPEN, EDIT, DELETE, LIST, MERGE, ADD };
enum { USED, RECENT, URL, DESC, TAG, NORDERS };

struct bookmark {
    char* url;
    char* desc;
    char* tags;
    long used; /* how often it was opened or copied */
    size_t line; /* where it is in the file */
};

struct args {
    char** v;
    size_t n;
};

static const char* orders[NORDERS] = {"used", "recent", "url", "desc", "tag"};

static char* bookmarks; /* file names */
static char* usertags;
static char* engines;
static char* usage;
static char* lockdir; /* the write lock: a directory beside the file */
static char* lockpid; /* the pid of its holder, a file in it */
static volatile sig_atomic_t locked;
static int menu;
static char* tagfilter; /* "" means every bookmark */
static int order;

static struct buf filebuf; /* the bookmark file, cut into fields */
static struct bookmark* all; /* every bookmark in it */
static size_t nall;
static struct bookmark** view; /* the ones to list, in order */
static size_t nview;

static void usagetext(FILE* f) {
    fputs("usage: bm [-t tag] [-S order] [action]\n"
          "Without an action: browse. Pick a bookmark, then what to do with it. Text\n"
          "that is no bookmark is opened as an address, or searched for on the web.\n"
          "  -o, --open        open a bookmark, an address or a web search\n"
          "                    (-p, --plumb is the same)\n"
          "  -c, --copy        copy a bookmark's URL to the clipboard\n"
          "      --print       print a bookmark's URL\n"
          "  -a, --add [url]   add a bookmark; the url defaults to the selection\n"
          "  -e, --edit        open the bookmark file in $EDITOR at a bookmark\n"
          "  -d, --delete      delete a bookmark\n"
          "  -l, --list        print the bookmarks\n"
          "  -m, --merge       add the bookmarks on stdin, skipping the known ones\n"
          "  -t, --tag <tag>   only consider bookmarks with this tag\n"
          "  -S, --sort <o>    used (default), recent, url, desc or tag\n"
          "  -h, --help\n",
        f);
}

/* ---- strings ---- */

static const char* envor(const char* name, const char* fallback) {
    const char* s = getenv(name);

    return s && *s ? s : fallback;
}

static int lower(int c) { return c >= 'A' && c <= 'Z' ? c + ('a' - 'A') : c; }

/* lowercmp: strcmp without regard to the case of ASCII letters. */
static int lowercmp(const char* a, const char* b) {
    int x, y;

    for (;; a++, b++) {
        x = lower((unsigned char) *a);
        y = lower((unsigned char) *b);
        if (x != y)
            return x < y ? -1 : 1;
        if (!x)
            return 0;
    }
}

/* cmpkey: for tsearch, whose keys are the strings themselves. */
static int cmpkey(const void* a, const void* b) { return strcmp(a, b); }

static int cmpstr(const void* a, const void* b) {
    return strcmp(*(char* const*) a, *(char* const*) b);
}

static void chomp(char* s) {
    size_t n = strlen(s);

    while (n > 0 && s[n - 1] == '\n')
        s[--n] = '\0';
}

/* nthline: a copy of line n of s, counted from 0; "" when s is shorter. */
static char* nthline(const char* s, size_t n) {
    for (; n > 0; n--) {
        if (!(s = strchr(s, '\n')))
            return xstrdup("");
        s++;
    }
    return xstrndup(s, strcspn(s, "\n"));
}

static char* firstfield(const char* s) { return xstrndup(s, strcspn(s, "\t")); }

/* isurl: whether the first field of line is url. */
static int isurl(const char* line, const char* url) {
    size_t n = strcspn(line, "\t");

    return strlen(url) == n && !memcmp(line, url, n);
}

/* hastag: whether tag is one of the words of tags. */
static int hastag(const char* tags, const char* tag) {
    size_t n, len = strlen(tag);

    for (;;) {
        tags += strspn(tags, " ");
        if (!*tags)
            return 0;
        n = strcspn(tags, " ");
        if (n == len && !memcmp(tags, tag, n))
            return 1;
        tags += n;
    }
}

/*
 * norm: two URLs are the same bookmark when they differ only in scheme, a
 * leading www., trailing slashes or the case of the host.
 */
static char* norm(const char* url) {
    const char* p = url;
    char *s, *slash;
    size_t i, n;

    if (isalpha((unsigned char) *p)) {
        while (isalnum((unsigned char) *p) || *p == '+' || *p == '.' || *p == '-')
            p++;
        if (!strncmp(p, "://", 3))
            url = p + 3;
    }
    n = strcspn(url, "/");
    if (n >= 4 && lower(url[0]) == 'w' && lower(url[1]) == 'w' && lower(url[2]) == 'w'
        && url[3] == '.') {
        url += 4;
        n -= 4;
    }
    s = xstrdup(url);
    for (i = 0; i < n; i++)
        s[i] = (char) lower((unsigned char) s[i]);
    slash = s + strlen(s);
    while (slash > s + n && slash[-1] == '/')
        *--slash = '\0';
    return s;
}

/* urlencode: for a query string, byte by byte. */
static void urlencode(struct buf* b, const char* s) {
    for (; *s; s++) {
        if (isalnum((unsigned char) *s) || strchr("._~-", *s))
            bufadd(b, s, 1);
        else if (*s == ' ')
            bufputs(b, "+");
        else
            bufprintf(b, "%%%02X", (unsigned char) *s);
    }
}

/*
 * column: s, filled up with spaces to width characters. With cut, a longer s
 * is cut short and ends in "..". Characters are counted, not bytes, so that
 * UTF-8 text lines up.
 */
static void column(struct buf* b, const char* s, size_t width, int cut) {
    size_t chars = 0, i;

    for (i = 0; s[i]; i++)
        chars += (s[i] & 0xC0) != 0x80;
    if (cut && chars > width) {
        chars = 0;
        for (i = 0; s[i]; i++)
            if ((s[i] & 0xC0) != 0x80 && chars++ == width - 2)
                break;
        bufadd(b, s, i);
        bufputs(b, "..");
        chars = width;
    } else {
        bufputs(b, s);
    }
    for (; chars < width; chars++)
        bufputs(b, " ");
}

/* ---- external programs: menu, clipboard, opener ---- */

static void arg(struct args* a, const char* s) {
    a->v = xrealloc(a->v, (a->n + 2) * sizeof(*a->v));
    a->v[a->n++] = xstrdup(s);
    a->v[a->n] = NULL;
}

/* argwords: a command kept in a variable may carry arguments, so it is split. */
static void argwords(struct args* a, const char* s) {
    char** w;
    size_t i;

    if (!s)
        return;
    w = words(s);
    for (i = 0; w[i]; i++)
        arg(a, w[i]);
    freewords(w);
}

static int runargs(struct args* a, const char* in, struct buf* out, int flags) {
    int rc = run(a->v ? a->v : (char*[]) {NULL}, in, out, flags);

    freewords(a->v);
    a->v = NULL;
    a->n = 0;
    return rc;
}

/* menuout: what the menu program printed, without the final newlines. */
static char* menuout(struct args* a, const char* in) {
    struct buf out = {0};

    runargs(a, in, &out, 0);
    chomp(out.s);
    return out.s;
}

/*
 * dmenu whenever there is a display to draw it on. fzf stands in on a bare
 * terminal, or when dmenu is not installed.
 */
static void pickmenu(void) {
    const char* name = envor("SBM_MENU", NULL);
    const char* display[] = {"dmenu", "fzf"};
    const char* terminal[] = {"fzf", "dmenu"};
    const char** try
        = envor("DISPLAY", NULL) || envor("WAYLAND_DISPLAY", NULL) ? display : terminal;
    size_t i;

    for (i = 0; !name && i < 2; i++)
        if (have(try[i]))
            name = try[i];
    if (!name)
        die("no menu program found: install dmenu or fzf, or set $SBM_MENU");
    if (!strcmp(name, "fzf"))
        menu = MENU_FZF;
    else if (!strcmp(name, "dmenu"))
        menu = MENU_DMENU;
    else
        menu = MENU_CUSTOM;
}

static void fzfargs(struct args* a) {
    const char* base[] = {FZF, NULL};
    size_t i;

    for (i = 0; base[i]; i++)
        arg(a, base[i]);
    argwords(a, getenv("SBM_FZF_OPTS"));
}

/* previewargs: for rows that come from rowlines with its display column. */
static void previewargs(struct args* a) {
    arg(a, "--delimiter=\t");
    arg(a, "--with-nth=5..");
    arg(a, "--preview-window=down:5:wrap");
    arg(a, "--preview=" PREVIEW);
}

static void dmenuargs(struct args* a, const char* prompt) {
    arg(a, "dmenu");
    arg(a, "-i");
    arg(a, "-l");
    arg(a, envor("DMENULINES", DMENULINES));
    arg(a, "-p");
    arg(a, prompt);
}

static void customargs(struct args* a, const char* kind, const char* prompt) {
    argwords(a, getenv("SBM_MENU"));
    arg(a, kind);
    arg(a, prompt);
}

/*
 * pick: the chosen line of choices, or else the text that was typed; "" when
 * the menu was closed. dmenu gives the typed text by itself, fzf has to be
 * asked for it.
 */
static char* pick(const char* prompt, const char* choices, int preview) {
    struct args a = {0};
    struct buf opt = {0};
    char *out, *line;

    switch (menu) {
    case MENU_FZF:
        fzfargs(&a);
        arg(&a, "--print-query");
        bufprintf(&opt, "--prompt=%s ", prompt);
        arg(&a, opt.s);
        free(opt.s);
        if (preview)
            previewargs(&a);
        out = menuout(&a, choices);
        line = nthline(out, 1);
        if (!*line) {
            free(line);
            line = nthline(out, 0);
        }
        break;
    case MENU_DMENU:
        dmenuargs(&a, prompt);
        out = menuout(&a, choices);
        line = nthline(out, 0);
        break;
    default:
        customargs(&a, "pick", prompt);
        out = menuout(&a, choices);
        line = nthline(out, 0);
        break;
    }
    free(out);
    return line;
}

/* pickmulti: like pick, for any number of lines. */
static char* pickmulti(const char* prompt, const char* choices) {
    struct args a = {0};
    struct buf in = {0}, got = {0}, opt = {0};
    char *out, *one, *rest;
    int more;

    bufadd(&got, "", 0);
    switch (menu) {
    case MENU_FZF:
        bufprintf(&in, "%s\n", choices);
        for (;;) {
            fzfargs(&a);
            arg(&a, "--multi");
            arg(&a, "--print-query");
            opt.len = 0;
            bufprintf(&opt, "--prompt=%s ", prompt);
            arg(&a, opt.s);
            arg(&a, "--header=" TAGHELP);
            out = menuout(&a, in.s);
            one = nthline(out, 0);
            rest = strchr(out, '\n');
            /* Marked lines end it, and so does nothing at all. A typed tag
             * is kept, and the menu opens again for more. */
            more = !(rest && rest[1]) && *one;
            bufprintf(&got, "%s\n", more ? one : rest ? rest + 1 : "");
            free(out);
            free(one);
            if (!more)
                break;
        }
        free(opt.s);
        break;
    case MENU_DMENU:
        bufprintf(&in, "done | (choose when done)\n%s\n", choices);
        for (;;) {
            dmenuargs(&a, prompt);
            out = menuout(&a, in.s);
            one = nthline(out, 0);
            free(out);
            /* An empty answer means the menu was closed. */
            if (!*one || (!strncmp(one, "done", 4) && (!one[4] || one[4] == ' '))) {
                free(one);
                break;
            }
            bufprintf(&got, "%s\n", one);
            free(one);
        }
        break;
    default:
        bufprintf(&in, "%s\n", choices);
        customargs(&a, "multi", prompt);
        out = menuout(&a, in.s);
        bufprintf(&got, "%s\n", out);
        free(out);
        break;
    }
    free(in.s);
    return got.s;
}

/*
 * readline: one line of stdin, read byte by byte so that nothing beyond it is
 * taken away from the programs that are run later.
 */
static char* readline(void) {
    struct buf b = {0};
    char c;

    bufadd(&b, "", 0);
    while (read(0, &c, 1) == 1 && c != '\n')
        bufadd(&b, &c, 1);
    return b.s;
}

/* ask: free text. def, unless "", is what is offered. */
static char* ask(const char* prompt, const char* def) {
    struct args a = {0};
    struct buf in = {0}, opt = {0};
    char *out, *line;

    if (menu == MENU_FZF) {
        if (*def)
            fprintf(stderr, "%s [%s]: ", prompt, def);
        else
            fprintf(stderr, "%s: ", prompt);
        line = readline();
        if (!*line) {
            free(line);
            line = xstrdup(def);
        }
        return line;
    }
    bufadd(&in, "", 0);
    if (*def)
        bufprintf(&in, "%s\n", def);
    if (menu == MENU_DMENU) {
        bufprintf(&opt, "%s:", prompt);
        arg(&a, "dmenu");
        arg(&a, "-p");
        arg(&a, opt.s);
        free(opt.s);
    } else {
        customargs(&a, "ask", prompt);
    }
    out = menuout(&a, in.s);
    line = nthline(out, 0);
    free(out);
    free(in.s);
    return line;
}

static int clipout(const char* text) {
    struct args a = {0};

    if (envor("SBM_COPY", NULL)) {
        argwords(&a, getenv("SBM_COPY"));
    } else if (envor("WAYLAND_DISPLAY", NULL) && have("wl-copy")) {
        arg(&a, "wl-copy");
    } else if (have("xclip")) {
        arg(&a, "xclip");
        arg(&a, "-i");
        arg(&a, "-selection");
        arg(&a, "clipboard");
    } else if (have("xsel")) {
        arg(&a, "xsel");
        arg(&a, "-ib");
    } else {
        die("no clipboard program found: set $SBM_COPY");
    }
    return runargs(&a, text, NULL, 0);
}

/* paste: run one paste command and keep what it printed, as lines. */
static void paste(
    struct buf* out, const char* prog, const char* opt1, const char* opt2, const char* opt3) {
    struct args a = {0};

    arg(&a, prog);
    if (opt1)
        arg(&a, opt1);
    if (opt2)
        arg(&a, opt2);
    if (opt3)
        arg(&a, opt3);
    runargs(&a, NULL, out, RUN_QUIET);
    bufputs(out, "\n");
}

/*
 * clipin: the first URL in the primary selection, or else in the clipboard;
 * "" without one. Never fatal: then there is just no URL to suggest.
 */
static char* clipin(void) {
    struct args a = {0};
    struct buf out = {0};
    char *p, *line, *url;

    bufadd(&out, "", 0);
    if (envor("SBM_PASTE", NULL)) {
        argwords(&a, getenv("SBM_PASTE"));
        runargs(&a, NULL, &out, RUN_QUIET);
    } else if (envor("WAYLAND_DISPLAY", NULL) && have("wl-paste")) {
        paste(&out, "wl-paste", "-n", "-p", NULL);
        paste(&out, "wl-paste", "-n", NULL, NULL);
    } else if (have("xclip")) {
        paste(&out, "xclip", "-o", NULL, NULL);
        paste(&out, "xclip", "-o", "-selection", "clipboard");
    } else if (have("xsel")) {
        paste(&out, "xsel", "-op", NULL, NULL);
        paste(&out, "xsel", "-ob", NULL, NULL);
    }
    for (p = out.s; (line = nextline(&p));)
        if (strstr(line, "://"))
            break;
    url = xstrdup(line ? line : "");
    free(out.s);
    return url;
}

static int opener(const char* url) {
    struct args a = {0};

    if (envor("SBM_OPEN", NULL))
        argwords(&a, getenv("SBM_OPEN"));
    else if (have("xdg-open"))
        arg(&a, "xdg-open");
    else
        die("no opener found: set $SBM_OPEN");
    arg(&a, url);
    return runargs(&a, NULL, NULL, 0);
}

/*
 * changed: the file was written. bm-commit, where installed, keeps its
 * history in git. bm-sync, where installed, tells your other machines; it
 * runs in the background, so that a slow network never holds the menu up.
 */
static void changed(const char* what, const char* url) {
    struct args a = {0};
    struct buf msg = {0};

    if (have("bm-commit")) {
        bufprintf(&msg, "bm: %s%s%s", what, url ? " " : "", url ? url : "");
        arg(&a, "bm-commit");
        arg(&a, msg.s);
        free(msg.s);
        runargs(&a, NULL, NULL, 0);
    }
    if (have("bm-sync"))
        detach((char*[]) {"bm-sync", "-q", NULL});
}

/* ---- the bookmark file ---- */

/* load: read the bookmark file, and the use counts that are kept beside it. */
static void load(void) {
    struct buf counts = {0};
    char *p, *line, *f[3];
    size_t lineno = 0, i;

    filebuf.len = 0;
    nall = 0;
    if (readpath(bookmarks, &filebuf) < 0)
        die("cannot read %s: %s", bookmarks, strerror(errno));
    for (p = filebuf.s; (line = nextline(&p));) {
        lineno++;
        if (!*line || *line == '#')
            continue;
        fields(line, f, 3);
        all = xrealloc(all, (nall + 1) * sizeof(*all));
        all[nall].url = f[0];
        all[nall].desc = f[1];
        all[nall].tags = f[2];
        all[nall].used = 0;
        all[nall].line = lineno;
        nall++;
    }
    readpath(usage, &counts); /* there may be none yet */
    for (p = counts.s; (line = nextline(&p));) {
        fields(line, f, 3);
        for (i = 0; i < nall; i++)
            if (!strcmp(all[i].url, f[0]))
                all[i].used = strtol(f[1], NULL, 10);
    }
    free(counts.s);
}

static struct bookmark* find(const char* url) {
    size_t i;

    for (i = 0; i < nall; i++)
        if (!strcmp(all[i].url, url))
            return &all[i];
    return NULL;
}

/* finddup: the bookmark that is the same page as url, if any. */
static struct bookmark* finddup(const char* url) {
    char *want = norm(url), *got;
    struct bookmark* dup = NULL;
    size_t i;

    for (i = 0; i < nall && !dup; i++) {
        got = norm(all[i].url);
        if (!strcmp(got, want))
            dup = &all[i];
        free(got);
    }
    free(want);
    return dup;
}

/* qsort is not stable, so the place in the file settles what is left. */
static int cmpbookmark(const void* pa, const void* pb) {
    const struct bookmark *a = *(struct bookmark* const*) pa, *b = *(struct bookmark* const*) pb;
    int c = 0;

    switch (order) {
    case USED:
        c = (a->used < b->used) - (a->used > b->used);
        break;
    case RECENT:
        c = (a->line < b->line) - (a->line > b->line);
        break;
    case DESC:
        c = lowercmp(a->desc, b->desc);
        break;
    case TAG:
        c = lowercmp(a->tags, b->tags);
        break;
    }
    if (!c)
        c = lowercmp(a->url, b->url);
    if (!c)
        c = (a->line > b->line) - (a->line < b->line);
    return c;
}

/* rows: load the bookmarks; view gets the ones with the tag, in order. */
static void rows(void) {
    size_t i;

    load();
    view = xrealloc(view, nall * sizeof(*view));
    nview = 0;
    for (i = 0; i < nall; i++)
        if (!*tagfilter || hastag(all[i].tags, tagfilter))
            view[nview++] = &all[i];
    qsort(view, nview, sizeof(*view), cmpbookmark);
}

/*
 * rowlines: the view as lines. For fzf two fields are added: the use count,
 * and a display column that is all fzf lists.
 */
static void rowlines(struct buf* b, int fzf) {
    size_t i;

    bufadd(b, "", 0);
    for (i = 0; i < nview; i++) {
        bufprintf(b, "%s\t%s\t%s", view[i]->url, view[i]->desc, view[i]->tags);
        if (fzf) {
            bufprintf(b, "\t%ld\t", view[i]->used);
            column(b, view[i]->desc, DESCWIDTH, 1);
            bufputs(b, "  ");
            column(b, view[i]->tags, TAGWIDTH, 0);
            bufprintf(b, "  %s", view[i]->url);
        }
        bufputs(b, "\n");
    }
}

/* choose: a bookmark's URL, or whatever else the user typed. */
static char* choose(const char* prompt) {
    struct buf in = {0};
    char *line, *url;

    rowlines(&in, menu == MENU_FZF);
    line = pick(prompt, in.s, 1);
    url = firstfield(line);
    free(line);
    free(in.s);
    return url;
}

/* chooseurl: like choose, but only a bookmark will do. */
static char* chooseurl(const char* prompt) {
    char* url;

    rows();
    if (!nview && *tagfilter)
        die("no bookmarks tagged '%s'", tagfilter);
    if (!nview)
        die("no bookmarks yet; add one with: bm --add");
    url = choose(prompt);
    if (!*url)
        exit(1);
    if (!find(url))
        die("not a bookmark: %s", url);
    return url;
}

/*
 * bump: count a use, for the "used" order. The counts live beside the
 * bookmark file, which stays a plain list: url, count, time of last use.
 */
static void bump(const char* url) {
    struct buf old = {0}, new = {0};
    char *p, *line, *f[3];
    long long now = (long long) time(NULL);
    int seen = 0;

    readpath(usage, &old);
    bufadd(&new, "", 0);
    for (p = old.s; (line = nextline(&p));) {
        if (isurl(line, url)) {
            fields(line, f, 3);
            bufprintf(&new, "%s\t%ld\t%lld\n", url, strtol(f[1], NULL, 10) + 1, now);
            seen = 1;
        } else {
            bufprintf(&new, "%s\n", line);
        }
    }
    if (!seen)
        bufprintf(&new, "%s\t1\t%lld\n", url, now);
    writepath(usage, O_CREAT | O_TRUNC, new.s, new.len);
    free(old.s);
    free(new.s);
}

/* knowntag: whether the tag file text has a line for name. */
static int knowntag(const char* text, const char* name) {
    size_t len = strlen(name);

    while (*text) {
        if (strcspn(text, " |\n") == len && !memcmp(text, name, len))
            return 1;
        text += strcspn(text, "\n");
        text += *text == '\n';
    }
    return 0;
}

/* learntags: the names that the tag file lacks are appended to it. */
static void learntags(char** names, size_t n) {
    struct buf known = {0}, line = {0};
    size_t i;

    readpath(usertags, &known);
    for (i = 0; i < n; i++) {
        if (knowntag(known.s, names[i]))
            continue;
        line.len = 0;
        bufprintf(&line, "%s | \n", names[i]);
        if (writepath(usertags, O_CREAT | O_APPEND, line.s, line.len) < 0)
            warn("cannot write %s: %s", usertags, strerror(errno));
        bufputs(&known, line.s);
    }
    free(known.s);
    free(line.s);
}

/*
 * tagnames: the tag names in lines of "name", "name | description" or
 * "name name", sorted, each one once. split says which: with it every word of
 * a line is a name, without it only the first one.
 */
static char** tagnames(const char* lines, int split, size_t* count) {
    char **names = NULL, *name;
    size_t n = 0, i, len, uniq = 0;

    while (*lines) {
        lines += strspn(lines, split ? " \n" : "\n");
        len = strcspn(lines, " |\n");
        if (len > 0) {
            names = xrealloc(names, (n + 1) * sizeof(*names));
            names[n++] = xstrndup(lines, len);
        }
        lines += len;
        if (!split || *lines == '|')
            lines += strcspn(lines, "\n");
    }
    if (n > 0)
        qsort(names, n, sizeof(*names), cmpstr);
    for (i = 0; i < n; i++) {
        name = names[i];
        if (uniq > 0 && !strcmp(names[uniq - 1], name))
            free(name);
        else
            names[uniq++] = name;
    }
    *count = uniq;
    return names;
}

static void freenames(char** names, size_t n) {
    while (n > 0)
        free(names[--n]);
    free(names);
}

/* ---- the write lock ---- */

/*
 * unlock: give the lock back. Only calls that a signal handler may make: the
 * handler for SIGINT and its kin calls it too.
 */
static void unlock(void) {
    if (!locked)
        return;
    locked = 0;
    unlink(lockpid);
    rmdir(lockdir);
}

/*
 * onsignal: end as "exit 1" would, with the lock given back. While a program
 * runs, run() does that once the program is done; killing bm from under the
 * editor would leave the editor without a terminal.
 */
static void onsignal(int sig) {
    (void) sig;
    if (busy) {
        stopped = 1;
        return;
    }
    unlock();
    _exit(1);
}

/*
 * takeover: whether the lock was left by a process that is gone. Then it is
 * removed, unless another process got it in the meantime.
 */
static int takeover(void) {
    struct buf pid = {0}, again = {0};
    int gone;

    readpath(lockpid, &pid);
    chomp(pid.s);
    gone = *pid.s && kill((pid_t) strtol(pid.s, NULL, 10), 0) < 0;
    if (gone) {
        readpath(lockpid, &again);
        chomp(again.s);
        if (!strcmp(pid.s, again.s)) {
            unlink(lockpid);
            rmdir(lockdir);
        }
    }
    free(pid.s);
    free(again.s);
    return gone;
}

/*
 * lock: take the write lock of the bookmark file, a directory beside it. bm
 * holds it while it changes the file, and bm-sync while it reads or writes
 * the file, so that neither writes over a change of the other. After
 * $SBM_LOCK_WAIT seconds (default LOCKWAIT) bm stops.
 */
static void lock(void) {
    struct buf pid = {0};
    struct sigaction sa;
    long wait = strtol(envor("SBM_LOCK_WAIT", LOCKWAIT), NULL, 10), waited = 0;
    static int prepared;

    if (!prepared) {
        prepared = 1;
        atexit(unlock);
        memset(&sa, 0, sizeof(sa));
        sa.sa_handler = onsignal;
        sigemptyset(&sa.sa_mask);
        sigaction(SIGHUP, &sa, NULL);
        sigaction(SIGINT, &sa, NULL);
        sigaction(SIGTERM, &sa, NULL);
    }
    while (mkdir(lockdir, 0777) < 0) {
        /* A directory that refuses the lock (read-only) still lets the
         * file be rewritten; bm-sync cannot keep its state there either. */
        if (errno != EEXIST)
            return;
        if (takeover())
            continue;
        if (waited >= wait)
            die("%s is in use (bm -e or bm-sync). If neither runs, remove %s", bookmarks, lockdir);
        sleep(1);
        waited++;
    }
    bufprintf(&pid, "%ld\n", (long) getpid());
    writepath(lockpid, O_CREAT | O_TRUNC, pid.s, pid.len);
    free(pid.s);
    locked = 1;
}

/* ---- actions ---- */

static int copyurl(const char* url) {
    bump(url);
    return clipout(url);
}

static int openurl(const char* url) {
    bump(url);
    return opener(url);
}

/*
 * editurl: the editor reads the file when it starts and writes it when you
 * save, so bm holds the lock until the editor ends. bm-sync then waits, and
 * syncs the edit after it.
 */
static void editurl(const char* url) {
    struct args a = {0};
    struct buf text = {0}, opt = {0};
    char *p, *line;
    size_t lineno = 0, found = 1;

    lock();
    readpath(bookmarks, &text);
    for (p = text.s; (line = nextline(&p));) {
        lineno++;
        if (isurl(line, url)) {
            found = lineno;
            break;
        }
    }
    free(text.s);
    argwords(&a, envor("VISUAL", envor("EDITOR", EDITOR)));
    bufprintf(&opt, "+%lu", (unsigned long) found);
    arg(&a, opt.s);
    arg(&a, bookmarks);
    free(opt.s);
    runargs(&a, NULL, NULL, 0);
    unlock();
    changed("edit", NULL);
}

static void deleteurl(const char* url) {
    const char* files[2];
    struct buf old = {0}, new = {0};
    char *p, *line;
    size_t i;

    files[0] = bookmarks;
    files[1] = usage;
    lock();
    for (i = 0; i < 2; i++) {
        old.len = new.len = 0;
        if (access(files[i], F_OK) < 0)
            continue;
        if (readpath(files[i], &old) < 0)
            die("cannot read %s: %s", files[i], strerror(errno));
        bufadd(&new, "", 0);
        for (p = old.s; (line = nextline(&p));)
            if (!isurl(line, url))
                bufprintf(&new, "%s\n", line);
        if (writepath(files[i], O_TRUNC, new.s, new.len) < 0)
            die("could not rewrite %s: %s", files[i], strerror(errno));
    }
    unlock();
    free(old.s);
    free(new.s);
    changed("delete", url);
}

/* engineof: the URL of the search engine with this keyword, or NULL. The
 * engines file holds "keyword | url with %s" lines. */
static char* engineof(const char* key) {
    struct buf text = {0};
    char *p, *line, *bar, *end, *url = NULL;

    readpath(engines, &text);
    for (p = text.s; !url && (line = nextline(&p));) {
        if (!(bar = strchr(line, '|')))
            continue;
        for (end = bar; end > line && end[-1] == ' ';)
            end--;
        if (strlen(key) != (size_t) (end - line) || memcmp(line, key, strlen(key)))
            continue;
        bar += 1 + strspn(bar + 1, " ");
        for (end = bar + strcspn(bar, "|"); end > bar && end[-1] == ' ';)
            end--;
        url = xstrndup(bar, (size_t) (end - bar));
    }
    free(text.s);
    if (url && !*url) {
        free(url);
        url = NULL;
    }
    return url;
}

/*
 * go: open text that is not a bookmark. One word with "://" or a dot in it is
 * an address. Anything else is a web search: by the engine whose keyword is
 * the first word, or else by the default engine.
 */
static int go(const char* text) {
    struct buf url = {0};
    const char *query = text, *space = strchr(text, ' '), *mark;
    char *engine = NULL, *key;
    int rc;

    if (!space && strstr(text, "://"))
        return opener(text);
    if (!space && strchr(text, '.')) {
        bufprintf(&url, "https://%s", text);
    } else {
        if (space && space > text) {
            key = xstrndup(text, (size_t) (space - text));
            if ((engine = engineof(key)))
                query = space + 1;
            free(key);
        }
        if (!engine)
            engine = xstrdup(envor("SBM_SEARCH", SEARCH));
        if ((mark = strstr(engine, "%s"))) {
            bufadd(&url, engine, (size_t) (mark - engine));
            urlencode(&url, query);
            bufputs(&url, mark + 2);
        } else {
            bufputs(&url, engine);
        }
        free(engine);
    }
    rc = opener(url.s);
    free(url.s);
    return rc;
}

static int plumb(void) {
    char* url;
    int rc;

    rows();
    url = choose("open:");
    if (!*url)
        rc = 1;
    else if (find(url))
        rc = openurl(url);
    else
        rc = go(url);
    free(url);
    return rc;
}

/* appendrows: add finished lines to the end of the bookmark file. */
static int appendrows(const struct buf* b) {
    if (writepath(bookmarks, O_CREAT | O_APPEND, b->s, b->len) < 0) {
        warn("cannot write %s: %s", bookmarks, strerror(errno));
        return -1;
    }
    return 0;
}

/* add: returns the exit status; 3 means "already bookmarked". */
static int add(const char* given) {
    struct buf title = {0}, row = {0}, choices = {0};
    struct bookmark* dup;
    char *url, *def, *desc, *picked, **names, *p, *q;
    size_t n, i;
    int rc;

    if (given && *given) {
        url = xstrdup(given);
    } else {
        def = clipin();
        url = ask("url", def);
        free(def);
    }
    for (p = q = url; *p; p++)
        if (!isspace((unsigned char) *p))
            *q++ = *p;
    *q = '\0';
    if (!*url) {
        free(url);
        return 1;
    }

    load();
    if ((dup = finddup(url))) {
        fprintf(
            stderr, "%s: already bookmarked:\n%s\t%s\t%s\n", argv0, dup->url, dup->desc, dup->tags);
        free(url);
        return 3;
    }

    /* bm-title, where installed, fetches the page's title. */
    bufadd(&title, "", 0);
    if (have("bm-title")) {
        struct args a = {0};

        arg(&a, "bm-title");
        arg(&a, url);
        runargs(&a, NULL, &title, 0);
        chomp(title.s);
    }
    desc = ask("description", title.s);
    for (p = desc; *p; p++)
        if (*p == '\t')
            *p = ' ';

    if (writepath(usertags, O_CREAT | O_APPEND, "", 0) < 0)
        warn("cannot create %s: %s", usertags, strerror(errno));
    readpath(usertags, &choices);
    chomp(choices.s);
    picked = pickmulti("tags:", choices.s);
    names = tagnames(picked, 0, &n);
    learntags(names, n);

    bufprintf(&row, "%s\t%s\t", url, desc);
    for (i = 0; i < n; i++)
        bufprintf(&row, "%s%s", i ? " " : "", names[i]);
    bufputs(&row, "\n");
    lock();
    rc = appendrows(&row) < 0;
    unlock();
    changed("add", url);

    freenames(names, n);
    free(picked);
    free(choices.s);
    free(row.s);
    free(title.s);
    free(desc);
    free(url);
    return rc;
}

/*
 * merge: bookmark lines on stdin (a bare URL per line will do); the ones not
 * known yet are appended. This is how the output of bm-import gets in.
 */
static int merge(void) {
    struct buf in = {0}, new = {0}, tags = {0};
    char *p, *line, *f[3], *key, **names;
    void *seen = NULL, **node;
    size_t i, n, added = 0, skipped = 0;
    int rc;

    lock();
    load();
    for (i = 0; i < nall; i++) {
        key = norm(all[i].url);
        node = tsearch(key, &seen, cmpkey);
        if (!node)
            die("out of memory");
        if (*(char**) node != key)
            free(key);
    }
    if (readfd(0, &in) < 0)
        die("cannot read stdin: %s", strerror(errno));
    bufadd(&new, "", 0);
    bufadd(&tags, "", 0);
    for (p = in.s; (line = nextline(&p));) {
        if (!*line || *line == '#')
            continue;
        fields(line, f, 3);
        key = norm(f[0]);
        node = tsearch(key, &seen, cmpkey);
        if (!node)
            die("out of memory");
        if (*(char**) node != key) {
            free(key);
            skipped++;
            continue;
        }
        bufprintf(&new, "%s\t%s\t%s\n", f[0], f[1], f[2]);
        bufprintf(&tags, "%s\n", f[2]);
        added++;
    }
    printf("added %lu, skipped %lu duplicates\n", (unsigned long) added, (unsigned long) skipped);
    names = tagnames(tags.s, 1, &n);
    learntags(names, n);
    rc = appendrows(&new) < 0;
    unlock();
    changed("merge", NULL);

    freenames(names, n);
    while (seen) {
        key = *(char**) seen;
        tdelete(key, &seen, cmpkey);
        free(key);
    }
    free(in.s);
    free(new.s);
    free(tags.s);
    return rc;
}

/*
 * addinside: add from within the browser. A failed add must not end the
 * session; and when add refuses a duplicate the user has to get to see that
 * before the list comes back.
 */
static void addinside(void) {
    if (add(NULL) == 3)
        free(ask("already bookmarked; press ENTER", ""));
}

/*
 * browsefzf: fzf can bind keys, so one list does everything. Opening and
 * copying leave it, the other keys come back to it.
 */
static int browsefzf(void) {
    struct args a = {0};
    struct buf in = {0}, opt = {0};
    char *out, *typed, *key, *row, *url, *answer;
    int rc = -1;

    while (rc < 0) {
        rows();
        in.len = opt.len = 0;
        rowlines(&in, 1);
        fzfargs(&a);
        arg(&a, "--print-query");
        arg(&a, "--expect=" KEYS);
        bufprintf(&opt, "--header=ENTER open  ^Y copy  ^A add  ^D delete  ^E edit  ^S sort [%s]",
            orders[order]);
        arg(&a, opt.s);
        arg(&a, "--prompt=bookmark: ");
        previewargs(&a);
        out = menuout(&a, in.s);
        typed = nthline(out, 0);
        key = nthline(out, 1);
        row = nthline(out, 2);
        url = firstfield(row);

        if (!*out) {
            rc = 1;
        } else if (!strcmp(key, "ctrl-a")) {
            addinside();
        } else if (!strcmp(key, "ctrl-s")) {
            order = (order + 1) % NORDERS;
        } else if (!*url) {
            if (!*key && !*typed)
                rc = 1;
            else if (!*key) {
                go(typed);
                rc = 0;
            }
        } else if (!strcmp(key, "ctrl-y")) {
            copyurl(url);
            rc = 0;
        } else if (!strcmp(key, "ctrl-e")) {
            editurl(url);
        } else if (!strcmp(key, "ctrl-d")) {
            opt.len = 0;
            bufprintf(&opt, "delete %s? (y/N)", url);
            answer = ask(opt.s, "");
            if (!strcmp(answer, "y") || !strcmp(answer, "Y") || !strcmp(answer, "yes"))
                deleteurl(url);
            free(answer);
        } else {
            openurl(url);
            rc = 0;
        }
        free(out);
        free(typed);
        free(key);
        free(row);
        free(url);
    }
    free(in.s);
    free(opt.s);
    return rc;
}

/*
 * browsemenu: dmenu can neither bind keys nor preview, so a second menu does
 * both: it shows the bookmark in full and asks what to do with it. Closing it
 * goes back to the list; closing the list leaves.
 */
static int browsemenu(void) {
    struct buf in = {0};
    struct bookmark* b;
    char *chosen, *url, *action;
    int rc = -1;

    while (rc < 0) {
        rows();
        in.len = 0;
        bufputs(&in, "[add]\n");
        rowlines(&in, 0);
        chosen = pick("bookmark:", in.s, 0);
        url = firstfield(chosen);
        if (!*chosen) {
            rc = 1;
        } else if (!strcmp(chosen, "[add]")) {
            addinside();
        } else if (!(b = find(url))) {
            go(chosen);
            rc = 0;
        } else {
            in.len = 0;
            bufprintf(&in, "open\ncopy\nedit\ndelete\n  %s\n  %s\n  tags: %s\n  used: %ld\n",
                b->url, b->desc, b->tags, b->used);
            action = pick("do:", in.s, 0);
            if (!strcmp(action, "open")) {
                openurl(url);
                rc = 0;
            } else if (!strcmp(action, "copy")) {
                copyurl(url);
                rc = 0;
            } else if (!strcmp(action, "edit"))
                editurl(url);
            else if (!strcmp(action, "delete"))
                deleteurl(url);
            free(action);
        }
        free(chosen);
        free(url);
    }
    free(in.s);
    return rc;
}

/* ---- main ---- */

/* mkdirs: create the directories that lead to file, like mkdir -p. */
static void mkdirs(const char* file) {
    char *path = xstrdup(file), *p;

    for (p = path + (*path == '/'); (p = strchr(p, '/')); p++) {
        *p = '\0';
        if (mkdir(path, 0777) < 0 && errno != EEXIST)
            die("cannot create directory for %s: %s", file, strerror(errno));
        *p = '/';
    }
    free(path);
}

/* oldformat: whether the file has a line of "url description | tags". */
static int oldformat(void) {
    struct buf text = {0};
    char *p, *line;
    int old = 0;

    readpath(bookmarks, &text);
    for (p = text.s; !old && (line = nextline(&p));)
        old = !strchr(line, '\t') && *line != '#' && line[strspn(line, " ")];
    free(text.s);
    return old;
}

static void setaction(int* action, int new) {
    if (*action != NONE) {
        fprintf(stderr, "%s: only one action at a time\n", argv0);
        exit(2);
    }
    *action = new;
}

static const char* needarg(char** argv) {
    if (!argv[1] || !*argv[1]) {
        fprintf(stderr, "%s: %s needs an argument\n", argv0, argv[0]);
        exit(2);
    }
    return argv[1];
}

#define IS(s, l) (!strcmp(*argv, s) || !strcmp(*argv, l))

int main(int argc, char* argv[]) {
    const char *addurl = NULL, *sortname = envor("SBM_SORT", SORTORDER);
    struct buf b = {0}, list = {0};
    char* url;
    int action = NONE, rc = 0;

    (void) argc;
    argv0 = "bm";
    tagfilter = xstrdup("");
    for (argv++; *argv; argv++) {
        if (IS("-h", "--help")) {
            setaction(&action, HELP);
        } else if (IS("-c", "--copy")) {
            setaction(&action, COPY);
        } else if (IS("--print", "--print")) {
            setaction(&action, PRINT);
        } else if (IS("-o", "--open") || IS("-p", "--plumb")) {
            setaction(&action, OPEN);
        } else if (IS("-e", "--edit")) {
            setaction(&action, EDIT);
        } else if (IS("-d", "--delete")) {
            setaction(&action, DELETE);
        } else if (IS("-l", "--list")) {
            setaction(&action, LIST);
        } else if (IS("-m", "--merge")) {
            setaction(&action, MERGE);
        } else if (IS("-a", "--add")) {
            setaction(&action, ADD);
            if (argv[1] && *argv[1] && *argv[1] != '-')
                addurl = *++argv;
        } else if (IS("-t", "--tag")) {
            free(tagfilter);
            tagfilter = xstrdup(needarg(argv));
            argv++;
        } else if (IS("-S", "--sort")) {
            sortname = needarg(argv);
            argv++;
        } else {
            fprintf(stderr, "%s: unknown argument: %s\n", argv0, *argv);
            usagetext(stderr);
            return 2;
        }
    }
    for (order = 0; order < NORDERS && strcmp(orders[order], sortname); order++)
        ;
    if (order == NORDERS) {
        fprintf(stderr, "%s: unknown sort order: %s\n", argv0, sortname);
        return 2;
    }
    if (action == HELP) {
        usagetext(stdout);
        return 0;
    }

    bookmarks = datafile("BOOKMARKS", "bookmarks");
    usertags = datafile("USERTAGS", "usertags");
    engines = datafile("SBM_ENGINES", "engines");
    bufprintf(&b, "%s.usage", bookmarks);
    usage = b.s;
    b = (struct buf) {0};
    bufprintf(&b, "%s.lock", bookmarks);
    lockdir = b.s;
    b = (struct buf) {0};
    bufprintf(&b, "%s/pid", lockdir);
    lockpid = b.s;

    mkdirs(bookmarks);
    if (writepath(bookmarks, O_CREAT | O_APPEND, "", 0) < 0)
        die("cannot create %s: %s", bookmarks, strerror(errno));
    if (oldformat())
        warn("%s has lines in the old format; run: bm-migrate", bookmarks);
    if (action != LIST && action != MERGE)
        pickmenu();

    switch (action) {
    case NONE:
        rc = menu == MENU_FZF ? browsefzf() : browsemenu();
        break;
    case OPEN:
        rc = plumb();
        break;
    case COPY:
        url = chooseurl("copy:");
        rc = copyurl(url);
        free(url);
        break;
    case PRINT:
        url = chooseurl("print:");
        bump(url);
        puts(url);
        free(url);
        break;
    case EDIT:
        url = chooseurl("edit:");
        editurl(url);
        free(url);
        break;
    case DELETE:
        url = chooseurl("delete:");
        deleteurl(url);
        printf("deleted %s\n", url);
        free(url);
        break;
    case ADD:
        rc = add(addurl);
        break;
    case LIST:
        rows();
        rowlines(&list, 0);
        fputs(list.s, stdout);
        free(list.s);
        break;
    case MERGE:
        rc = merge();
        break;
    }

    free(filebuf.s);
    free(all);
    free(view);
    free(tagfilter);
    free(bookmarks);
    free(usertags);
    free(engines);
    free(usage);
    free(lockdir);
    free(lockpid);
    return rc;
}
