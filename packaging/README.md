# Packaging sbm

Package definitions for sbm 0.3, one directory per format. Nothing here is
submitted anywhere yet, and nothing here changes the rest of the repository.

Two facts shape every file below.

1. **There is no licence.** The repository has no `LICENSE` file and no
   licence has been chosen. Every format needs a licence field, so every
   licence field holds the token `SBM_LICENSE_TBD`. It is not a guess and it
   is not a default. Every occurrence is listed under
   [Placeholders](#placeholders).
2. **There is no release tag and no tarball.** The source URL pattern is
   `https://github.com/equwal/sbm/archive/refs/tags/v0.3.tar.gz`, which
   returns 404 today. Checksums hold placeholder tokens. Where a format has a
   live or VCS variant, it is provided as well, because those work now:
   `arch/sbm-git`, `gentoo/.../sbm-9999.ebuild`, and `head` in the Homebrew
   formula.

This is the edition without cloud sync. Nothing here packages, requires or
mentions a sync client.

## What gets installed

`make install` copies the programs in `TOOLS` to `${DESTDIR}${PREFIX}/bin`:

    bm  bm-migrate  bm-import  bm-check  bm-html  bm-title  bm-commit  bm-watch

Nothing is compiled. There are no man pages. Every package calls
`make DESTDIR=... PREFIX=... install` rather than copying the scripts itself,
except the Windows packages, which unpack the release archive and generate
`.cmd` shims instead.

`README` is installed as documentation. `usertags` and `engines` are
examples, not configuration: they go to the examples directory of whatever
format is in use, and the user copies them to `~/.local/share/sbm/`.

## Dependencies, as the packages express them

| | Programs | Why |
|---|---|---|
| Required | POSIX sh, awk | everything |
| Required | dmenu **or** fzf | the menu |
| Required | xclip **or** xsel **or** wl-clipboard | `bm --copy` |
| Recommended | xdg-utils | opening URLs (`xdg-open`) |
| Optional | curl | `bm-title`, `bm-check` |
| Optional | jq | `bm-import` of Chromium JSON files |
| Optional | git | `bm-commit` |

Only Debian, Gentoo and RPM can say "a or b". The others pick one program as
the hard dependency and name the alternatives in the optional list, with a
comment saying so:

* **Arch, FreeBSD, Gentoo, Debian, RPM**: dmenu is the first choice, because
  `bm` prefers it whenever there is a display.
* **Alpine, Void, Homebrew, MacPorts, Chocolatey, Scoop, Nix**: fzf, because
  it needs no display, and on macOS and Windows dmenu is not an option at
  all.

`bm` picks dmenu when `$DISPLAY` or `$WAYLAND_DISPLAY` is set and fzf
otherwise, so installing both is fine and needs no configuration.

## The formats

| Format | Path | Build and test locally | Where it goes | Status |
|---|---|---|---|---|
| Homebrew | `homebrew/sbm.rb` | `brew install --build-from-source ./sbm.rb`, `brew test sbm`, `brew audit --strict --new sbm` | Your own tap (`brew tap equwal/sbm`) first. homebrew-core has a notability bar: roughly 30 forks, 30 watchers, 75 stars, and a maintained, versioned release. sbm meets none of it today. | Written, not built. `license` and `sha256` are placeholders, so `brew audit` fails until they are real. `head` works now. |
| Gentoo | `gentoo/app-misc/sbm/` | Put it in a local overlay, then `ebuild sbm-0.3.ebuild manifest`, `emerge -av app-misc/sbm`, `FEATURES=test emerge app-misc/sbm`, `pkgcheck scan` | GURU (the user overlay) first: it takes anyone. `::gentoo` needs a developer or the proxy-maintainers project; `metadata.xml` already names proxy-maint. | Written, not built. `pkgcheck` will flag `SBM_LICENSE_TBD` as a nonexistent licence. `sbm-9999.ebuild` works now. |
| Arch | `arch/sbm/PKGBUILD`, `arch/sbm-git/PKGBUILD` | `makepkg -si`, `makepkg --printsrcinfo > .SRCINFO`, `namcap PKGBUILD` and `namcap *.pkg.tar.zst` | AUR: `git clone ssh://aur@aur.archlinux.org/sbm.git`, commit `PKGBUILD` and `.SRCINFO`, push. No review queue. `[extra]` needs a Trusted User. | Written, not built. `sbm-git` works now; `sbm` needs the tag. `.SRCINFO` is not committed here: it is generated, and it would go stale. |
| Debian | `debian/debian/`, notes in `debian/apt/README.md` | `dpkg-buildpackage -us -uc -b`, `lintian -i -I --pedantic`, `autopkgtest`. See `debian/apt/README.md`. | Debian proper needs an ITP bug and a sponsor through mentors.debian.net, which takes weeks. Your own signed apt repository (reprepro or aptly) works the same day; `debian/apt/README.md` covers both. | Written, not built. `debian/rules` and `debian/tests/*` need the execute bit set after copying. |
| Chocolatey | `chocolatey/sbm.nuspec`, `chocolatey/tools/` | `choco pack` (done, see below), then `choco install sbm -s .` on a throwaway machine | community.chocolatey.org, with automated checks plus human moderation. Moderators dislike embedded binaries and like package scripts that download from the official source, which is what this does. | `choco pack` succeeds. Not installed or pushed from here. |
| Scoop | `scoop/sbm.json` | `scoop install .\sbm.json`, `scoop checkver sbm <bucket>`, `scoop bucket add` your own bucket | Your own bucket repository. `ScoopInstaller/Extras` takes pull requests; `Main` is for widely used, well known programs. | Written, not installed. JSON parses and the shim generator was run for real. |
| Nix | `nix/default.nix`, `nix/flake.nix` | `nix build -f default.nix`, or `nix build .#sbm` in this directory, then `nixpkgs-review` | A pull request against NixOS/nixpkgs, package file under `pkgs/by-name/sb/sbm/package.nix`. | Written, not evaluated. `meta.license` must become `lib.licenses.<id>`, an attribute and not a string, before nixpkgs will take it. |
| RPM | `rpm/sbm.spec` | `rpmbuild -ba sbm.spec`, `mock -r fedora-rawhide-x86_64 --rebuild *.src.rpm`, `rpmlint sbm.spec` | Fedora: a package review bug in Bugzilla and a sponsor for the first package. openSUSE: a submit request to Factory through the Open Build Service, which is faster. | Written, not built. Rich dependencies `(dmenu or fzf)` need rpm 4.13 or newer: Fedora, and openSUSE Leap 15 and later. |
| Alpine | `alpine/APKBUILD` | `abuild -r`, `abuild checksum`, `apkbuild-lint APKBUILD` | A merge request against `alpinelinux/aports`, in `community/`. | Written, not built. Alpine hashes with sha512, so the token there is `SBM_SHA512_TBD`. |
| Void | `void/srcpkgs/sbm/template` | Inside a void-packages checkout: `./xbps-src pkg sbm`, `xlint srcpkgs/sbm/template` | A pull request against `void-linux/void-packages`. | Written, not built. |
| FreeBSD | `freebsd/deskutils/sbm/` | In a ports tree: `make makesum`, `make stage`, `make check-plist`, `make test`, `portlint -A` | A `ports` bug in Bugzilla with the shar or a patch, or a pull request against `freebsd/freebsd-ports`. | Written, not built. `USES=gmake` is needed; see [Upstream notes](#upstream-notes). |
| MacPorts | `macports/Portfile` | `port lint --nitpick`, `sudo port -v install` from a local ports tree | A pull request against `macports/macports-ports`. | Written, not built. `checksums` needs three tokens replaced, not one. |
| Guix | `guix/sbm.scm` | `guix build -L packaging/guix sbm`, `guix shell -L packaging/guix sbm -- bm --list`, `guix lint -L packaging/guix sbm` | A patch to `guix-patches@gnu.org`, or a channel of your own, which works immediately. | Written, not evaluated. The `#:use-module` lines are a best guess at where each program lives in `gnu/packages/`; `guix build` will say if one is wrong. |

## Placeholders

One search and replace per token finishes each job. Nothing else in these
files is a placeholder.

### `SBM_LICENSE_TBD` — 31 lines in 16 files

Replace with the licence, in whatever spelling the format wants: an SPDX
identifier for most, a name from `licenses/` for Gentoo, an abbreviation from
`Mk/bsd.licenses.db.mk` for FreeBSD, a `(guix licenses)` variable for Guix, a
`lib.licenses` attribute for Nix, and the full text plus a short name for
Debian.

| File | Lines |
|---|---|
| `alpine/APKBUILD` | 10 (comment), 13 |
| `arch/sbm/PKGBUILD` | 10 (comment), 14 |
| `arch/sbm-git/PKGBUILD` | 14 |
| `chocolatey/sbm.nuspec` | 16 (comment), 19 |
| `debian/apt/README.md` | 13 (prose) |
| `debian/debian/copyright` | 8, 12, 14, 18 (prose) |
| `freebsd/deskutils/sbm/Makefile` | 11 (comment), 14 |
| `gentoo/app-misc/sbm/sbm-0.3.ebuild` | 14 (comment), 16 |
| `gentoo/app-misc/sbm/sbm-9999.ebuild` | 14 (comment), 15 |
| `guix/sbm.scm` | 128 (comment), 131 |
| `homebrew/sbm.rb` | 7 (comment), 9 |
| `macports/Portfile` | 26 (comment), 29 |
| `nix/default.nix` | 101 |
| `rpm/sbm.spec` | 7 (comment), 10 |
| `scoop/sbm.json` | 10 (comment), 17 |
| `void/srcpkgs/sbm/template` | 15 (comment), 17 |

One of these is not a bare token. `choco pack` refuses a `licenseUrl` that
does not parse as a URL (error CHCU0001), so
`chocolatey/sbm.nuspec` line 19 carries the token inside a URL path:
`https://github.com/equwal/sbm/blob/master/SBM_LICENSE_TBD`. That URL does
not resolve. The same search and replace still finds it.

### Checksum placeholders

No tag means no tarball means no checksum. Four tokens, because the formats
do not agree on a hash.

`SBM_SHA256_TBD` — 15 lines in 9 files:

| File | Lines | Replace by running |
|---|---|---|
| `arch/sbm/PKGBUILD` | 32 (comment), 33 | `makepkg -g` |
| `chocolatey/tools/chocolateyInstall.ps1` | 24 (comment), 26 | `Get-FileHash .\v0.3.tar.gz -Algorithm SHA256` |
| `freebsd/deskutils/sbm/distinfo` | 2 | `make makesum` |
| `guix/sbm.scm` | 40 (comment), 42 | `guix download <url>` (base32, not hex) |
| `homebrew/sbm.rb` | 5 | `brew fetch --build-from-source sbm` |
| `macports/Portfile` | 34 | `port -v checksum sbm` |
| `nix/default.nix` | 34 (comment), 36 | `nix-prefetch-url --unpack <url>` (SRI, not hex) |
| `scoop/sbm.json` | 11 (comment), 26 | `scoop checkver sbm <bucket> -u` |
| `void/srcpkgs/sbm/template` | 21 (comment), 22 | `xgensum -i srcpkgs/sbm/template` |

`SBM_SHA512_TBD` — `alpine/APKBUILD` lines 53 (comment) and 55. Alpine hashes
with sha512. Replace by running `abuild checksum`.

`SBM_RMD160_TBD` and `SBM_SIZE_TBD` — `macports/Portfile` lines 33 and 35.
MacPorts wants rmd160, sha256 and the byte size. `port -v checksum sbm`
prints all three.

`freebsd/deskutils/sbm/distinfo` also has `TIMESTAMP = 0` and `SIZE ... = 0`.
`make makesum` rewrites the whole file, so those need no hand editing.

### Native "skip" values, used on purpose

`arch/sbm-git/PKGBUILD` line 29 uses `sha256sums=('SKIP')`. That is correct,
not a placeholder: a git source has no fixed archive to hash.

## Upstream notes

Things a reviewer will raise, none of which are fixed in this directory,
because nothing outside `packaging/` was touched.

* **No `LICENSE` file, no licence chosen.** Every repository above will
  refuse the package, and an unlicensed work is not distributable at all.
  This is the one blocker.
* **No tags.** Nine of the twelve formats need a versioned archive.
  `debian/watch`, `checkver` and `autoupdate` all look for `v*` tags and find
  nothing.
* **No man pages.** `TODO` lists them as unfinished. Debian, Fedora and
  FreeBSD all expect a man page for a program in `bin`, and lintian will say
  so. `config.mk` defines `MANPREFIX` and the `Makefile` never uses it.
* **`Makefile` needs GNU make, not POSIX make.** The first line is
  `include config.mk`. BSD make wants `.include "config.mk"` and cannot parse
  the file at all. That is why the FreeBSD port sets `USES=gmake`, which is
  an odd thing to need in a project whose README says it keeps to POSIX. POSIX
  make only gained `include` in the 2024 edition. Changing the line to
  `.include` would break GNU make instead; supporting both means a small
  shim, or moving the variables into the `Makefile`.
* **`install` and `uninstall` disagree.** `install` copies `${TOOLS}`;
  `uninstall` removes `${SCRIPTS}`, the full list. Harmless for packages,
  which never call `uninstall`, but surprising.
* **`.gitignore` contains `bm`.** The main program is already tracked, so it
  is unaffected today, but deleting and re-adding `bm` would silently fail.
  `bmks` and `tags.*` in the same file are fine.
* **`bm` has no `--version`.** Several ecosystems' smoke tests reach for it
  first. The test blocks here use `bm --list` and `bm --merge` instead, which
  are the two actions that never open a menu.
* **`make check` is not hermetic.** It runs shellcheck only when shellcheck
  happens to be installed, so the same command lints or does not lint
  depending on the machine. The Gentoo, Nix, Guix and MacPorts definitions
  call `sh test/run.sh` directly for that reason, and declare shellcheck as a
  build-time dependency where the format has one.
* **The test suite is not declared anywhere.** It uses `jq`, `git`, `node`
  and `make` when they are present and skips those groups otherwise, so it
  passes either way, but a build that has none of them tests less than a
  build that has all of them.
* `DESTDIR` itself is well behaved: `make install DESTDIR=... PREFIX=...`
  creates the directory and copies the scripts with mode 755, and the test
  suite has its own check that `TOOLS` is honoured.

## Release checklist

1. **Choose a licence.** Add `LICENSE` at the top of the repository and a
   line in `README`. Nothing else on this list matters until this is done.
2. Replace `SBM_LICENSE_TBD` everywhere listed above. Then add the licence
   file to the packages that install one:
   * Arch: `install -Dm644 LICENSE "$pkgdir/usr/share/licenses/$pkgname/LICENSE"`
   * Alpine: `install -Dm644 LICENSE "$pkgdir"/usr/share/licenses/$pkgname/LICENSE`
   * Void: `vlicense LICENSE`
   * RPM: `%license LICENSE` in `%files`
   * FreeBSD: `LICENSE_FILE=${WRKSRC}/LICENSE`
   * Debian: the full text goes into `debian/copyright`
3. Tag the release: `git tag -a v0.3 -m 'sbm 0.3' && git push --tags`, and
   check that
   `https://github.com/equwal/sbm/archive/refs/tags/v0.3.tar.gz` downloads
   and unpacks to `sbm-0.3/`.
4. Compute the checksums and replace the four checksum tokens, using the
   commands in the table above.
5. Optional, and worth doing first: write the man pages that `TODO` asks for,
   and decide what to do about `include config.mk` versus BSD make.
6. Submit, easiest first:
   * **AUR** (`sbm`, `sbm-git`): push. No review.
   * **Your own apt repository**: `debian/apt/README.md`.
   * **Your own Homebrew tap and Scoop bucket**: push.
   * **A Guix channel**: push.
   * **GURU** (Gentoo user overlay): pull request.
   * **Void, Alpine, nixpkgs, macports-ports, freebsd-ports**: pull request
     or bug, reviewed but not sponsored.
   * **Chocolatey community**: push, then wait for moderation.
   * **Fedora, openSUSE Factory**: review bug or submit request.
   * **Debian proper**: ITP bug, then a sponsor. Slowest.
   * **homebrew-core**: only once the project clears the notability bar.

## What was checked on this machine, and what was not

Checked: `bash -n` on both PKGBUILDs, the APKBUILD, the Void template and
both ebuilds; `sh -n` on the autopkgtest scripts; Python XML parsing of
`metadata.xml` and `sbm.nuspec`; Python JSON parsing of `sbm.json`; the
PowerShell language parser on both `.ps1` files; `choco pack`, which built a
`.nupkg` that was then deleted; bracket balance and field syntax for the Nix,
Guix, Tcl, Ruby and Debian files; and the generated Windows `.cmd` shim, run
for real against the `bm` and `bm-html` in this repository.

Not checked: nothing was installed or built as a package, because that needs
each distribution. There is no Ruby here, so the formula was not run through
`ruby -c`. There is no `make` and no shellcheck here, and `test/run.sh` does
not run under Git Bash: `mkdir -m 700` inside the Windows temporary directory
fails with "cannot change permissions". That is an MSYS and Windows problem,
not a fault in the suite.
