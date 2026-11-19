#!/usr/bin/env bash
# Trim the CSDK down to the files a Panorama build reads.
# Full CSDK is ~6 GB unpacked. A UI compile runs one tool
# (bin_cs2/win64/resourcecompiler.exe) plus data files.
# This script finds the true set: trace, repack, verify.
#
# Static map (uncompressed, from the zip):
#   game/citadel        1994 MB  game content, build never reads it
#   game/bin            731 MB   wrong flavor, build never reads it
#   game/bin_server     713 MB   wrong flavor, build never reads it
#   game/bin_tools      713 MB   wrong flavor, build never reads it
#   game/bin_cs2        656 MB   only this flavor runs
#   game/core           632 MB   only panorama_config.txt is copied
#   content/*           195 MB   examples, build never reads them
# Inside bin_cs2 the bulk is per-tool DLLs (phonon, v8, hammer,
# modeldoc). The trace shows which ones resourcecompiler loads.
#
# Subcommands (run in `nix develop`, game installed):
#   trace   run one Panorama compile under strace, list CSDK reads
#   repack  copy the listed files into a minimal tree
#   verify  compare two stage trees file by file (sha256)
#   report  print full vs trim sizes
#
# Example loop:
#   ./nix-toolchain/deadlock-trim-csdk/trim-csdk.sh trace --game "$HOME/.steam/.../Deadlock/game" \
#     --csdk /nix/store/...-Reduced_CSDK_12 --out /tmp/trim
#   ./nix-toolchain/deadlock-trim-csdk/trim-csdk.sh repack --csdk <same> --list /tmp/trim/files.txt \
#     --out /tmp/trim/min
#   CSDK_PATH=/tmp/trim/min ./build/nix/build.sh remove-esc-menu-animations
#   # compare result VPK against a full-CSDK build, then ship min/
set -euo pipefail

cmd="${1:-}"; shift || true
GAME=""; CSDK=""; OUT=""; LIST=""; REF=""; NEW=""
while [ $# -gt 0 ]; do
  case "$1" in
    --game) GAME="$2"; shift 2;;
    --csdk) CSDK="$2"; shift 2;;
    --out) OUT="$2"; shift 2;;
    --list) LIST="$2"; shift 2;;
    --ref) REF="$2"; shift 2;;
    --new) NEW="$2"; shift 2;;
    *) echo "unknown arg: $1" >&2; exit 1;;
  esac
done

need() { command -v "$1" >/dev/null 2>&1 || { echo "need $1" >&2; exit 1; }; }

