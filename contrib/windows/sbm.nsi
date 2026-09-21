; sbm.nsi: the Windows installer of sbm. contrib/windows/build-installer.sh
; runs makensis on this file.
;
; The installer needs Cygwin with mintty. It puts bm and the bm-* tools in
; /usr/local/bin, fzf.exe in /usr/local/libexec/sbm, and the settings in
; /etc/profile.d/sbm.sh. It makes a desktop shortcut and a Start menu entry
; that open bm in a mintty window. The key of the desktop shortcut is
; Ctrl+Alt+Shift+F24. Almost no keyboard has an F24 key, so keyboard firmware
; can use this key combination without conflicts. Only one shortcut has the
; key: when two shortcuts have the same key, Explorer can lose the key.
;
; A Startup entry runs bm-watch in a hidden mintty at each login. bm-watch
; brings the bookmarks of the Chromium browsers into bm, and then the new
; bookmarks as you add them. The installer also starts bm-watch at once.
;
; The uninstaller stops bm-watch and removes these files. It keeps the
; bookmarks of the user.

Unicode true
ManifestDPIAware true
!include LogicLib.nsh

!ifndef VERSION
  !error "Give the version, for example -DVERSION=0.3"
!endif
!ifndef VIVERSION
  !error "Give the version in four numbers, for example -DVIVERSION=0.3.0.0"
!endif
!ifndef SRC
  !error "Give the directory with the files to install, with -DSRC=dir"
!endif
!ifndef OUTFILE
  !error "Give the name of the installer, with -DOUTFILE=file"
!endif

!define UNINSTKEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\sbm"
!define MINTTYARGS "--class sbm -t sbm -s 120,32 -p center -o ConfirmExit=no -o Scrollbar=none /bin/bash -lc bm"
!define WATCHARGS '--class sbm-watch -w hide /bin/bash -lc "exec bm-watch brave chrome chromium edge vivaldi"'

Name "sbm ${VERSION}"
OutFile "${OUTFILE}"
RequestExecutionLevel admin
ShowInstDetails show
ShowUninstDetails show

VIProductVersion "${VIVERSION}"
VIAddVersionKey "ProductName" "sbm"
VIAddVersionKey "ProductVersion" "${VERSION}"
VIAddVersionKey "FileVersion" "${VERSION}"
VIAddVersionKey "FileDescription" "sbm ${VERSION} installer"
VIAddVersionKey "LegalCopyright" "Spenser Truex"

Var Cygwin

Page instfiles
UninstPage uninstConfirm
UninstPage instfiles

Function .onInit
  ; Cygwin setup is a 64-bit program. It writes to the 64-bit registry.
  SetRegView 64
  ReadRegStr $Cygwin HKLM "Software\Cygwin\setup" "rootdir"
  ${If} $Cygwin == ""
    ReadRegStr $Cygwin HKCU "Software\Cygwin\setup" "rootdir"
  ${EndIf}
  ${IfNot} ${FileExists} "$Cygwin\bin\mintty.exe"
    MessageBox MB_ICONSTOP "sbm needs Cygwin with mintty.$\r$\nInstall Cygwin from https://cygwin.com, then start this installer again."
    Abort
  ${EndIf}
FunctionEnd

