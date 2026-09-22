/*
 * bm-html: print the bookmarks as one self-contained web page.
 *
 *     bm-html > ~/public_html/bookmarks.html
 *     bm --tag code --list | bm-html -t 'Code' - > code.html
 *
 * Without a file the default bookmark file is read; "-" is stdin.
 *
 * The page lists the bookmarks under each of their tags, with links to the
 * tags at the top. A few lines of script add a filter box; without script the
 * page is still the complete list. page.html?q=words starts out filtered, so
 * the page can serve as a search engine keyword in a browser, or in bm's own
 * engines file:    b | https://example.org/bookmarks.html?q=%s
 */

#include "config.h"
#include "util.h"

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct bookmark {
    char* url;
    char* desc;
    char* tags;
    size_t line;
};

static void usage(FILE* f) { fputs("usage: bm-html [-t title] [file | -] ...\n", f); }

/* esc: print s as HTML text, or as an attribute value in double quotes. */
static void esc(const char* s, size_t n) {
    for (; n > 0; n--, s++) {
        switch (*s) {
        case '&':
            fputs("&amp;", stdout);
            break;
        case '<':
            fputs("&lt;", stdout);
            break;
        case '>':
            fputs("&gt;", stdout);
            break;
        case '"':
            fputs("&quot;", stdout);
            break;
        default:
            putchar(*s);
        }
    }
}

/* foldcmp: strcmp with the letters folded to upper case, as "sort -f" does. */
static int foldcmp(const char* a, const char* b) {
    int x, y;

    for (;; a++, b++) {
        x = toupper((unsigned char) *a);
        y = toupper((unsigned char) *b);
        if (x != y)
            return x < y ? -1 : 1;
        if (!x)
            return 0;
    }
}

/* By description, then by URL. qsort is not stable, hence the line number. */
static int cmpbookmark(const void* pa, const void* pb) {
    const struct bookmark *a = pa, *b = pb;
    int c;

    if (!(c = foldcmp(a->desc, b->desc)) && !(c = foldcmp(a->url, b->url)))
        c = (a->line > b->line) - (a->line < b->line);
    return c;
}

static int cmpstr(const void* a, const void* b) {
    return strcmp(*(char* const*) a, *(char* const*) b);
}

/* script: whether following the URL would run script. Never publish those. */
static int script(const char* url) {
    const char* schemes[] = {"javascript:", "data:", "vbscript:"};
    size_t i, j;

    url += strspn(url, " ");
    for (i = 0; i < sizeof(schemes) / sizeof(*schemes); i++) {
        for (j = 0; schemes[i][j] && tolower((unsigned char) url[j]) == schemes[i][j]; j++)
            ;
        if (!schemes[i][j])
            return 1;
    }
    return 0;
}

/* item: one bookmark as a list item, with links to its tags. */
static void item(const struct bookmark* b) {
    const char *host = b->url, *p, *tag;
    size_t n;

    /* The host is what is between the scheme and the first of "/?#". */
    if (isalpha((unsigned char) *host)) {
        /* strchr finds the final NUL too, which must end the scheme. */
        for (p = host; isalnum((unsigned char) *p) || (*p && strchr("+.-", *p));)
            p++;
        if (!strncmp(p, "://", 3))
            host = p + 3;
    }
    fputs("<li><a href=\"", stdout);
    esc(b->url, strlen(b->url));
    fputs("\">", stdout);
    esc(*b->desc ? b->desc : b->url, strlen(*b->desc ? b->desc : b->url));
    fputs("</a> <small>", stdout);
    esc(host, strcspn(host, "/?#"));
    fputs("</small>", stdout);
    for (tag = b->tags; *(tag += strspn(tag, " ")); tag += n) {
        n = strcspn(tag, " ");
        fputs(" <a class=t href=\"#", stdout);
        esc(tag, n);
        fputs("\">", stdout);
        esc(tag, n);
        fputs("</a>", stdout);
    }
    putchar('\n');
}

/* section: the bookmarks with this tag; "" stands for the ones without. */
static void section(const struct bookmark* b, size_t nb, const char* name) {
    const char *title = *name ? name : "untagged", *tag;
    size_t i, n, len = strlen(name);

    fputs("<section><h2 id=\"", stdout);
    esc(title, strlen(title));
    fputs("\">", stdout);
    esc(title, strlen(title));
    fputs("</h2>\n<ul>\n", stdout);
    for (i = 0; i < nb; i++) {
        tag = b[i].tags + strspn(b[i].tags, " ");
        if (!*tag && !*name)
            item(&b[i]);
        for (; *tag; tag += n, tag += strspn(tag, " ")) {
            n = strcspn(tag, " ");
            if (n == len && !memcmp(tag, name, n))
                item(&b[i]);
        }
    }
    fputs("</ul></section>\n", stdout);
}

