/*
 * libFuzzer targets for the code that parses text from outside: bookmark
 * lines, the old file format, tag and engine files, and menu output.
 * Build one target at a time, from the top directory, with a clang that has
 * libFuzzer (on macOS that is the one from Homebrew, not Apple's):
 *
 *     clang -std=c99 -D_POSIX_C_SOURCE=200809L -DFUZZ_BM -g -O1 \
 *         -fsanitize=fuzzer,address,undefined -fno-sanitize-recover=all \
 *         test/fuzz.c util.c -o fuzz-bm
 *     ./fuzz-bm -max_total_time=120 corpus/
 *
 * The targets are -DFUZZ_BM, -DFUZZ_MIGRATE and -DFUZZ_HTML. Each one takes in
 * a whole tool, with its main() renamed, to get at its static functions.
 */

#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define main tool_main
#if defined(FUZZ_BM)
#include "../bm.c"
#elif defined(FUZZ_MIGRATE)
#include "../bm-migrate.c"
#elif defined(FUZZ_HTML)
#include "../bm-html.c"
#else
#error "define FUZZ_BM, FUZZ_MIGRATE or FUZZ_HTML"
#endif
#undef main

#if defined(FUZZ_BM)
/* chars: how many characters s has, counted as column does. */
static size_t chars(const char* s) {
    size_t n = 0;

    for (; *s; s++)
        n += (*s & 0xC0) != 0x80;
    return n;
}

/* The input is the bookmark file, the use counts, the tag file and the
 * engines file, all at once. */
static void target(char* text) {
    static char file[1024];
    struct buf b = {0};
    char *s, **names;
    size_t n, i;

    if (!*file) {
        snprintf(file, sizeof(file), "%s/sbm-fuzz.%ld",
            getenv("TMPDIR") ? getenv("TMPDIR") : "/tmp", (long) getpid());
        bookmarks = usage = usertags = engines = file;
        tagfilter = "";
    }
    if (writepath(file, O_CREAT | O_TRUNC, text, strlen(text)) < 0)
        abort();

    for (order = 0; order < NORDERS; order++) {
        rows();
        for (i = 1; i < nview; i++)
            assert(cmpbookmark(&view[i - 1], &view[i]) < 0);
    }
    b.len = 0;
    rowlines(&b, 1);
    if (nall > 0) {
        assert(find(all[0].url) == &all[0]);
        assert(finddup(all[nall - 1].url));
    }
    oldformat();
    free(engineof("w"));
    knowntag(text, "code");
    hastag(text, "code");

    names = tagnames(text, 0, &n);
    for (i = 1; i < n; i++)
        assert(strcmp(names[i - 1], names[i]) < 0);
    freenames(names, n);
    names = tagnames(text, 1, &n);
    freenames(names, n);

    /* A URL is the same page as itself, whatever it looks like. */
    s = norm(text);
    free(s);
    b.len = 0;
    urlencode(&b, text);
    assert(strspn(b.s, "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._~-+%")
        == b.len);
    b.len = 0;
    column(&b, text, DESCWIDTH, 1);
    assert(chars(text) > DESCWIDTH ? chars(b.s) == DESCWIDTH : chars(b.s) >= DESCWIDTH);
    free(b.s);
    free(nthline(text, 2));
    free(firstfield(text));
}
#elif defined(FUZZ_MIGRATE)
/* Converting what was converted changes nothing. */
static void target(char* text) {
    struct buf once = {0}, twice = {0};
    char* copy;

    convert(text, &once);
    copy = xstrdup(once.s);
    assert(convert(copy, &twice) == 0);
    assert(!strcmp(once.s, twice.s));
    free(copy);
    free(once.s);
    free(twice.s);
}
#else
static void target(char* text) {
    static int quiet;

    if (!quiet && !freopen("/dev/null", "w", stdout))
        abort();
    quiet = 1;
    page(text, "fuzz <title>");
}
#endif

int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
    char* text;

    if (size > 64 * 1024)
        return -1;
    text = xstrndup((const char*) data, size);
    target(text);
    free(text);
    return 0;
}
