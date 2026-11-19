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
# Raw files (no compiled _c form in the VPK, e.g. .cfg keybind files)
# are extracted as-is and staged without resourcecompiler.
is_raw() { case "$1" in *.cfg) return 0;; *) return 1;; esac; }
N=0
# Cumulative steps: step-0 holds fresh decompiles of every target across
# all patches; step-N is a copy of step-(N-1) with patch N applied, so
# same-file patches compose with no bookkeeping. Overlapping hunks fail
# loudly at git apply below. Patches may also add new files
# (--- /dev/null + +++ b/<path>, e.g. a new panorama script): those are
# skipped at decompile time and created by git apply instead.
# NOTE: the `|| true`s below are load-bearing: with `set -euo pipefail`
# a grep with no matches would otherwise kill the build silently.
ALLTARGETS=$(for P in $PATCHES; do grep '^+++ b/' "$P" || true; done | sed 's|^+++ b/||' | grep -v '^/dev/null$' | sort -u || true)
NEWFILES=$(for P in $PATCHES; do grep -A1 '^--- /dev/null' "$P" || true; done | grep '^+++ b/' | sed 's|^+++ b/||' | sort -u || true)
mkdir -p "$T/step-0" "$T/fresh-0"
[ -f "$GAME_MOUNT/citadel/pak01_dir.vpk" ] \
  || { echo "no input VPK at $GAME_MOUNT/citadel/pak01_dir.vpk (check /tmp/deadlock mount)" >&2; ls -l "$GAME_MOUNT/citadel" >&2; exit 1; }
for D in $ALLTARGETS; do
  # Line-based match: $NEWFILES is newline-separated, so a space-wrapped
  # case pattern would miss every entry but the last.
  if [ -n "$NEWFILES" ] && printf '%s\n' "$NEWFILES" | grep -qxF "$D"; then
    echo "+ new file $D (no decompile)" >&2
    continue
  fi
  if is_raw "$D"; then
    echo "+ extracting raw $D" >&2
    if ! Source2Viewer-CLI \
      -i "$GAME_MOUNT/citadel/pak01_dir.vpk" -o "$T/fresh-0" \
      -f "$D"; then
      echo "extract command failed for $D" >&2; exit 1
    fi
    CSS=$(find "$T/fresh-0" -name "$(basename "$D")" | head -n 1)
    if [ -z "$CSS" ]; then
      # Not in the citadel pack: try the core pack
      # (e.g. panorama/default_keybinds.cfg).
      if ! Source2Viewer-CLI \
        -i "$GAME_MOUNT/core/pak01_dir.vpk" -o "$T/fresh-0" \
        -f "$D"; then
        echo "extract command failed for $D" >&2; exit 1
      fi
      CSS=$(find "$T/fresh-0" -name "$(basename "$D")" | head -n 1)
    fi
    [ -n "$CSS" ] || { echo "extract produced no $D" >&2; exit 1; }
    mkdir -p "$T/step-0/$(dirname "$D")"
    cp "$CSS" "$T/step-0/$D"
    continue
  fi
  TARGET=$(echo "$D" | sed 's|\.\([a-z]*\)$|.v\1_c|')
  mkdir -p "$T/step-0/$(dirname "$D")"
  echo "+ decompiling $TARGET" >&2
  if ! Source2Viewer-CLI \
    -i "$GAME_MOUNT/citadel/pak01_dir.vpk" -d -o "$T/fresh-0" \
    -f "$TARGET"; then
    echo "decompile command failed for $D ($TARGET)" >&2; exit 1
  fi
  CSS=$(find "$T/fresh-0" -name "$(basename "$D")" | head -n 1)
  [ -n "$CSS" ] || { echo "decompile produced no $D" >&2; exit 1; }
  cp "$CSS" "$T/step-0/$D"
done
for P in $PATCHES; do
  N=$((N + 1)); W="$T/step-$N"
  mkdir -p "$W"; cp -r "$T/step-$((N - 1))/." "$W/"
  TARGETS=$(grep '^+++ b/' "$P" | sed 's|^+++ b/||' | grep -v '^/dev/null$' || true)
  [ -n "$TARGETS" ] || { echo "$P has no diff paths" >&2; exit 1; }
  git -C "$W" apply "$PWD/$P" \
    || { echo "$P does not apply - re-derive it (or it conflicts with an earlier patch)" >&2; exit 1; }
  for D in $TARGETS; do
    if is_raw "$D"; then
      echo "+ staging raw $D (no compile)" >&2
      mkdir -p "$T/stage/$(dirname "$D")"
      cp "$W/$D" "$T/stage/$D"
      continue
    fi
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
# Debug: ship the patched cleartext sources plus the compiled outputs
# alongside the vpk, so a build can be inspected without rebuilding
# (result*/debug after `nix build -o`). Skipped unless $DEBUG is set.
if [ -n "${DEBUG:-}" ]; then
mkdir -p "$T/debug"
cp -r "$T/step-0" "$T/debug/step-0"
N=0
# Steps are continuous: step-0 fresh, step-1..N patched states (each with
# the patch file that produced it), final step-N+1 the staged build result.
for P in $PATCHES; do
  N=$((N + 1))
  cp -r "$T/step-$N" "$T/debug/step-$N"
  cp "$PWD/$P" "$T/debug/step-$N/"
done
N=$((N + 1))
cp -r "$T/stage" "$T/debug/step-$N"
fi
# Release: 7zipped archive of the vpk for upload (result*/release).
# Skipped unless $RELEASE is set.
if [ -n "${RELEASE:-}" ]; then
  mkdir -p "$T/release"
  7z a "$T/release/${VPKNAME%.vpk}.7z" "$T/$VPKNAME"
fi
