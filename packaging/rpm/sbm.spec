Name:           sbm
Version:        0.3
Release:        1%{?dist}
Summary:        Bookmark manager made of POSIX sh scripts, driven by dmenu or fzf

# Upstream has not chosen a licence yet and ships no LICENSE file. Replace
# SBM_LICENSE_TBD with the SPDX identifier, and add the LICENSE file to the
# %%files section with %%license once upstream ships one. rpmlint reports
# the token as an invalid licence, which is intended.
License:        SBM_LICENSE_TBD
URL:            https://github.com/equwal/sbm
# No release tag exists yet. Once v0.3 is tagged, fetch with:
#   spectool -g sbm.spec
Source0:        %{url}/archive/refs/tags/v%{version}.tar.gz#/%{name}-%{version}.tar.gz

BuildArch:      noarch

BuildRequires:  make
# make check runs shellcheck -s sh over every script before the test suite.
# Both Fedora and openSUSE call the package ShellCheck.
BuildRequires:  ShellCheck

# Rich dependencies need rpm >= 4.13: Fedora, and openSUSE Leap 15 and later.
# They are the only honest way to say "dmenu or fzf".
Requires:       (dmenu or fzf)
Requires:       /bin/sh
Requires:       awk

Recommends:     (xclip or xsel or wl-clipboard)
Recommends:     xdg-utils

# bm-title and bm-check
Suggests:       curl
# bm-import, for Chromium JSON bookmark files only
Suggests:       jq
# bm-commit
Suggests:       git-core

%description
sbm keeps bookmarks in one tab separated file: URL, description, tags. Lines
starting with # are ignored, so cut, grep, awk and an editor work on it as
well as the tools do.

bm picks a bookmark with dmenu, or with fzf on a bare terminal, and then
opens it, copies it, edits it or deletes it. Text that is no bookmark is
opened as an address or searched for on the web.

The rest are small filters that read and write bookmark lines: bm-import
turns a browser's bookmarks into bookmark lines, bm-check reports dead links,
bm-html writes a searchable web page, bm-migrate converts the old file
format, bm-title prints a page's title and bm-commit keeps the bookmark
file's history in git.

Everything is POSIX sh and POSIX utilities. Nothing is compiled.

%prep
%autosetup

%build
# Nothing is compiled; the package is a set of sh scripts.

%install
%make_install PREFIX=%{_prefix}

# Shipped as documentation, not as configuration: the user copies what they
# want to ~/.local/share/sbm/.
mkdir -p examples
cp -p usertags engines examples/

%check
# The suite scripts the menu, the clipboard and curl, so it needs no display
# and no network.
make check

%files
%doc README TODO examples
%{_bindir}/bm
%{_bindir}/bm-check
%{_bindir}/bm-commit
%{_bindir}/bm-html
%{_bindir}/bm-import
%{_bindir}/bm-migrate
%{_bindir}/bm-title
%{_bindir}/bm-page
%{_bindir}/bm-watch

%changelog
* Sun Sep 20 2026 Spenser Truex <truex@equwal.com> - 0.3-1
- Initial package.
