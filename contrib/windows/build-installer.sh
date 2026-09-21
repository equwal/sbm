#!/bin/sh

# build-installer.sh: make sbm-VERSION-setup.exe, the Windows installer, in
# the top directory of the source. The script needs makensis (NSIS), curl,
# unzip and sha256sum. It runs on Linux, and on Windows under Cygwin.
#
#     sh contrib/windows/build-installer.sh
#
# The script gets fzf.exe from the fzf release on GitHub. It stops if the
# SHA-256 sum of the download is not the expected one.

set -e

fzf_version=0.74.4
fzf_sum=5e63c0e798406fcb9c51a9fed4988398e25fdabf8c670e32c16caf7b4a7ed02d

here=$(cd "$(dirname "$0")" && pwd)
top=$(cd "$here/../.." && pwd)
version=$(sed -n 's/^VERSION=//p' "$top/config.mk")
# VIProductVersion needs four numbers: 0.3 becomes 0.3.0.0.
viversion=$(printf '%s.0.0.0\n' "$version" | cut -d. -f1-4)
out=$top/sbm-$version-setup.exe

# makensis for Windows needs Windows paths.
native () {
    if command -v cygpath >/dev/null 2>&1; then
        cygpath -w "$1"
    else
        printf '%s\n' "$1"
    fi
}

work=${TMPDIR:-/tmp}/sbm-installer.$$
mkdir "$work"
trap 'rm -rf "$work"' EXIT INT TERM
mkdir "$work/libexec" "$work/share" "$work/etc"

make -s -C "$top" install PREFIX="$work" >/dev/null
cp "$here/fzf" "$work/bin/"
cp "$here/sbm-setup" "$work/libexec/"
cp "$here/sbm.sh" "$work/etc/"
cp "$top/engines" "$top/usertags" "$top/LICENSE" "$work/share/"

url=https://github.com/junegunn/fzf/releases/download/v$fzf_version
curl -fsSL -o "$work/fzf.zip" "$url/fzf-$fzf_version-windows_amd64.zip"
printf '%s  %s\n' "$fzf_sum" "$work/fzf.zip" | sha256sum -c - >/dev/null
unzip -q "$work/fzf.zip" fzf.exe -d "$work/libexec"
curl -fsSL -o "$work/libexec/fzf-LICENSE.txt" \
    "https://raw.githubusercontent.com/junegunn/fzf/v$fzf_version/LICENSE"

makensis -V2 -DVERSION="$version" -DVIVERSION="$viversion" \
    -DSRC="$(native "$work")" -DOUTFILE="$(native "$out")" \
    "$(native "$here/sbm.nsi")"
printf '%s\n' "$out"