Section
  ; An earlier version can run bm-watch. Stop it before its files change.
  ${If} ${FileExists} "$Cygwin\usr\local\libexec\sbm\sbm-setup"
    nsExec::ExecToLog '"$Cygwin\bin\sh.exe" /usr/local/libexec/sbm/sbm-setup stop'
    Pop $0
  ${EndIf}

  SetOutPath "$Cygwin\usr\local\bin"
  File "${SRC}\bin\bm"
  File "${SRC}\bin\bm-check"
  File "${SRC}\bin\bm-commit"
  File "${SRC}\bin\bm-html"
  File "${SRC}\bin\bm-import"
  File "${SRC}\bin\bm-migrate"
  File "${SRC}\bin\bm-title"
  File "${SRC}\bin\bm-watch"
  File "${SRC}\bin\fzf"
  SetOutPath "$Cygwin\usr\local\libexec\sbm"
  File "${SRC}\libexec\fzf.exe"
  File "${SRC}\libexec\fzf-LICENSE.txt"
  File "${SRC}\libexec\sbm-setup"
  SetOutPath "$Cygwin\usr\local\share\sbm"
  File "${SRC}\share\engines"
  File "${SRC}\share\usertags"
  SetOutPath "$Cygwin\etc\profile.d"
  File "${SRC}\etc\sbm.sh"

  ; Cygwin does not see an execute permission on files that a Windows
  ; program makes. Cygwin chmod sets it.
  nsExec::ExecToLog '"$Cygwin\bin\chmod.exe" 755 /usr/local/bin/bm /usr/local/bin/bm-check /usr/local/bin/bm-commit /usr/local/bin/bm-html /usr/local/bin/bm-import /usr/local/bin/bm-migrate /usr/local/bin/bm-title /usr/local/bin/bm-watch /usr/local/bin/fzf /usr/local/libexec/sbm/fzf.exe'
  Pop $0
  ${If} $0 != 0
    Abort "chmod failed with exit status $0"
  ${EndIf}

  nsExec::ExecToLog '"$Cygwin\bin\sh.exe" /usr/local/libexec/sbm/sbm-setup data'
  Pop $0
  ${If} $0 != 0
    Abort "sbm-setup failed with exit status $0"
  ${EndIf}

  ; bm-import reads the bookmarks of a browser with jq.
  ${IfNot} ${FileExists} "$Cygwin\bin\jq.exe"
    MessageBox MB_ICONEXCLAMATION|MB_OK "The browser import needs jq.$\r$\nInstall the jq package with Cygwin setup." /SD IDOK
  ${EndIf}

  WriteUninstaller "$Cygwin\usr\local\libexec\sbm\uninstall.exe"

  SetShellVarContext current
  CreateShortcut /NoWorkingDir "$DESKTOP\sbm.lnk" "$Cygwin\bin\mintty.exe" \
    "${MINTTYARGS}" "$Cygwin\bin\mintty.exe" 0 SW_SHOWNORMAL \
    ALT|CONTROL|SHIFT|F24 "sbm: bookmarks in fzf"
  CreateShortcut /NoWorkingDir "$SMPROGRAMS\sbm.lnk" "$Cygwin\bin\mintty.exe" \
    "${MINTTYARGS}" "$Cygwin\bin\mintty.exe" 0 SW_SHOWNORMAL "" \
    "sbm: bookmarks in fzf"
  CreateShortcut /NoWorkingDir "$SMSTARTUP\sbm-watch.lnk" "$Cygwin\bin\mintty.exe" \
    '${WATCHARGS}' "$Cygwin\bin\mintty.exe" 0 SW_SHOWMINIMIZED "" \
    "sbm: bring new browser bookmarks into bm"

  ; Start bm-watch now. Explorer starts it as the user, not as the
  ; administrator that runs this installer.
  Exec '"$WINDIR\explorer.exe" "$SMSTARTUP\sbm-watch.lnk"'

  WriteRegStr HKLM "${UNINSTKEY}" "DisplayName" "sbm"
  WriteRegStr HKLM "${UNINSTKEY}" "DisplayVersion" "${VERSION}"
  WriteRegStr HKLM "${UNINSTKEY}" "Publisher" "Spenser Truex"
  WriteRegStr HKLM "${UNINSTKEY}" "URLInfoAbout" "https://github.com/equwal/sbm"
  WriteRegStr HKLM "${UNINSTKEY}" "InstallLocation" "$Cygwin"
  WriteRegStr HKLM "${UNINSTKEY}" "UninstallString" '"$Cygwin\usr\local\libexec\sbm\uninstall.exe"'
  WriteRegDWORD HKLM "${UNINSTKEY}" "NoModify" 1
  WriteRegDWORD HKLM "${UNINSTKEY}" "NoRepair" 1
SectionEnd

Function un.onInit
  SetRegView 64
  ReadRegStr $Cygwin HKLM "${UNINSTKEY}" "InstallLocation"
  ${IfNot} ${FileExists} "$Cygwin\bin\mintty.exe"
    MessageBox MB_ICONSTOP "The registry does not give the Cygwin directory of sbm."
    Abort
  ${EndIf}
FunctionEnd

Section Uninstall
  nsExec::ExecToLog '"$Cygwin\bin\sh.exe" /usr/local/libexec/sbm/sbm-setup stop'
  Pop $0

  Delete "$Cygwin\usr\local\bin\bm"
  Delete "$Cygwin\usr\local\bin\bm-check"
  Delete "$Cygwin\usr\local\bin\bm-commit"
  Delete "$Cygwin\usr\local\bin\bm-html"
  Delete "$Cygwin\usr\local\bin\bm-import"
  Delete "$Cygwin\usr\local\bin\bm-migrate"
  Delete "$Cygwin\usr\local\bin\bm-title"
  Delete "$Cygwin\usr\local\bin\bm-watch"
  Delete "$Cygwin\usr\local\bin\fzf"
  Delete "$Cygwin\usr\local\libexec\sbm\fzf.exe"
  Delete "$Cygwin\usr\local\libexec\sbm\fzf-LICENSE.txt"
  Delete "$Cygwin\usr\local\libexec\sbm\sbm-setup"
  Delete "$Cygwin\usr\local\libexec\sbm\uninstall.exe"
  RMDir "$Cygwin\usr\local\libexec\sbm"
  Delete "$Cygwin\usr\local\share\sbm\engines"
  Delete "$Cygwin\usr\local\share\sbm\usertags"
  RMDir "$Cygwin\usr\local\share\sbm"
  Delete "$Cygwin\etc\profile.d\sbm.sh"
  SetShellVarContext current
  Delete "$DESKTOP\sbm.lnk"
  Delete "$SMPROGRAMS\sbm.lnk"
  Delete "$SMSTARTUP\sbm-watch.lnk"
  DeleteRegKey HKLM "${UNINSTKEY}"
SectionEnd
