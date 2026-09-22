;;; sbm: bookmarks in a plain file, picked with dmenu or fzf.
;;;
;;; Build it out of this file:
;;;
;;;   guix build -L packaging/guix sbm
;;;   guix shell -L packaging/guix sbm -- bm --list
;;;
;;; To send it upstream, move the package form into gnu/packages/, most
;;; likely web.scm or suckless.scm, and drop the define-module header.

(define-module (sbm)
  #:use-module (guix packages)
  #:use-module (guix download)
  #:use-module (guix gexp)
  #:use-module (guix utils)
  #:use-module (guix build-system gnu)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (gnu packages base)
  #:use-module (gnu packages curl)
  #:use-module (gnu packages freedesktop)
  #:use-module (gnu packages gawk)
  #:use-module (gnu packages haskell-apps)
  #:use-module (gnu packages suckless)
  #:use-module (gnu packages terminals)
  #:use-module (gnu packages version-control)
  #:use-module (gnu packages web)
  #:use-module (gnu packages xdisorg))

(define-public sbm
  (package
    (name "sbm")
    (version "0.3")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "https://github.com/equwal/sbm"
                           "/archive/refs/tags/v" version ".tar.gz"))
       (file-name (string-append name "-" version ".tar.gz"))
       ;; No release tag exists yet, so there is nothing to hash. Replace
       ;; SBM_SHA256_TBD with the base32 hash that this prints:
       ;;   guix download <the URL above>
       (sha256 (base32 "SBM_SHA256_TBD"))))
    (build-system gnu-build-system)
    (arguments
     (list
      #:make-flags
      #~(list (string-append "PREFIX=" #$output))
      #:phases
      #~(modify-phases %standard-phases
          ;; There is no configure script.
          (delete 'configure)
          (replace 'check
            (lambda* (#:key tests? #:allow-other-keys)
              (when tests?
                ;; "make check" also runs shellcheck when it is installed,
                ;; which would make the result depend on the build
                ;; environment. The suite scripts the menu, the clipboard
                ;; and curl: no display, no network.
                (invoke "sh" "test/run.sh"))))
          (add-after 'install 'install-doc
            (lambda _
              (let* ((doc (string-append #$output "/share/doc/" #$name "-"
                                         #$version))
                     (examples (string-append doc "/examples")))
                (install-file "README" doc)
                (install-file "TODO" doc)
                (install-file "usertags" examples)
                (install-file "engines" examples))))
          (add-after 'install-doc 'wrap-programs
            (lambda* (#:key inputs #:allow-other-keys)
              ;; bm calls bm-title and bm-commit by name, so $output/bin
              ;; goes on the PATH as well as the runtime programs.
              (let ((path
                     (cons (string-append #$output "/bin")
                           (map (lambda (file)
                                  (dirname (search-input-file inputs file)))
                                '("bin/awk"
                                  "bin/fzf"
                                  "bin/dmenu"
                                  "bin/xclip"
                                  "bin/wl-copy"
                                  "bin/xdg-open"
                                  "bin/curl"
                                  "bin/jq"
                                  "bin/git")))))
                (for-each (lambda (program)
                            (wrap-program program
                              `("PATH" ":" prefix ,path)))
                          (find-files (string-append #$output "/bin")))))))))
    (inputs
     (list coreutils
           gawk
           ;; A menu is required and either will do; both are wrapped in, so
           ;; bm picks dmenu when there is a display and fzf otherwise.
           dmenu
           fzf
           ;; Clipboard.
           xclip
           wl-clipboard
           ;; Optional, but cheap and wrapped in so the tools just work:
           ;; curl (bm-title, bm-check), jq (bm-import of Chromium JSON
           ;; files), git (bm-commit), xdg-utils (opening URLs).
           curl
           jq
           git
           xdg-utils))
    (native-inputs
     (list shellcheck))
    (home-page "https://github.com/equwal/sbm")
    (synopsis "Bookmark manager in C and POSIX sh, driven by dmenu or fzf")
    (description
     "sbm keeps bookmarks in one tab separated file: URL, description, tags.
@command{bm} picks one with dmenu, or with fzf on a bare terminal, and then
opens it, copies it, edits it or deletes it.  Text that is no bookmark is
opened as an address or searched for on the web.

The rest are small filters that read and write bookmark lines:
@command{bm-import} turns a browser's bookmarks into bookmark lines,
@command{bm-check} reports dead links, @command{bm-html} writes a searchable
web page, @command{bm-migrate} converts the old file format,
@command{bm-title} prints a page's title and @command{bm-commit} keeps the
bookmark file's history in git.

bm, bm-migrate, bm-check and bm-html are C99; the rest is POSIX sh.")
    ;; Upstream has not chosen a licence yet and ships no LICENSE file.
    ;; Replace SBM_LICENSE_TBD with a variable from (guix licenses), for
    ;; example license:gpl3+. As written this is an unbound variable and
    ;; evaluation fails, which is what a placeholder should do.
    (license license:SBM_LICENSE_TBD)))

sbm
