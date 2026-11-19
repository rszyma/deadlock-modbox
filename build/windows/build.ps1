#Requires -Version 5.1
<#
.SYNOPSIS
  Build a Deadlock VPK from patches in ./mods (native Windows, no Wine).
.DESCRIPTION
  DRAFT - not yet run on Windows. Mirrors build/nix/build.sh:
  with no mod names builds all patches, else only the named ones.

  Prerequisites on PATH: none. Everything is bootstrapped or pointed at:
  GAME_DIR/CSDK_PATH/SOURCE2VIEWER env (or same-named params); git (MinGit)
  plus Python and the vpk packer self-install into .tools/ on first run
  (pinned zips, hash-checked, no admin, no Store).
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File build/windows/build.ps1 remove-esc-menu-animations
#>
[CmdletBinding()]
param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$Mods,
  [string]$GameDir = $env:GAME_DIR,
  [string]$CsdkPath = $env:CSDK_PATH,
  [string]$Source2Viewer = $env:SOURCE2VIEWER
)
$ErrorActionPreference = 'Stop'
# Repo root without git: walk up until mods/ + build/ are both present.
$Root = (Get-Location).Path
while (-not ((Test-Path (Join-Path $Root 'mods')) -and (Test-Path (Join-Path $Root 'build')))) {
  $parent = Split-Path $Root -Parent
  if (-not $parent -or $parent -eq $Root) { throw 'not inside the modbox repo (no mods/ + build/ found upward)' }
  $Root = $parent
}
Set-Location $Root

if (-not $GameDir) {
  $GameDir = Join-Path ${env:ProgramFiles(x86)} 'Steam\steamapps\common\Deadlock\game'
}
if (-not (Test-Path (Join-Path $GameDir 'citadel\gameinfo.gi'))) {
  Write-Error "game dir not found: $GameDir (set GAME_DIR=... for a custom Steam library)"
}
foreach ($f in @('game\bin_cs2\win64\resourcecompiler.exe', 'game\citadel\bin',
                 'game\core\panorama\panorama_config.txt')) {
  if (-not (Test-Path (Join-Path $CsdkPath $f))) {
    Write-Error "CSDK_PATH looks wrong, missing $f (want an unpacked Reduced_CSDK_12)"
  }
}
# No PATH prereqs: git and Python arrive via Ensure-* below.
if (-not $Source2Viewer -or -not (Test-Path $Source2Viewer)) {
  Write-Error "Source2Viewer-CLI.exe not found (set SOURCE2VIEWER=... to the win-x64 build)"
}

if ($Mods.Count -eq 0) {
  $PatchFiles = Get-ChildItem mods/*.patch | ForEach-Object { $_.FullName }
  $ResultDir = 'result'
} else {
  $PatchFiles = foreach ($m in $Mods) {
    $p = Join-Path 'mods' (($m -replace '^\.', '') + '.patch')
    if (-not (Test-Path $p)) { Write-Error "no such mod: $m (see mods/)" }
    (Resolve-Path $p).Path
  }
  $ResultDir = 'result-' + ($Mods -join '+')
}

# Self-contained git (MinGit: git.exe plus a minimal shell, ~40 MB).
# The real git apply stays the patch engine per the spec; this just
# removes the Git-for-Windows install step. Same pin-and-hash pattern
# as the Python packer below.
function Ensure-Git {
  $exe = Join-Path (Get-Location) '.tools\mingit\cmd\git.exe'
  if (Test-Path $exe) { return $exe }
  $dl = Join-Path (Get-Location) '.tools\dl'
  New-Item -ItemType Directory -Force -Path $dl | Out-Null
  $zip = Join-Path $dl 'mingit.zip'
  $hash = '4a92850b6e917da4fd010669b614b55dccf5b0ec333a534cc4be4700dfefdafd'
  Invoke-WebRequest -Uri 'https://github.com/git-for-windows/git/releases/download/v2.56.1.windows.1/MinGit-2.56.1-64-bit.zip' `
    -OutFile $zip
  $actual = (Get-FileHash -Algorithm SHA256 -Path $zip).Hash.ToLower()
  if ($actual -ne $hash) { throw "hash mismatch for $zip" }
  Expand-Archive -Path $zip -DestinationPath (Join-Path (Get-Location) '.tools\mingit') -Force
  Remove-Item -Recurse -Force $dl
  return $exe
}
$env:MODBOX_GIT = Ensure-Git
# Self-contained packer: python.org embeddable zip (~11 MB, no install,
# no Store, no admin) plus the vpk sdist (pure stdlib, ~100 KB).
# Same packer as the nix build, so all runners emit identical bytes.
function Ensure-Packer {
  $tools = Join-Path (Get-Location) '.tools'
  $py = Join-Path $tools 'python\python.exe'
  $cli = Join-Path $tools 'vpk\vpk\cli.py'
  if ((Test-Path $py) -and (Test-Path $cli)) { return @($py, $cli) }
  $dl = Join-Path $tools 'dl'; New-Item -ItemType Directory -Force -Path $dl | Out-Null
  $pyZip = Join-Path $dl 'python-embed.zip'
  $pyHash = '9e35319bffedab8b36ad44d8f377cb4f1733bcec257a0b6d04d94f01486ddb38'
  $vpkTgz = Join-Path $dl 'vpk-1.4.0.tar.gz'
  $vpkHash = '32ce0a2ca74f29e6b6614dc6e56b7724181c7b011f4de6040a138d4d8fe97040'
  Invoke-WebRequest -Uri 'https://www.python.org/ftp/python/3.13.17/python-3.13.17-embed-amd64.zip' `
    -OutFile $pyZip
  Invoke-WebRequest -Uri 'https://files.pythonhosted.org/packages/70/d4/567a1c46a4c1efc646454868cfffa81e87760663cfddcc28dc9d273fb5ac/vpk-1.4.0.tar.gz' `
    -OutFile $vpkTgz
  foreach ($pair in @(@($pyZip, $pyHash), @($vpkTgz, $vpkHash))) {
    $actual = (Get-FileHash -Algorithm SHA256 -Path $pair[0]).Hash.ToLower()
    if ($actual -ne $pair[1]) { throw "hash mismatch for $($pair[0])" }
  }
  Expand-Archive -Path $pyZip -DestinationPath (Join-Path $tools 'python') -Force
  # Embeddable python ignores PYTHONPATH; register the vpk tree in
  # python313._pth instead (canonical embeddable-app procedure).
  $vpkDir = Join-Path $tools 'vpk'
  New-Item -ItemType Directory -Force -Path $vpkDir | Out-Null
  tar -xzf $vpkTgz -C $vpkDir --strip-components 1
  Add-Content (Join-Path $tools 'python\python313._pth') '..\vpk'
  Remove-Item -Recurse -Force $dl
  return @($py, $cli)
}
$packer = Ensure-Packer
$env:MODBOX_PYTHON = $packer[0]
$env:MODBOX_VPKCLI = $packer[1]
$env:MODBOX_GAME = $GameDir
$env:MODBOX_CSDK = (Resolve-Path $CsdkPath).Path
$env:MODBOX_S2V = (Resolve-Path $Source2Viewer).Path
$env:MODBOX_PATCHES = $PatchFiles -join ';'
$env:MODBOX_VPKNAME = 'pak75_dir.vpk'
$env:MODBOX_RESULT = (Join-Path (Get-Location) $ResultDir)

& "$PSScriptRoot/build-phase.ps1"
$Vpk = Join-Path $env:MODBOX_RESULT "$env:MODBOX_VPKNAME"
Write-Host "VPK: $Vpk"
