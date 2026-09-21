# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit git-r3 optfeature

DESCRIPTION="Bookmark manager made of POSIX sh scripts, driven by dmenu or fzf"
HOMEPAGE="https://github.com/equwal/sbm"
EGIT_REPO_URI="https://github.com/equwal/sbm.git"
EGIT_BRANCH="master"

# Upstream has not chosen a licence yet and ships no LICENSE file.
# Replace SBM_LICENSE_TBD with a name from licenses/ in the tree.
LICENSE="SBM_LICENSE_TBD"
SLOT="0"
# A live ebuild carries no KEYWORDS on purpose.
IUSE="+X wayland"

RDEPEND="
	|| (
		x11-misc/dmenu
		app-shells/fzf
	)
	X? (
		|| (
			x11-misc/xclip
			x11-misc/xsel
		)
	)
	wayland? ( gui-apps/wl-clipboard )
"

src_compile() {
	# Nothing is compiled; the package is a set of sh scripts.
	:
}

src_test() {
	sh test/run.sh || die "test suite failed"
}

src_install() {
	emake DESTDIR="${D}" PREFIX="${EPREFIX}/usr" install

	dodoc README TODO
	docinto examples
	dodoc usertags engines
}

pkg_postinst() {
	optfeature "page titles for 'bm --add' and dead-link checks" net-misc/curl
	optfeature "importing Chromium bookmark files" app-misc/jq
	optfeature "keeping the bookmark file's history in git" dev-vcs/git
	optfeature "opening URLs with the desktop's handler" x11-misc/xdg-utils
}
