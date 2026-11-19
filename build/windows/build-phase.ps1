# DRAFT - not yet run on Windows. Native port of build-phase.sh:
# decompile each patched file from the game, apply the patch, compile
# with the CSDK resourcecompiler, stage, pack. PWD is the repo root;
# configuration arrives via $env:MODBOX_* (set by build.ps1).
$ErrorActionPreference = 'Stop'

$Game = $env:MODBOX_GAME
$Csdk = $env:MODBOX_CSDK
$S2v = $env:MODBOX_S2V
$Patches = $env:MODBOX_PATCHES -split ';'
$VpkName = $env:MODBOX_VPKNAME
$Result = $env:MODBOX_RESULT
$T = Join-Path ([System.IO.Path]::GetTempPath()) 'modroot'

function Invoke-Native([string]$Exe, [string[]]$Args, [string]$What) {
  & $Exe @Args
  if ($LASTEXITCODE -ne 0) { throw "$What failed (exit $LASTEXITCODE)" }
}
function Is-Raw([string]$Path) { return $Path -like '*.cfg' }
function Compiled-Name([string]$Path) {
  # panorama/foo.vxml -> panorama/foo.vxml_c (same sed as build-phase.sh)
  return [regex]::Replace($Path, '\.([a-z]*)$', '.v$1_c')
}
function Find-ByName([string]$Dir, [string]$Name) {
  $hit = Get-ChildItem -Path $Dir -Recurse -Filter $Name -File -ErrorAction SilentlyContinue |
    Select-Object -First 1
  if ($null -eq $hit) { return $null }
  return $hit.FullName
}

Remove-Item -Recurse -Force $T -ErrorAction SilentlyContinue
# Drop the junctions explicitly first: Remove-Item -Recurse must never
# follow them into the CSDK/game trees.
foreach ($j in @("$T/game/citadel/bin")) {
  $link = Get-Item $j -Force -ErrorAction SilentlyContinue
  if ($null -ne $link -and $link.LinkType -eq 'Junction') { $link.Delete() }
}
Remove-Item -Recurse -Force $T -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path "$T/game/citadel", "$T/game/core/panorama" | Out-Null
if (-not (Test-Path (Join-Path $Game 'citadel\gameinfo.gi'))) {
  throw "no game at $Game (set GAME_DIR=...)"
}
Copy-Item (Join-Path $Game 'citadel\gameinfo.gi') "$T/game/citadel/gameinfo.gi"
# Junction, not symlink: needs no privileges, and resourcecompiler
# resolves it like the Linux symlink in build-phase.sh.
New-Item -ItemType Junction -Path "$T/game/citadel/bin" `
  -Target (Join-Path $Csdk 'game\citadel\bin') | Out-Null
Copy-Item (Join-Path $Csdk 'game\core\panorama\panorama_config.txt') `
  "$T/game/core/panorama/panorama_config.txt"

# Every +++ b/ path across all patches, minus /dev/null (added files).
$AllTargets = $(foreach ($p in $Patches) {
  Select-String -Path $p -Pattern '^\+\+\+ b/' -AllMatches |
    ForEach-Object { $_.Line.Substring(6) }
}) | Where-Object { $_ -ne '/dev/null' } | Sort-Object -Unique
# Added files (--- /dev/null + +++ b/<path>): created by git apply,
# skipped at decompile time, same as build-phase.sh.
$NewFiles = $(foreach ($p in $Patches) {
  $lines = Get-Content $p
  for ($i = 0; $i -lt $lines.Count - 1; $i++) {
    if ($lines[$i] -eq '--- /dev/null' -and $lines[$i + 1] -match '^\+\+\+ b/(.+)$') {
      $Matches[1]
    }
  }
}) | Sort-Object -Unique

$Step0 = "$T/step-0"; $Fresh0 = "$T/fresh-0"
New-Item -ItemType Directory -Force -Path $Step0, $Fresh0 | Out-Null
$CitadelVpk = Join-Path $Game 'citadel\pak01_dir.vpk'
$CoreVpk = Join-Path $Game 'core\pak01_dir.vpk'
if (-not (Test-Path $CitadelVpk)) { throw "no input VPK at $CitadelVpk" }
foreach ($d in $AllTargets) {
  if ($NewFiles -contains $d) { Write-Host "+ new file $d (no decompile)"; continue }
  New-Item -ItemType Directory -Force -Path "$Step0/$(Split-Path $d -Parent)" | Out-Null
  if (Is-Raw $d) {
    # Raw files (no compiled _c form in the VPK, e.g. .cfg keybind files)
    # are extracted as-is and staged without resourcecompiler.
    Write-Host "+ extracting raw $d"
    Invoke-Native $S2v @('-i', $CitadelVpk, '-o', $Fresh0, '-f', $d) "extract of $d"
    $css = Find-ByName $Fresh0 (Split-Path $d -Leaf)
    if ($null -eq $css) {
      # Not in the citadel pack: try the core pack
      # (e.g. panorama/default_keybinds.cfg).
      Invoke-Native $S2v @('-i', $CoreVpk, '-o', $Fresh0, '-f', $d) "extract of $d"
      $css = Find-ByName $Fresh0 (Split-Path $d -Leaf)
    }
    if ($null -eq $css) { throw "extract produced no $d" }
    Copy-Item $css (Join-Path $Step0 $d)
    continue
  }
  $Target = Compiled-Name $d
  Write-Host "+ decompiling $Target"
  Invoke-Native $S2v @('-i', $CitadelVpk, '-d', '-o', $Fresh0, '-f', $Target) "decompile of $d ($Target)"
  $css = Find-ByName $Fresh0 (Split-Path $d -Leaf)
  if ($null -eq $css) { throw "decompile produced no $d" }
  Copy-Item $css (Join-Path $Step0 $d)
}

