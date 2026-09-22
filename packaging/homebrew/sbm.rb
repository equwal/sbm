class Sbm < Formula
  desc "Bookmark manager in C and POSIX sh, driven by dmenu or fzf"
  homepage "https://github.com/equwal/sbm"
  url "https://github.com/equwal/sbm/archive/refs/tags/v0.3.tar.gz"
  sha256 "SBM_SHA256_TBD"
  # No licence has been chosen upstream yet and the repository carries no
  # LICENSE file. Replace SBM_LICENSE_TBD with the SPDX identifier.
  # `brew audit --strict` rejects this token, which is intended.
  license "SBM_LICENSE_TBD"
  head "https://github.com/equwal/sbm.git", branch: "master"

  # A menu is required: dmenu or fzf. Homebrew has no dmenu formula, and dmenu
  # needs X11 on macOS, so fzf is the only practical menu here and is a hard
  # dependency. See caveats.
  depends_on "fzf"

  # Optional runtime helpers are deliberately not dependencies:
  #   curl  ships with macOS      (bm-title, bm-check)
  #   git   ships with the CLT    (bm-commit)
  #   jq    only for Chromium JSON bookmark files (bm-import)
  # Homebrew dropped :optional and :recommended, so these are named in caveats.

  def install
    system "make", "install", "PREFIX=#{prefix}"
    doc.install "README", "TODO"
    (pkgshare/"examples").install "usertags", "engines"
  end

  def caveats
    <<~EOS
      sbm expects a menu, a clipboard command and an opener. On macOS:

        * The menu is fzf. dmenu is an X11 program; if you run XQuartz and
          build dmenu yourself, set SBM_MENU=dmenu.
        * bm does not auto-detect pbcopy/pbpaste/open, so set these yourself:

            export SBM_COPY=pbcopy
            export SBM_PASTE=pbpaste
            export SBM_OPEN=open

      Example tag and search-engine files are installed in

        #{pkgshare}/examples

      Copy them if you want them:

        mkdir -p ~/.local/share/sbm
        cp #{pkgshare}/examples/usertags #{pkgshare}/examples/engines ~/.local/share/sbm/

      Optional programs: jq (bm-import of Chromium bookmark files).
      curl and git come with macOS and the Command Line Tools.
    EOS
  end

  test do
    ENV["BOOKMARKS"] = testpath/"bookmarks"
    ENV["USERTAGS"] = testpath/"usertags"
    ENV["SBM_GIT"] = "0"
    ENV["SBM_FETCH"] = "0"

    # --list and --merge are the two actions that never open a menu.
    merged = pipe_output("#{bin}/bm --merge",
                         "https://equwal.com\tSpenser Truex's website\tusers\n")
    assert_match "added 1", merged

    # Merging the same URL again must be a no-op.
    again = pipe_output("#{bin}/bm --merge",
                        "https://equwal.com/\tsame bookmark, trailing slash\tusers\n")
    assert_match "skipped 1", again

    assert_equal "https://equwal.com\tSpenser Truex's website\tusers",
                 shell_output("#{bin}/bm --list").strip

    assert_match "<li>", shell_output("#{bin}/bm-html")
  end
end
