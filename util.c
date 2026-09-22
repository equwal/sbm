/* Shared by bm and the bm-* tools: memory, strings, files, child programs. */

#include "util.h"

#include <errno.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

const char* argv0 = "bm";
volatile sig_atomic_t busy;
volatile sig_atomic_t stopped;

void die(const char* fmt, ...) {
    va_list ap;

    fprintf(stderr, "%s: ", argv0);
    va_start(ap, fmt);
    vfprintf(stderr, fmt, ap);
    va_end(ap);
    fputc('\n', stderr);
    exit(1);
}

void warn(const char* fmt, ...) {
    va_list ap;

    fprintf(stderr, "%s: ", argv0);
    va_start(ap, fmt);
    vfprintf(stderr, fmt, ap);
    va_end(ap);
    fputc('\n', stderr);
}

void* xmalloc(size_t n) {
    void* p = malloc(n ? n : 1);

    if (!p)
        die("out of memory");
    return p;
}

void* xrealloc(void* p, size_t n) {
    p = realloc(p, n ? n : 1);
    if (!p)
        die("out of memory");
    return p;
}

char* xstrndup(const char* s, size_t n) {
    char* p = xmalloc(n + 1);

    memcpy(p, s, n);
    p[n] = '\0';
    return p;
}

char* xstrdup(const char* s) { return xstrndup(s, strlen(s)); }

void bufadd(struct buf* b, const char* s, size_t n) {
    if (b->len + n + 1 > b->cap) {
        b->cap = (b->len + n + 1) * 2;
        b->s = xrealloc(b->s, b->cap);
    }
    memcpy(b->s + b->len, s, n);
    b->len += n;
    b->s[b->len] = '\0';
}

void bufputs(struct buf* b, const char* s) { bufadd(b, s, strlen(s)); }

void bufprintf(struct buf* b, const char* fmt, ...) {
    va_list ap;
    int n;

    va_start(ap, fmt);
    n = vsnprintf(NULL, 0, fmt, ap);
    va_end(ap);
    if (n < 0)
        die("vsnprintf failed");
    bufadd(b, "", 0);
    if (b->len + n + 1 > b->cap) {
        b->cap = (b->len + n + 1) * 2;
        b->s = xrealloc(b->s, b->cap);
    }
    va_start(ap, fmt);
    vsnprintf(b->s + b->len, (size_t) n + 1, fmt, ap);
    va_end(ap);
    b->len += n;
}

/* readfd: append all of fd to b. b->s is a string afterwards, also on error. */
int readfd(int fd, struct buf* b) {
    char chunk[4096];
    ssize_t n;

    bufadd(b, "", 0);
    while ((n = read(fd, chunk, sizeof(chunk))) != 0) {
        if (n < 0) {
            if (errno == EINTR)
                continue;
            return -1;
        }
        bufadd(b, chunk, (size_t) n);
    }
    return 0;
}

/* readpath: like readfd, for a file name; "-" is stdin. */
int readpath(const char* path, struct buf* b) {
    int fd, rc;

    bufadd(b, "", 0);
    if (!strcmp(path, "-"))
        return readfd(0, b);
    if ((fd = open(path, O_RDONLY)) < 0)
        return -1;
    rc = readfd(fd, b);
    close(fd);
    return rc;
}

int writeall(int fd, const char* s, size_t n) {
    ssize_t w;

    while (n > 0) {
        if ((w = write(fd, s, n)) < 0) {
            if (errno == EINTR)
                continue;
            return -1;
        }
        s += w;
        n -= (size_t) w;
    }
    return 0;
}

/*
 * writepath: open path with flags and write s to it. The file is written in
 * place, never replaced by rename(), so that a symlinked file stays a symlink
 * and keeps its mode.
 */
int writepath(const char* path, int flags, const char* s, size_t n) {
    int fd, rc;

    if ((fd = open(path, O_WRONLY | flags, 0666)) < 0)
        return -1;
    rc = writeall(fd, s, n);
    if (close(fd) < 0)
        rc = -1;
    return rc;
}

/*
 * nextline: the next line of *p, cut off at its newline, or NULL when there
 * are no more. *p is changed in place and moved past the line.
 */
char* nextline(char** p) {
    char *line = *p, *nl;

    if (!line || !*line)
        return NULL;
    if ((nl = strchr(line, '\n'))) {
        *nl = '\0';
        *p = nl + 1;
    } else {
        *p = line + strlen(line);
    }
    return line;
}

/*
 * fields: cut line at its tabs, in place. The first max fields go to f, and
 * the ones the line lacks are "". Returns how many fields the line has.
 */
size_t fields(char* line, char** f, size_t max) {
    size_t n = 0, i;
    char* tab;

    for (;;) {
        if (n < max)
            f[n] = line;
        n++;
        if (!(tab = strchr(line, '\t')))
            break;
        *tab = '\0';
        line = tab + 1;
    }
    for (i = n; i < max; i++)
        f[i] = line + strlen(line);
    return n;
}

