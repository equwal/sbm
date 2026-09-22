/* Defaults. Where an environment variable is named, it wins at run time. */

/* bm */
#define DMENULINES "15" /* $DMENULINES */
#define SEARCH "https://duckduckgo.com/?q=%s" /* $SBM_SEARCH */
#define SORTORDER "used" /* $SBM_SORT */
#define EDITOR "vi" /* $VISUAL, $EDITOR */
#define LOCKWAIT "10" /* $SBM_LOCK_WAIT: seconds to wait for the write lock */
/* fzf and the options of every call; $SBM_FZF_OPTS is added after them */
#define FZF "fzf", "-i", "--reverse", "--height=40%"
/* columns of the fzf list, in characters */
#define DESCWIDTH 44
#define TAGWIDTH 18

/* bm-check */
#define JOBS 8 /* probes in flight */
#define TIMEOUT "10" /* seconds per probe */
#define AGENT "Mozilla/5.0"

/* bm-html */
#define TITLE "Bookmarks"
