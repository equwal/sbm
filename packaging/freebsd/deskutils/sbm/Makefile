PORTNAME=	sbm
DISTVERSIONPREFIX=	v
DISTVERSION=	0.3
CATEGORIES=	deskutils

MAINTAINER=	truex@equwal.com
COMMENT=	Bookmark manager in C and POSIX sh, driven by dmenu or fzf
WWW=		https://github.com/equwal/sbm

# Upstream has not chosen a licence yet and ships no LICENSE file. Replace
# SBM_LICENSE_TBD with an abbreviation from Mk/bsd.licenses.db.mk and add
#   LICENSE_FILE=	${WRKSRC}/LICENSE
# The ports framework refuses an unknown licence, which is intended.
LICENSE=	SBM_LICENSE_TBD

# The ports framework has no "a or b" operator. A menu is required; fzf needs
# no display, so it is the hard dependency. Install x11/dmenu as well if you
# run X11: bm prefers it whenever $DISPLAY is set.
RUN_DEPENDS=	fzf:textproc/fzf

# Upstream's Makefile starts with "include config.mk", which is GNU make
# syntax. bmake wants ".include" and cannot parse the file.
USES=		gmake
USE_GITHUB=	yes
GH_ACCOUNT=	equwal

OPTIONS_DEFINE=		DOCS EXAMPLES

TEST_DEPENDS=	shellcheck:devel/hs-ShellCheck

# PREFIX is /usr/local here, not /usr, and the upstream config.mk already
# defaults to /usr/local. It is passed on the command line anyway, because a
# plain assignment in config.mk wins over the environment under GNU make.
do-install:
	@${MKDIR} ${STAGEDIR}${PREFIX}/bin
	cd ${WRKSRC} && ${SETENV} ${MAKE_ENV} ${MAKE_CMD} install \
		DESTDIR=${STAGEDIR} PREFIX=${PREFIX}

post-install-DOCS-on:
	@${MKDIR} ${STAGEDIR}${DOCSDIR}
	${INSTALL_DATA} ${WRKSRC}/README ${WRKSRC}/TODO ${STAGEDIR}${DOCSDIR}

post-install-EXAMPLES-on:
	@${MKDIR} ${STAGEDIR}${EXAMPLESDIR}
	${INSTALL_DATA} ${WRKSRC}/usertags ${WRKSRC}/engines \
		${STAGEDIR}${EXAMPLESDIR}

# make check runs shellcheck -s sh over every script, then the test suite.
# The suite scripts the menu, the clipboard and curl: no display, no network.
do-test:
	cd ${WRKSRC} && ${SETENV} ${MAKE_ENV} ${MAKE_CMD} check

# Optional at runtime, none of them pulled in:
#   ftp/curl       bm-title, bm-check
#   textproc/jq    bm-import of Chromium JSON bookmark files
#   devel/git      bm-commit
#   x11/xclip      clipboard under X11 (or x11/xsel, or x11/wl-clipboard)
#   devel/xdg-utils  opening URLs with xdg-open

.include <bsd.port.mk>
