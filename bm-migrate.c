/*
 * bm-migrate: convert a bookmark file from the old sbm format
 *
 *     URL description | tag tag
 *
 * to the tab separated one bm uses now
 *
 *     URL<tab>description<tab>tag tag
 *
 * The URL is the first word, the tags are whatever follows the last " |", and
 * a line without " |" has no tags. Comments, blank lines and lines that
 * already contain a tab are passed through, so converting twice changes
 * nothing.
 */

#include "util.h"

#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static void usage(FILE* f) {
    fputs("usage: bm-migrate [-n] [file]\n"
          "  file   the bookmark file; defaults to $BOOKMARKS, then to\n"
          "         $XDG_DATA_HOME/sbm/bookmarks. \"-\" converts stdin to stdout.\n"
          "  -n     print the converted file instead of replacing it\n"
          "The original is kept as <file>.bak (or .bak.1, .bak.2, ... if that exists).\n",
        f);
}

/* trim: s without the spaces at its ends; s is changed in place. */
static char* trim(char* s) {
    char* end;

    s += strspn(s, " ");
    for (end = s + strlen(s); end > s && end[-1] == ' ';)
        *--end = '\0';
    return s;
}

/* convert: text in the old format to out. Returns how many lines changed. */
static size_t convert(char* text, struct buf* out) {
    char *line, *url, *desc, *tags, *bar;
    size_t changed = 0;

    bufadd(out, "", 0);
    while ((line = nextline(&text))) {
        if (strchr(line, '\t') || *line == '#' || !line[strspn(line, " ")]) {
            bufprintf(out, "%s\n", line);
            continue;
        }
        url = line + strspn(line, " ");
        desc = url + strcspn(url, " ");
        tags = "";
        /* Look for " |" from where the URL ends: the description may be empty. */
        if ((bar = strrchr(desc, '|')) && bar > desc && bar[-1] == ' ') {
            tags = trim(bar + 1);
            bar[-1] = '\0';
        }
        if (*desc)
            *desc++ = '\0';
        bufprintf(out, "%s\t%s\t%s\n", url, trim(desc), tags);
        changed++;
    }
    return changed;
}

/* backup: copy file to a new name beside it; the name is returned. */
static char* backup(const char* file) {
    struct buf name = {0};
    char* argv[] = {"cp", "-p", "--", NULL, NULL, NULL};
    struct stat st;
    unsigned n;

    /* Never overwrite an earlier backup: it may be the only copy of the
     * original. */
    bufprintf(&name, "%s.bak", file);
    for (n = 1; lstat(name.s, &st) == 0; n++) {
        name.len = 0;
        bufprintf(&name, "%s.bak.%u", file, n);
    }
    argv[3] = (char*) file;
    argv[4] = name.s;
    if (run(argv, NULL, NULL, 0) != 0)
        die("could not back up to %s", name.s);
    return name.s;
}

int main(int argc, char* argv[]) {
    struct buf text = {0}, out = {0};
    struct stat st;
    char *file, *saved;
    size_t count;
    int dryrun = 0;

    (void) argc;
    argv0 = "bm-migrate";
    for (argv++; *argv && **argv == '-' && strcmp(*argv, "-"); argv++) {
        if (!strcmp(*argv, "-h") || !strcmp(*argv, "--help")) {
            usage(stdout);
            return 0;
        } else if (!strcmp(*argv, "-n") || !strcmp(*argv, "--dry-run")) {
            dryrun = 1;
        } else {
            fprintf(stderr, "%s: unknown option: %s\n", argv0, *argv);
            usage(stderr);
            return 2;
        }
    }
    if (argv[0] && argv[1]) {
        fprintf(stderr, "%s: one file at a time\n", argv0);
        return 2;
    }
    file = argv[0] ? xstrdup(argv[0]) : datafile("BOOKMARKS", "bookmarks");

    if (strcmp(file, "-")) {
        if (stat(file, &st) < 0 || !S_ISREG(st.st_mode))
            die("no such file: %s", file);
    } else {
        dryrun = 1;
    }
    if (readpath(file, &text) < 0)
        die("cannot read %s", file);
    count = convert(text.s, &out);

    if (dryrun) {
        fputs(out.s, stdout);
    } else if (count == 0) {
        printf("nothing to migrate in %s\n", file);
    } else {
        saved = backup(file);
        if (writepath(file, O_TRUNC, out.s, out.len) < 0)
            die("could not rewrite %s; the original is in %s", file, saved);
        printf(
            "migrated %lu lines in %s (original kept as %s)\n", (unsigned long) count, file, saved);
        free(saved);
    }
    free(text.s);
    free(out.s);
    free(file);
    return 0;
}
