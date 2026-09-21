$ErrorActionPreference = 'Stop'

$toolsDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

$scripts = @('bm', 'bm-migrate', 'bm-import', 'bm-check', 'bm-html', 'bm-title', 'bm-commit', 'bm-watch', 'bm-sync')

foreach ($s in $scripts) {
  $cmdPath = Join-Path $toolsDir "$s.cmd"
  Uninstall-BinFile -Name $s -Path $cmdPath
  Remove-Item -LiteralPath $cmdPath -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath (Join-Path $toolsDir $s) -Force -ErrorAction SilentlyContinue
}

foreach ($extra in @('README', 'usertags', 'engines')) {
  Remove-Item -LiteralPath (Join-Path $toolsDir $extra) -Force -ErrorAction SilentlyContinue
}

Remove-Item -LiteralPath (Join-Path $toolsDir 'staging') -Recurse -Force -ErrorAction SilentlyContinue

# The bookmark file is the user's data and is left alone. It is under
# ~/.local/share/sbm/ unless BOOKMARKS says otherwise.
Write-Host 'sbm: your bookmark file was not touched.'
