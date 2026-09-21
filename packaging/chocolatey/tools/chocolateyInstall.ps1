$ErrorActionPreference = 'Stop'

$packageName = 'sbm'
$version     = '0.3'
$toolsDir    = Split-Path -Parent $MyInvocation.MyCommand.Definition
$stage       = Join-Path $toolsDir 'staging'

# What Makefile's TOOLS installs.
$scripts = @('bm', 'bm-migrate', 'bm-import', 'bm-check', 'bm-html', 'bm-title', 'bm-commit')

# ---------------------------------------------------------------------------
# Fetch and unpack.
#
# GitHub serves a tag as .tar.gz. 7zip needs two passes for that: .tar.gz to
# .tar, then .tar to the tree. Nothing is embedded in this package, because no
# licence has been chosen upstream yet.
# ---------------------------------------------------------------------------

$packageArgs = @{
  packageName   = $packageName
  unzipLocation = $stage
  url           = "https://github.com/equwal/sbm/archive/refs/tags/v$version.tar.gz"
  # No release tag exists yet, so there is nothing to hash. Replace
  # SBM_SHA256_TBD with the sha256 of the tarball once v0.3 is tagged:
  #   Get-FileHash .\v0.3.tar.gz -Algorithm SHA256
  checksum      = 'SBM_SHA256_TBD'
  checksumType  = 'sha256'
}

Install-ChocolateyZipPackage @packageArgs

$tar = Get-ChildItem -Path $stage -Filter '*.tar' -File | Select-Object -First 1
if (-not $tar) {
  throw "sbm: no .tar found in $stage after unpacking the release archive."
}
Get-ChocolateyUnzip -FileFullPath $tar.FullName -Destination $stage -PackageName $packageName
Remove-Item -LiteralPath $tar.FullName -Force

$src = Join-Path $stage "$packageName-$version"
if (-not (Test-Path -LiteralPath $src)) {
  # A -git style archive, or a renamed top directory: take the only one there.
  $only = Get-ChildItem -Path $stage -Directory | Select-Object -First 1
  if (-not $only) { throw "sbm: the release archive did not unpack into a directory." }
  $src = $only.FullName
}

foreach ($s in $scripts) {
  $from = Join-Path $src $s
  if (-not (Test-Path -LiteralPath $from)) { throw "sbm: $s is missing from the release archive." }
  Copy-Item -LiteralPath $from -Destination (Join-Path $toolsDir $s) -Force
}
foreach ($extra in @('README', 'usertags', 'engines')) {
  $from = Join-Path $src $extra
  if (Test-Path -LiteralPath $from) {
    Copy-Item -LiteralPath $from -Destination (Join-Path $toolsDir $extra) -Force
  }
}
Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue

# ---------------------------------------------------------------------------
# Find a POSIX sh. Git for Windows ships one; the package depends on git for
# exactly that reason. Look in several places rather than one hardcoded path,
# because Git installs per machine, per user, 32 bit, and through Chocolatey.
# ---------------------------------------------------------------------------

function Get-PosixSh {
  $candidates = New-Object 'System.Collections.Generic.List[string]'

  $gitCmd = Get-Command 'git.exe' -ErrorAction SilentlyContinue
  if ($gitCmd) {
    # ...\Git\cmd\git.exe and ...\Git\bin\git.exe both give ...\Git here.
    $gitRoot = Split-Path -Parent (Split-Path -Parent $gitCmd.Source)
    $candidates.Add((Join-Path $gitRoot 'bin\sh.exe'))
    $candidates.Add((Join-Path $gitRoot 'usr\bin\sh.exe'))
  }

  $keys = @(
    'HKLM:\SOFTWARE\GitForWindows',
    'HKLM:\SOFTWARE\WOW6432Node\GitForWindows',
    'HKCU:\SOFTWARE\GitForWindows'
  )
  foreach ($key in $keys) {
    try {
      $installPath = (Get-ItemProperty -Path $key -Name 'InstallPath' -ErrorAction Stop).InstallPath
      if ($installPath) {
        $candidates.Add((Join-Path $installPath 'bin\sh.exe'))
        $candidates.Add((Join-Path $installPath 'usr\bin\sh.exe'))
      }
    } catch {
      # No such key on this machine.
    }
  }

  $roots = @(
    $env:ProgramFiles,
    ${env:ProgramFiles(x86)},
    $env:ProgramW6432,
    $(if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'Programs' }),
    $(if ($env:ChocolateyInstall) { Join-Path $env:ChocolateyInstall 'lib\git.install\tools' })
  )
  foreach ($root in $roots) {
    if ($root) {
      $candidates.Add((Join-Path $root 'Git\bin\sh.exe'))
      $candidates.Add((Join-Path $root 'Git\usr\bin\sh.exe'))
    }
  }

  $shCmd = Get-Command 'sh.exe' -ErrorAction SilentlyContinue
  if ($shCmd) { $candidates.Add($shCmd.Source) }

  foreach ($candidate in $candidates) {
    if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) { return $candidate }
  }
  return $null
}

$sh = Get-PosixSh
if (-not $sh) {
  throw @'
sbm: no POSIX sh found.

sbm is POSIX shell and needs one to run. Git for Windows ships sh.exe and is
a dependency of this package:

    choco install git

If Git is installed somewhere unusual, sbm still works: put that sh.exe on
PATH and reinstall this package.
'@
}
Write-Host "sbm: using $sh"

# ---------------------------------------------------------------------------
# Generate a .cmd per script and register it on PATH.
#
# The sh path found above is baked in, with a fall back to whatever sh.exe is
# on PATH, so moving or upgrading Git does not break the shims outright.
# ---------------------------------------------------------------------------

foreach ($s in $scripts) {
  $cmdPath = Join-Path $toolsDir "$s.cmd"
  $body = @"
@echo off
rem Generated by the sbm Chocolatey package. Do not edit: reinstalling
rem the package rewrites this file.
setlocal
if not defined SBM_COPY set "SBM_COPY=clip"
if not defined SBM_PASTE set "SBM_PASTE=powershell -NoProfile -Command Get-Clipboard"
set "SBM_SH=$sh"
if not exist "%SBM_SH%" set "SBM_SH=sh.exe"
"%SBM_SH%" "%~dp0$s" %*
"@
  Set-Content -LiteralPath $cmdPath -Value $body -Encoding ASCII
  Install-BinFile -Name $s -Path $cmdPath
}

Write-Host @'
sbm is installed. On Windows:

  * The menu is fzf. dmenu is an X11 program and is not available here.
  * SBM_COPY and SBM_PASTE default to clip and Get-Clipboard.
  * Set an opener yourself, for example:
      setx SBM_OPEN "powershell -NoProfile -Command Start-Process"
  * Example tag and engine files are in this package's tools directory.
    Copy them to ~/.local/share/sbm/ (the HOME that Git Bash uses).
'@
