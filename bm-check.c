/*
 * bm-check: report dead and permanently moved links.
 *
 *     bm-check                    the default bookmark file
 *     bm-check file ...           these files ("-" is stdin)
 *     bm --tag code --list | bm-check -
 *
 * Reads bookmark lines (only the first field matters, so a plain list of URLs
 * works too) and prints, for each link that is in trouble,
 *
 *     status<tab>url[<tab>new location]
 *
 * where status is the HTTP status, or 000 when there was no answer. 301 and
 * 308 are reported because the bookmark should be updated. Exits 1 when it
 * printed anything.
 */

#include "config.h"
#include "util.h"

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

#define PROBE "%{http_code} %{redirect_url}"

static void usage(void) {
    puts("usage: bm-check [file | -] ...\n"
         "Prints status<tab>url[<tab>new location] for every dead or permanently\n"
         "moved link in the bookmark lines, or URLs, that it reads.\n"
         "Exits 1 when it printed anything.");
}

/* refused: whether the answer to a HEAD request says nothing about the page. */
static int refused(const char* res) {
    size_t n = strcspn(res, " ");

    return n == 0
        || (n == 3 && (!memcmp(res, "403", 3) || !memcmp(res, "405", 3) || !memcmp(res, "000", 3)));
}

/* check: probe one URL and report it if it is in trouble. Returns whether it
 * was. The report is one write, so that probes do not garble each other. */
static int check(const char* url) {
    char* head[] = {"curl", "-sI", "--max-time", TIMEOUT, "-A", AGENT, "-o", "/dev/null", "-w",
        PROBE, "--", NULL, NULL};
    char* get[] = {"curl", "-s", "-r", "0-0", "--max-time", TIMEOUT, "-A", AGENT, "-o", "/dev/null",
        "-w", PROBE, "--", NULL, NULL};
    struct buf res = {0}, line = {0};
    const char *code, *where;

    head[11] = get[13] = (char*) url;
    run(head, NULL, &res, RUN_QUIET);
    if (refused(res.s)) {
        /* Some servers refuse HEAD; ask for the first byte instead. */
        res.len = 0;
        run(get, NULL, &res, RUN_QUIET);
    }
    where = res.s + strcspn(res.s, " ");
    if (*where)
        res.s[where++ - res.s] = '\0';
    code = *res.s ? res.s : "000";
    if (!strcmp(code, "301") || !strcmp(code, "308"))
        bufprintf(&line, "%s\t%s\t%s\n", code, url, where);
    else if (*code != '2' && *code != '3')
        bufprintf(&line, "%s\t%s\n", code, url);
    if (line.len > 0)
        writeall(1, line.s, line.len);
    free(res.s);
    free(line.s);
    return line.len > 0;
}

/* reap: wait for one probe; returns whether it reported its link. */
static int reap(void) {
    int status;

    while (wait(&status) < 0)
        if (errno != EINTR)
            return 0;
    return WIFEXITED(status) && WEXITSTATUS(status) == 1;
}

int main(int argc, char* argv[]) {
    struct buf text = {0};
    char *deffile[2] = {NULL, NULL}, *p, *line, *f[1];
    int running = 0, bad = 0;
    pid_t pid;

    (void) argc;
    argv0 = "bm-check";
    argv++;
    if (*argv && (!strcmp(*argv, "-h") || !strcmp(*argv, "--help"))) {
        usage();
        return 0;
    }
    if (!have("curl"))
        die("needs curl");
    if (!*argv) {
        deffile[0] = datafile("BOOKMARKS", "bookmarks");
        argv = deffile;
    }
    for (; *argv; argv++)
        if (readpath(*argv, &text) < 0)
            warn("cannot read %s", *argv);
        else if (text.len > 0 && text.s[text.len - 1] != '\n')
            bufputs(&text, "\n");

    /* JOBS probes in flight until the list runs out, like xargs -P. */
    for (p = text.s; (line = nextline(&p));) {
        if (!*line || *line == '#')
            continue;
        fields(line, f, 1);
        if (running == JOBS) {
            bad |= reap();
            running--;
        }
        if ((pid = fork()) < 0)
            die("fork: %s", strerror(errno));
        if (pid == 0)
            _exit(check(f[0]));
        running++;
    }
    for (; running > 0; running--)
        bad |= reap();
    free(text.s);
    free(deffile[0]);
    return bad;
}