/* page: print the web page for the bookmark lines in text, which is cut up. */
static void page(char* text, const char* title) {
    struct bookmark* b = NULL;
    char **names = NULL, *p, *line, *f[3];
    size_t nb = 0, nnames = 0, lineno = 0, i, j, n;
    int untagged = 0;

    for (p = text; (line = nextline(&p));) {
        lineno++;
        if (!*line || *line == '#')
            continue;
        fields(line, f, 3);
        if (script(f[0]))
            continue;
        b = xrealloc(b, (nb + 1) * sizeof(*b));
        b[nb].url = f[0];
        b[nb].desc = f[1];
        b[nb].tags = f[2];
        b[nb].line = lineno;
        nb++;
    }
    if (nb > 0)
        qsort(b, nb, sizeof(*b), cmpbookmark);

    /* The tags by name, each one once. */
    for (i = 0; i < nb; i++) {
        p = b[i].tags + strspn(b[i].tags, " ");
        untagged |= !*p;
        for (; *p; p += n, p += strspn(p, " ")) {
            n = strcspn(p, " ");
            names = xrealloc(names, (nnames + 1) * sizeof(*names));
            names[nnames++] = xstrndup(p, n);
        }
    }
    if (nnames > 0)
        qsort(names, nnames, sizeof(*names), cmpstr);
    for (i = j = 0; i < nnames; i++) {
        if (j > 0 && !strcmp(names[j - 1], names[i]))
            free(names[i]);
        else
            names[j++] = names[i];
    }
    nnames = j;

    fputs("<!doctype html>\n"
          "<meta charset=utf-8>\n"
          "<meta name=viewport content=\"width=device-width, initial-scale=1\">\n"
          "<title>",
        stdout);
    esc(title, strlen(title));
    fputs("</title>\n"
          "<style>\n"
          "body{max-width:50em;margin:1em auto;padding:0 1em;font:1em/1.5 sans-serif}\n"
          "#q{width:100%;box-sizing:border-box;font:inherit;padding:.3em}\n"
          "ul{padding-left:1.2em}small,.t{color:#777;font-size:.85em}.t{margin-left:.3em}\n"
          "</style>\n"
          "<h1>",
        stdout);
    esc(title, strlen(title));
    printf("</h1>\n<input id=q type=search placeholder=\"filter %lu bookmarks\" hidden>\n<p>",
        (unsigned long) nb);
    for (i = 0; i < nnames; i++) {
        fputs("<a href=\"#", stdout);
        esc(names[i], strlen(names[i]));
        fputs("\">", stdout);
        esc(names[i], strlen(names[i]));
        fputs("</a> ", stdout);
    }
    fputs("</p>\n", stdout);
    for (i = 0; i < nnames; i++)
        section(b, nb, names[i]);
    if (untagged)
        section(b, nb, "");
    fputs("<script>\n"
          "var q=document.getElementById(\"q\");q.hidden=false;\n"
          "function f(){var w=q.value.toLowerCase().split(/\\s+/);\n"
          "document.querySelectorAll(\"section\").forEach(function(s){var n=0;\n"
          "s.querySelectorAll(\"li\").forEach(function(l){\n"
          "var t=(l.textContent+\" \"+l.firstChild.href).toLowerCase();\n"
          "var ok=w.every(function(x){return t.indexOf(x)>=0});l.hidden=!ok;if(ok)n++});\n"
          "s.hidden=!n})}\n"
          "q.oninput=f;q.value=new URLSearchParams(location.search).get(\"q\")||\"\";f();\n"
          "</script>\n",
        stdout);

    for (i = 0; i < nnames; i++)
        free(names[i]);
    free(names);
    free(b);
}

int main(int argc, char* argv[]) {
    const char* title = TITLE;
    struct buf text = {0};
    char* deffile[2] = {NULL, NULL};

    (void) argc;
    argv0 = "bm-html";
    for (argv++; *argv && **argv == '-' && strcmp(*argv, "-"); argv++) {
        if (!strcmp(*argv, "-h") || !strcmp(*argv, "--help")) {
            usage(stdout);
            return 0;
        } else if (!strcmp(*argv, "-t") && argv[1]) {
            title = *++argv;
        } else if (!strcmp(*argv, "--")) {
            argv++;
            break;
        } else {
            usage(stderr);
            return 2;
        }
    }
    if (!*argv) {
        deffile[0] = datafile("BOOKMARKS", "bookmarks");
        argv = deffile;
    }
    for (; *argv; argv++)
        if (readpath(*argv, &text) < 0)
            warn("cannot read %s", *argv);
        else if (text.len > 0 && text.s[text.len - 1] != '\n')
            bufputs(&text, "\n");

    page(text.s, title);
    free(text.s);
    free(deffile[0]);
    return 0;
}