/* words: split s at blanks, as the shell does with an unquoted variable. */
char** words(const char* s) {
    char** w = NULL;
    size_t n = 0, len;

    for (;;) {
        s += strspn(s, " \t\n");
        w = xrealloc(w, (n + 1) * sizeof(*w));
        if (!*s)
            break;
        len = strcspn(s, " \t\n");
        w[n++] = xstrndup(s, len);
        s += len;
    }
    w[n] = NULL;
    return w;
}

void freewords(char** w) {
    size_t i;

    for (i = 0; w && w[i]; i++)
        free(w[i]);
    free(w);
}

/* have: whether prog can be run, like "command -v". */
int have(const char* prog) {
    const char *path, *end;
    struct buf file = {0};
    struct stat st;
    int found = 0;

    if (strchr(prog, '/'))
        return access(prog, X_OK) == 0;
    if (!(path = getenv("PATH")))
        return 0;
    while (!found) {
        end = path + strcspn(path, ":");
        file.len = 0;
        if (end == path)
            bufputs(&file, ".");
        else
            bufadd(&file, path, (size_t) (end - path));
        bufprintf(&file, "/%s", prog);
        found = stat(file.s, &st) == 0 && S_ISREG(st.st_mode) && access(file.s, X_OK) == 0;
        if (!*end)
            break;
        path = end + 1;
    }
    free(file.s);
    return found;
}

/*
 * run: run a program found on PATH and wait for it. in, unless NULL, is what
 * it reads on stdin; out, unless NULL, gets what it writes to stdout. The
 * arguments are passed as they are: no shell ever sees them. Returns the exit
 * status, 127 when the program could not be run.
 *
 * A child of its own writes the input. That way it does not matter whether
 * the program reads all of its input before it writes, as menus do, or not.
 *
 * A signal handler that finds busy set leaves stopped set instead of ending
 * the process: run() then ends it once the program is done.
 */
int run(char* const argv[], const char* in, struct buf* out, int flags) {
    int ip[2] = {-1, -1}, op[2] = {-1, -1}, status = 0, fd;
    pid_t pid, writer = -1;

    if (out)
        bufadd(out, "", 0);
    if (!argv[0])
        return 127;
    fflush(NULL);
    if ((in && pipe(ip) < 0) || (out && pipe(op) < 0))
        die("pipe: %s", strerror(errno));
    busy = 1;
    if ((pid = fork()) < 0)
        die("fork: %s", strerror(errno));
    if (pid == 0) {
        if (in) {
            dup2(ip[0], 0);
            close(ip[0]);
            close(ip[1]);
        }
        if (out) {
            dup2(op[1], 1);
            close(op[0]);
            close(op[1]);
        }
        if ((flags & RUN_QUIET) && (fd = open("/dev/null", O_WRONLY)) >= 0) {
            dup2(fd, 2);
            close(fd);
        }
        execvp(argv[0], argv);
        warn("%s: %s", argv[0], strerror(errno));
        _exit(127);
    }
    if (in) {
        if ((writer = fork()) < 0)
            die("fork: %s", strerror(errno));
        if (writer == 0) {
            close(ip[0]);
            if (out) {
                close(op[0]);
                close(op[1]);
            }
            /* The program may leave early; then the rest is dropped. */
            writeall(ip[1], in, strlen(in));
            _exit(0);
        }
        close(ip[0]);
        close(ip[1]);
    }
    if (out) {
        close(op[1]);
        readfd(op[0], out);
        close(op[0]);
    }
    while (waitpid(pid, &status, 0) < 0 && errno == EINTR)
        ;
    if (writer > 0)
        while (waitpid(writer, NULL, 0) < 0 && errno == EINTR)
            ;
    busy = 0;
    if (stopped)
        exit(1);
    if (WIFEXITED(status))
        return WEXITSTATUS(status);
    return 128 + (WIFSIGNALED(status) ? WTERMSIG(status) : 0);
}

/*
 * detach: start a program that runs on by itself, without a terminal and
 * without stdin, stdout or stderr, and do not wait for it. A child forks it
 * and ends at once, so that the program is never a zombie of this process.
 */
void detach(char* const argv[]) {
    pid_t pid;
    int fd;

    fflush(NULL);
    if ((pid = fork()) < 0)
        die("fork: %s", strerror(errno));
    if (pid == 0) {
        if (fork() != 0)
            _exit(0);
        setsid();
        if ((fd = open("/dev/null", O_RDWR)) >= 0) {
            dup2(fd, 0);
            dup2(fd, 1);
            dup2(fd, 2);
            if (fd > 2)
                close(fd);
        }
        execvp(argv[0], argv);
        _exit(127);
    }
    while (waitpid(pid, NULL, 0) < 0 && errno == EINTR)
        ;
}

/* datafile: $env, or else the file of that name below $XDG_DATA_HOME/sbm. */
char* datafile(const char* env, const char* name) {
    const char* s;
    struct buf b = {0};

    if ((s = getenv(env)) && *s)
        return xstrdup(s);
    if ((s = getenv("XDG_DATA_HOME")) && *s) {
        bufprintf(&b, "%s/sbm/%s", s, name);
    } else {
        s = getenv("HOME");
        bufprintf(&b, "%s/.local/share/sbm/%s", s ? s : "", name);
    }
    return b.s;
}
