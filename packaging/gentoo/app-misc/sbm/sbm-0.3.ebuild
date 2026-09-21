# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit optfeature

DESCRIPTION="Bookmark manager made of POSIX sh scripts, driven by dmenu or fzf"
HOMEPAGE="https://github.com/equwal/sbm"
SRC_URI="https://github.com/equwal/sbm/archive/refs/tags/v${PV}.tar.gz
	-> ${P}.tar.gz"

# Upstream has not chosen a licence yet and ships no LICENSE file.
# Replace SBM_LICENSE_TBD with a name from licenses/ in the tree.
# pkgcheck reports this token as a nonexistent licence, which is intended.
LICENSE="SBM_LICENSE_TBD"
SLOT="0"
KEYWORDS="~amd64 ~arm64 ~x86"
IUSE="+X wayland"

# A menu is required and either program will do; || () says exactly that.
# The clipboard programs are per-display-server, so they hang off USE.
# Without X and without wayland nothing is pulled in and you set $SBM_COPY
# and $SBM_PASTE yourself.
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
	# "make check" also runs shellcheck when it happens to be installed,
	# which would make the result depend on the build host. The suite itself
	# is deterministic: it scripts the menu, the clipboard and curl, so it
	# needs no display and no network.
	sh test/run.sh || die "test suite failed"
}

src_install() {
	emake DESTDIR="${D}" PREFIX="${EPREFIX}/usr" install

	dodoc README TODO
	docinto examples
	dodoc usertags engines

	# Once upstream adds a LICENSE file, nothing extra is needed here:
	# dodoc handles it through the LICENSE variable above.
}

pkg_postinst() {
	optfeature "page titles for 'bm --add' and dead-link checks" net-misc/curl
	optfeature "importing Chromium bookmark files" app-misc/jq
	optfeature "keeping the bookmark file's history in git" dev-vcs/git
	optfeature "opening URLs with the desktop's handler" x11-misc/xdg-utils

	elog "Example tag and search-engine files are in"
	elog "  /usr/share/doc/${PF}/examples"
	elog "Copy them to ~/.local/share/sbm/ if you want them."
}