$n = 0
foreach ($p in $Patches) {
  $n++; $w = "$T/step-$n"
  New-Item -ItemType Directory -Force -Path $w | Out-Null
  # cp -r semantics: an empty previous step (all-new-file patch)
  # copies nothing and must not fail.
  if (Get-ChildItem "$T/step-$($n - 1)" -Force | Select-Object -First 1) {
    Copy-Item "$T/step-$($n - 1)/*" $w -Recurse -Force
  }
  $Targets = Select-String -Path $p -Pattern '^\+\+\+ b/' -AllMatches |
    ForEach-Object { $_.Line.Substring(6) } |
    Where-Object { $_ -ne '/dev/null' }
  if ($null -eq $Targets) { throw "$p has no diff paths" }
  # Real git apply (MinGit bootstrapped by build.ps1), same engine as build/nix.
  & $env:MODBOX_GIT -C $w apply $p
  if ($LASTEXITCODE -ne 0) {
    throw "$p does not apply - re-derive it (or it conflicts with an earlier patch)"
  }
  foreach ($d in $Targets) {
    if (Is-Raw $d) {
      Write-Host "+ staging raw $d (no compile)"
      $dest = "$T/stage/$d"
      New-Item -ItemType Directory -Force -Path (Split-Path $dest -Parent) | Out-Null
      Copy-Item "$w/$d" $dest
      continue
    }
    $Target = Compiled-Name $d
    $tb = Split-Path $Target -Leaf
    $content = "$T/content/citadel_addons/badge/$d"
    New-Item -ItemType Directory -Force -Path (Split-Path $content -Parent) | Out-Null
    Copy-Item "$w/$d" $content
    # Native resourcecompiler: no Wine, no dxvk, no zpath mangling.
    Invoke-Native (Join-Path $Csdk 'game\bin_cs2\win64\resourcecompiler.exe') `
      @('-v', '-f', '-game', "$T/game/citadel", $content) "compile of $d"
    $out = Find-ByName "$T/game" $tb
    if ($null -eq $out) { throw "compile produced no $tb" }
    $staged = "$T/stage/$Target"
    New-Item -ItemType Directory -Force -Path (Split-Path $staged -Parent) | Out-Null
    Copy-Item $out $staged
  }
}

# Normalize mtimes so the pack step below is deterministic:
# same patch plus same game build gives same bytes.
$epoch = [datetime]'1970-01-01T00:00:00Z'
Get-ChildItem -Path "$T/stage" -Recurse | ForEach-Object {
  $_.LastWriteTimeUtc = $epoch
}
# Pack with the same python vpk tool as the nix build, so all runners
# emit identical bytes. The interpreter is the pinned embeddable
# distribution bootstrapped by build.ps1 (never a system python:
# Win11 only ships a Store stub, and versions would drift).
# (CSDKCfgVPK.exe ships in the CSDK and would drop the bootstrap;
# its CLI flags are still unconfirmed, so it stays a testing-phase
# option, not the draft default.)
$vpkOut = Join-Path $T $VpkName
Invoke-Native $env:MODBOX_PYTHON @($env:MODBOX_VPKCLI, $vpkOut, '-c', "$T/stage") 'pack'

Remove-Item -Recurse -Force $Result -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $Result | Out-Null
if ($env:MODBOX_DEBUG -ne '0') {
  $dbg = Join-Path $Result 'debug'
  Copy-Item $Step0 (Join-Path $dbg 'step-0') -Recurse
  $n = 0
  foreach ($p in $Patches) {
    $n++
    Copy-Item "$T/step-$n" (Join-Path $dbg "step-$n") -Recurse
    Copy-Item $p (Join-Path $dbg "step-$n")
  }
  $n++
  Copy-Item "$T/stage" (Join-Path $dbg "step-$n") -Recurse
}
Copy-Item $vpkOut (Join-Path $Result $VpkName)
if ($env:MODBOX_RELEASE -ne '0') {
  # Compress-Archive timestamps are not normalized; the release zip is
  # a convenience, not a compared artifact. Prefer 7z when present.
  $zip = Join-Path $Result ($VpkName -replace '\.vpk$', '.zip')
  if (Get-Command 7z -ErrorAction SilentlyContinue) {
    Invoke-Native '7z' @('a', $zip, $vpkOut) 'release zip'
  } else {
    Compress-Archive -Path $vpkOut -DestinationPath $zip -Force
  }
}
