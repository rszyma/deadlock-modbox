#!/usr/bin/env bash
# modbox build phase: decompile each patched file from the mounted game,
# apply the patch, compile, stage, pack. Runs inside the nix sandbox;
# GAME_MOUNT, CSDK_DIR, TMPDIR come from the derivation. PWD is the repo.
set -euo pipefail
zpath() { echo "Z:${1//\//\\}"; }
T=$TMPDIR/modroot
mkdir -p "$T/game/citadel" "$T/game/core/panorama"
[ -f "$GAME_MOUNT/citadel/gameinfo.gi" ] \
  || { echo "no game mounted at $GAME_MOUNT (see README)" >&2; exit 1; }
cp "$GAME_MOUNT/citadel/gameinfo.gi" "$T/game/citadel/gameinfo.gi"
ln -s "$CSDK_DIR/game/citadel/bin" "$T/game/citadel/bin"
cp "$CSDK_DIR/game/core/panorama/panorama_config.txt" \
  "$T/game/core/panorama/panorama_config.txt"
export WINEPREFIX="$T/wineprefix"
export DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1
N=0
for P in $PATCHES; do
  N=$((N + 1)); W="$T/work-$N"
  TARGETS=$(grep '^--- a/' "$P" | cut -d/ -f2-)
  [ -n "$TARGETS" ] || { echo "$P has no diff paths" >&2; exit 1; }
  for D in $TARGETS; do
    TARGET=$(echo "$D" | sed 's|\.\([a-z]*\)$|.v\1_c|')
    mkdir -p "$W/$(dirname "$D")"
    Source2Viewer-CLI \
      -i "$GAME_MOUNT/citadel/pak01_dir.vpk" -d -o "$T/fresh-$N" \
      -f "$TARGET" >/dev/null 2>&1
    CSS=$(find "$T/fresh-$N" -name "$(basename "$D")" | head -n 1)
    [ -n "$CSS" ] || { echo "decompile produced no $D" >&2; exit 1; }
    cp "$CSS" "$W/$D"
  done
  git -C "$W" apply "$PWD/$P" \
    || { echo "$P does not apply - re-derive it" >&2; exit 1; }
  for D in $TARGETS; do
    TARGET=$(echo "$D" | sed 's|\.\([a-z]*\)$|.v\1_c|')
    TB=$(basename "$TARGET")
    mkdir -p "$T/content/citadel_addons/badge/$(dirname "$D")"
    cp "$W/$D" "$T/content/citadel_addons/badge/$D"
    (cd "$T/game" && deadlock-resourcecompiler -v -f \
      -game "$(zpath "$T/game/citadel")" \
      "$(zpath "$T/content/citadel_addons/badge/$D")")
    OUT=$(find "$T/game" -name "$TB" | head -n 1)
    [ -n "$OUT" ] || { echo "compile produced no $TB" >&2; exit 1; }
    mkdir -p "$T/stage/$(dirname "$TARGET")"
    cp "$OUT" "$T/stage/$TARGET"
  done
done
vpk "$T/$VPKNAME" -c "$T/stage"
