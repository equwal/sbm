# Building the .deb, and serving it from your own apt repository

`../debian/` is a complete `debian/` directory. It is kept one level down so
that `packaging/debian/` can hold this note beside it. To use it, copy it to
the top of a source tree:

    cp -r packaging/debian/debian /path/to/sbm-0.3/debian

## Before the first build

Two things in `debian/` are placeholders.

* `debian/copyright` says `SBM_LICENSE_TBD`. Nothing can be uploaded
  anywhere until a real licence is chosen: an unlicensed work is not
  distributable.
* `debian/changelog` says `UNRELEASED` and has no `Closes:` line, because no
  ITP bug has been filed.

Git does not carry the execute bit through every path this directory may
travel, so check it:

    chmod 755 debian/rules debian/tests/smoke debian/tests/upstream-suite

## Building

`3.0 (quilt)` needs an orig tarball beside the source directory:

    sbm-0.3.orig.tar.gz
    sbm-0.3/debian/...

Once v0.3 is tagged, the tarball is the release archive renamed:

    wget -O sbm-0.3.orig.tar.gz \
      https://github.com/equwal/sbm/archive/refs/tags/v0.3.tar.gz

Until then, `make dist` in the source tree produces `sbm-0.3.tar.gz` with the
same top level directory name, which works for local builds.

Build a binary package:

    cd sbm-0.3
    dpkg-buildpackage -us -uc -b

Build source and binary, in a clean chroot, which is what an upload needs:

    sbuild -d unstable
    # or
    pbuilder build ../sbm_0.3-1.dsc

Check it:

    lintian -i -I --pedantic ../sbm_0.3-1_all.deb ../sbm_0.3-1.dsc
    autopkgtest ../sbm_0.3-1_all.deb -- null

Install it locally:

    sudo apt install ./sbm_0.3-1_all.deb

## Getting into Debian proper

Debian needs a Debian Developer to sponsor the first upload.

1. Choose a licence and add a `LICENSE` file upstream.
2. Tag `v0.3` upstream so `debian/watch` has something to find.
3. File an ITP bug: `reportbug wnpp`, type `ITP`. Put the bug number in
   `debian/changelog` as `Closes: #NNNNNN`.
4. Build in a clean chroot and get `lintian --pedantic` quiet.
5. Upload the source package to <https://mentors.debian.net/>.
6. Ask for a sponsor on debian-mentors@lists.debian.org, or in the RFS bug.

This takes weeks to months. The apt repository below works the same day.

## Your own signed apt repository

Both tools below produce a repository that `apt` trusts once the user adds
your key. Pick one.

### reprepro

`conf/distributions`:

    Origin: equwal.com
    Label: sbm
    Codename: stable
    Architectures: amd64 arm64 source
    Components: main
    Description: sbm packages
    SignWith: YOURKEYID

Then:

    mkdir -p ~/apt/conf                  # put the file above in there
    cd ~/apt
    reprepro includedeb stable /path/to/sbm_0.3-1_all.deb
    reprepro include stable /path/to/sbm_0.3-1_amd64.changes   # source too

`reprepro` signs `Release` with the key named in `SignWith`. Copy `~/apt`
to any static web server; nothing server side is needed.

### aptly

    aptly repo create -distribution=stable -component=main sbm
    aptly repo add sbm /path/to/sbm_0.3-1_all.deb
    aptly publish repo -gpg-key=YOURKEYID sbm
    # publishes under ~/.aptly/public; copy that to the web server

`aptly` can also mirror and snapshot, which matters once there is more than
one package.

### The key

Export the public half in binary form, which is what modern apt wants:

    gpg --export YOURKEYID > equwal-archive-keyring.gpg

Serve it next to the repository. Users then write
`/etc/apt/sources.list.d/sbm.sources`:

    Types: deb
    URIs: https://example.com/apt
    Suites: stable
    Components: main
    Signed-By: /usr/share/keyrings/equwal-archive-keyring.gpg

and put the exported key at that path. Do not tell users to pipe a key into
`apt-key`: it has been removed.

`Architectures: amd64 arm64` is only about the index. The package itself is
`Architecture: all`, so one build serves every architecture.