case "$cmd" in
trace)
  [ -n "$GAME" ] && [ -n "$CSDK" ] && [ -n "$OUT" ] || {
    echo "usage: trim-csdk.sh trace --game DIR --csdk DIR --out DIR" >&2; exit 1; }
  OUT="$(realpath -m "$OUT")"
  if ! command -v strace >/dev/null 2>&1; then
    echo "need strace (try: nix run nixpkgs#strace -- --version)" >&2; exit 1
  fi
  need Source2Viewer-CLI
  # Wine comes from env (nix build) or from the dev wrapper.
  # Env wins when set, so one script serves shell and sandbox.
  if [ -z "${WINEBIN:-}" ]; then
    WRAP="$(command -v deadlock-resourcecompiler)" \
      || { echo "run in nix develop or set WINEBIN" >&2; exit 1; }
    WINEBIN="$(grep -o '/nix/store/[^ ]*/bin/wine' "$WRAP" | head -n 1)"
    DXVK_TGZ="${DXVK_TGZ:-$(grep -o '/nix/store/[^ ]*dxvk[^ ]*\.tar\.gz' "$WRAP" | head -n 1)}"
    VKICD_JSON="${VKICD_JSON:-$(grep -o '/nix/store/[^"]*lvp_icd[^"]*\.json' "$WRAP" | head -n 1)}"
    VKLIB_DIR="${VKLIB_DIR:-$(grep -o '/nix/store/[^"]*vulkan-loader[^"]*/lib' "$WRAP" | head -n 1)}"
  fi
  [ -x "$WINEBIN" ] || { echo "no wine found" >&2; exit 1; }
  export DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1
  [ -d "$GAME/citadel" ] || { echo "no game at $GAME" >&2; exit 1; }
  CSDK="$(realpath "$CSDK")"
  mkdir -p "$OUT"
  T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
  mkdir -p "$T/game/citadel" "$T/game/core/panorama"
  cp "$GAME/citadel/gameinfo.gi" "$T/game/citadel/gameinfo.gi"
  ln -s "$CSDK/game/citadel/bin" "$T/game/citadel/bin"
  cp "$CSDK/game/core/panorama/panorama_config.txt" \
    "$T/game/core/panorama/panorama_config.txt"
  export WINEPREFIX="$T/wineprefix" WINEDEBUG=-all
  export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-d3d11,dxgi=n}"
  export VK_ICD_FILENAMES="${VK_ICD_FILENAMES:-$VKICD_JSON}"
  export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:+$LD_LIBRARY_PATH:}$VKLIB_DIR"
  if [ ! -f "$WINEPREFIX/drive_c/windows/system32/dxgi.dll" ]; then
    mkdir -p "$WINEPREFIX/drive_c/windows/system32"
    tar -xzf "$DXVK_TGZ" -C "$WINEPREFIX/drive_c/windows/system32" \
      --strip-components=2 dxvk-2.7.1/x64/d3d11.dll dxvk-2.7.1/x64/dxgi.dll
  fi
  unset DISPLAY
  zpath() { echo "Z:${1//\//\\}"; }
  # Decompile Panorama sources, then compile one file back.
  # hud_escape_menu exercises layout plus style includes.
  # With an existing -o folder, S2V writes the file at its VPK path (cleartext suffix).
  mkdir -p "$T/fresh"
  Source2Viewer-CLI -i "$GAME/citadel/pak01_dir.vpk" -d \
    -o "$T/fresh" -f panorama/layout/hud_escape_menu.vxml_c
  SRC="$T/fresh/panorama/layout/hud_escape_menu.xml"
  [ -f "$SRC" ] || { echo "decompile gave no file" >&2; exit 1; }
  mkdir -p "$T/content/citadel_addons/badge/panorama/layout"
  cp "$SRC" "$T/content/citadel_addons/badge/panorama/layout/hud_escape_menu.xml"
  (cd "$T/game" && strace -f -e trace=%file -o "$OUT/trace.log" \
    "$WINEBIN" "$CSDK/game/bin_cs2/win64/resourcecompiler.exe" \
    -v -f -game "$(zpath "$T/game/citadel")" \
    "$(zpath "$T/content/citadel_addons/badge/panorama/layout/hud_escape_menu.xml")")
  # Keep paths under CSDK with a good return code.
  # Drop ENOENT probes: the good fallback is logged too.
  # Keep files only: dir probes ride along in the log.
  grep -o '"[^"]*"' "$OUT/trace.log" | tr -d '"' | grep "^$CSDK/" \
    | sort -u > "$OUT/files.all.txt"
  grep -v 'ENOENT' "$OUT/trace.log" | grep -o '"[^"]*"' | tr -d '"' \
    | grep "^$CSDK/" | sort -u | while IFS= read -r f; do
    [ -f "$f" ] && echo "$f"
  done > "$OUT/files.txt"
  # The tool plus its config ride along even with no trace line.
  for f in game/bin_cs2/win64/resourcecompiler.exe \
           game/core/panorama/panorama_config.txt; do
    grep -qxF "$CSDK/$f" "$OUT/files.txt" || echo "$CSDK/$f" >> "$OUT/files.txt"
  done
  sort -u -o "$OUT/files.txt" "$OUT/files.txt"
  echo "reads: $(wc -l < "$OUT/files.all.txt") total, $(wc -l < "$OUT/files.txt") good"
  echo "list: $OUT/files.txt"
  ;;
repack)
  [ -n "$CSDK" ] && [ -n "$LIST" ] && [ -n "$OUT" ] || {
    echo "usage: trim-csdk.sh repack --csdk DIR --list FILE --out DIR" >&2; exit 1; }
  OUT="$(realpath -m "$OUT")"
  CSDK="$(realpath "$CSDK")"
  mkdir -p "$OUT"
  # rsync needs names relative to the CSDK root: strip the prefix.
  sed "s|^$CSDK/||" "$LIST" | (cd "$CSDK" && rsync -a --files-from=- . "$OUT")
  echo "trim tree: $OUT ($(du -sh "$OUT" | cut -f1))"
  ;;
verify)
  [ -n "$REF" ] && [ -n "$NEW" ] || {
    echo "usage: trim-csdk.sh verify --ref DIR --new DIR" >&2; exit 1; }
  SUMS="$(mktemp)"; trap 'rm -f "$SUMS"' EXIT
  diff -r "$REF" "$NEW" \
    && (cd "$REF" && find . -type f | sort | xargs sha256sum) > "$SUMS" \
    && (cd "$NEW" && sha256sum -c "$SUMS") \
    && echo "TREES MATCH"
  ;;
report)
  [ -n "$CSDK" ] && [ -n "$LIST" ] || {
    echo "usage: trim-csdk.sh report --csdk DIR --list FILE" >&2; exit 1; }
  echo "full CSDK: $(du -sh "$CSDK" | cut -f1)"
  echo "listed files: $(wc -l < "$LIST")"
  echo "listed size: $(sed "s|^$(realpath "$CSDK")/||" "$LIST" | (cd "$CSDK" && xargs du -sc 2>/dev/null | tail -1))"
  sed "s|^$(realpath "$CSDK")/||" "$LIST" | cut -d/ -f1-2 | sort | uniq -c | sort -rn
  ;;
*)
  echo "usage: trim-csdk.sh {trace|repack|verify|report} ..." >&2; exit 1;;
esac
