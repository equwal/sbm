{ lib
, stdenv
, fetchFromGitHub
, makeWrapper
, gawk
, coreutils
, fzf
, dmenu
, xclip
, wl-clipboard
, xdg-utils
, curl
, jq
, git
  # dmenu is X11 only, so it is off on Darwin and fzf carries the menu there.
, withDmenu ? stdenv.hostPlatform.isLinux
, withWaylandClipboard ? stdenv.hostPlatform.isLinux
  # Optional at runtime: bm-title and bm-check (curl), bm-import of Chromium
  # JSON files (jq), bm-commit (git). Cheap enough to keep on by default.
, withCurl ? true
, withJq ? true
, withGit ? true
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "sbm";
  version = "0.3";

  src = fetchFromGitHub {
    owner = "equwal";
    repo = "sbm";
    rev = "v${finalAttrs.version}";
    # No release tag exists yet, so there is nothing to hash. Replace
    # SBM_SHA256_TBD with the SRI hash; lib.fakeHash makes the build print
    # the real one. The token is left here so it shows up in a grep.
    hash = "SBM_SHA256_TBD";
  };

  nativeBuildInputs = [ makeWrapper ];

  doCheck = true;

  checkPhase = ''
    runHook preCheck
    # "make check" also runs shellcheck when it is installed, which would
    # make the result depend on what is in the build environment. The suite
    # itself scripts the menu, the clipboard and curl: no display, no network.
    sh test/run.sh
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    make install PREFIX="$out"
    install -Dm444 README -t "$out/share/doc/sbm"
    install -Dm444 TODO -t "$out/share/doc/sbm"
    install -Dm444 usertags engines -t "$out/share/doc/sbm/examples"
    runHook postInstall
  '';

  postFixup =
    let
      runtimeDeps =
        # fzf is always there: it is the menu that needs no display.
        # xclip, wl-clipboard, dmenu and xdg-utils are X11 or Wayland
        # programs and do not evaluate on Darwin.
        [ gawk coreutils fzf ]
        ++ lib.optionals stdenv.hostPlatform.isLinux [ xclip xdg-utils ]
        ++ lib.optional withDmenu dmenu
        ++ lib.optional withWaylandClipboard wl-clipboard
        ++ lib.optional withCurl curl
        ++ lib.optional withJq jq
        ++ lib.optional withGit git;
    in
    ''
      # bm calls bm-title and bm-commit by name, so $out/bin goes on the
      # PATH as well as the runtime programs.
      for f in "$out"/bin/*; do
        wrapProgram "$f" \
          --prefix PATH : "$out/bin:${lib.makeBinPath runtimeDeps}"
      done
    '';

  meta = {
    description = "Bookmark manager in C and POSIX sh, driven by dmenu or fzf";
    longDescription = ''
      sbm keeps bookmarks in one tab separated file: URL, description, tags.
      bm picks one from dmenu, or from fzf on a bare terminal, and opens it,
      copies it, edits it or deletes it. Text that is no bookmark is opened as
      an address or searched for on the web. The other programs are small
      filters over bookmark lines: bm-import, bm-check, bm-html, bm-migrate,
      bm-title and bm-commit.
    '';
    homepage = "https://github.com/equwal/sbm";
    # Upstream has not chosen a licence yet and ships no LICENSE file.
    # This must become lib.licenses.<id> (an attribute, not a string) before
    # the package can go into nixpkgs; a string fails the meta check.
    license = "SBM_LICENSE_TBD";
    mainProgram = "bm";
    maintainers = [ ];
    platforms = lib.platforms.unix;
  };
})
