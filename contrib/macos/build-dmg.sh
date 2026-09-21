#!/bin/sh

# build-dmg.sh: make sbm-VERSION.dmg, the portable macOS edition, in the top
# directory of the source. Run it on macOS:
#
#     sh contrib/macos/build-dmg.sh
#
# The image holds sbm.app. The app contains bm, the bm-* tools and fzf, so it
# needs no other software. The script gets fzf from the fzf release on
# GitHub. It stops if the SHA-256 sum of a download is not the expected one.

set -e

fzf_version=0.74.4
fzf_amd64_sum=2d392b50be66e2ab104ccd52a6072df692b1f9b9c5b449a9c098de885f32c4c5
fzf_arm64_sum=4f6a113bfc0c7959e0005c78d566a51afc4fcefc956f43735c62a9deb19e92ae

here=$(cd "$(dirname "$0")" && pwd)
top=$(cd "$here/../.." && pwd)
version=$(sed -n 's/^VERSION=//p' "$top/config.mk")
out=$top/sbm-$version.dmg

work=${TMPDIR:-/tmp}/sbm-dmg.$$
mkdir "$work"
trap 'rm -rf "$work"' EXIT INT TERM
app=$work/root/sbm.app
mkdir -p "$app/Contents/MacOS"

make -s -C "$top" install PREFIX="$app/Contents/Resources" >/dev/null
cp "$here/sbm" "$app/Contents/MacOS/sbm"
cp "$here/sbm-run" "$app/Contents/Resources/sbm-run"
chmod 755 "$app/Contents/MacOS/sbm" "$app/Contents/Resources/sbm-run"
sed "s/@VERSION@/$version/g" "$here/Info.plist" > "$app/Contents/Info.plist"
plutil -lint "$app/Contents/Info.plist" >/dev/null

url=https://github.com/junegunn/fzf/releases/download/v$fzf_version
for arch in amd64 arm64; do
    curl -fsSL -o "$work/fzf-$arch.tar.gz" \
        "$url/fzf-$fzf_version-darwin_$arch.tar.gz"
done
shasum -a 256 -c >/dev/null <<EOF
$fzf_amd64_sum  $work/fzf-amd64.tar.gz
$fzf_arm64_sum  $work/fzf-arm64.tar.gz
EOF
for arch in amd64 arm64; do
    mkdir "$work/$arch"
    tar -xzf "$work/fzf-$arch.tar.gz" -C "$work/$arch"
done
# One fzf for Intel and Apple silicon.
lipo -create -output "$app/Contents/Resources/bin/fzf" \
    "$work/amd64/fzf" "$work/arm64/fzf"
curl -fsSL -o "$app/Contents/Resources/fzf-LICENSE.txt" \
    "https://raw.githubusercontent.com/junegunn/fzf/v$fzf_version/LICENSE"

# The app has no signature from a registered developer. An ad-hoc signature
# still lets macOS find a damaged app.
codesign --force --deep --sign - "$app"

ln -s /Applications "$work/root/Applications"
hdiutil create -quiet -volname "sbm $version" -srcfolder "$work/root" \
    -ov -format UDZO "$out"
printf '%s\n' "$out"
