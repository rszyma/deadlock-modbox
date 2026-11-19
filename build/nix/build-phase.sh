#!/usr/bin/env bash
# modbox build phase (spec diffmod/v1, Deadlock profile):
# parse each DiffMod, decompile its targets from the mounted game, apply the DiffMods in
# order, compile each changed file once, stage, pack.
# Runs inside the nix sandbox. GAME_MOUNT, GAME_BUILD, CSDK_DIR, DECOMPILER, PACK_VPK,
# PATCHES, VPKNAME and TMPDIR come from the derivation. PWD is the source root (mods/).
set -euo pipefail
SPEC=diffmod/v1
die() { echo "error: $*" >&2; exit 1; }
warn() { echo "warning: $*" >&2; }
zpath() { echo "Z:${1//\//\\}"; }
T=$TMPDIR/modroot

# Build record (spec rule 11).
echo "spec: $SPEC"
echo "game-build: $GAME_BUILD"
echo "decompiler: $DECOMPILER"

# Deadlock profile suffix map (spec rule 9). Raw files pass through with no compile.
is_raw() { case "$1" in *.cfg) return 0 ;; *) return 1 ;; esac }
compiled_path() {
  case "$1" in
    *.css | *.xml | *.js) echo "${1%.*}.v${1##*.}_c" ;;
    *) return 1 ;;
  esac
}

# header_key KEY FILE: the first `# KEY: value` line of the header (spec rules 3-4).
header_key() {
  sed -n "/^#/!q; /^#[[:space:]]*$1[[:space:]]*:/{s/^#[^:]*:[[:space:]]*//; s/[[:space:]]*\$//; p; q}" "$2"
}

[ -f "$GAME_MOUNT/citadel/gameinfo.gi" ] \
  || die "no game at $GAME_MOUNT (build/nix/build.sh mounts it; check GAME_DIR)"
CITADEL_VPK="$GAME_MOUNT/citadel/pak01_dir.vpk"
CORE_VPK="$GAME_MOUNT/core/pak01_dir.vpk"
[ -f "$CITADEL_VPK" ] || die "no game VPK at $CITADEL_VPK"

# Parse all DiffMods first, so a rule break fails before the slow steps.
# PT[i]: targets of DiffMod i (newline-separated). NEW[path]: the path is a new file.
declare -a PT=()
declare -A NEW=()
I=0
for P in $PATCHES; do
  I=$((I + 1))
  case "$P" in
    *.vpk.patch) die "$P: a plain DiffMod name must not end in .vpk.patch (spec rule 12)" ;;
  esac
  # git parses the body (spec rule 7): numstat lists the targets, summary the file ops.
  STAT=$(git apply --numstat --summary "$P" 2>&1) || die "$P is not a valid DiffMod: $STAT"
  OPS=$(printf '%s\n' "$STAT" | grep -E '^ (delete mode|rename|copy|mode change) ' || true)
  [ -z "$OPS" ] || die "$P: renames, copies, deletes and mode changes are not allowed (spec rule 8):"$'\n'"$OPS"
  PT[I]=$(printf '%s\n' "$STAT" | sed -n 's/^[0-9-]*\t[0-9-]*\t//p')
  while IFS= read -r D; do
    NEW[$D]=1
  done < <(printf '%s\n' "$STAT" | sed -n 's/^ create mode [0-7]* //p')
  KEY_SPEC=$(header_key spec "$P")
  KEY_DEC=$(header_key decompiler "$P")
  if [ -n "$KEY_SPEC" ] && [ "$KEY_SPEC" != "$SPEC" ]; then
    warn "$P: unknown spec version $KEY_SPEC, building as $SPEC"
  fi
  if [ -n "$KEY_DEC" ] && [ "$KEY_DEC" != "$DECOMPILER" ]; then
    warn "$P: made with decompiler $KEY_DEC, this build uses $DECOMPILER"
  fi
  while IFS= read -r D; do
    case "$D" in
      /* | .. | ../* | */.. | */../*) die "$P: $D leaves the VPK root (spec rule 8)" ;;
    esac
    is_raw "$D" || compiled_path "$D" >/dev/null \
      || die "$P: $D: the Deadlock profile maps no suffix .${D##*.} (spec rule 9)"
  done <<<"${PT[I]}"
done
ALL=$(printf '%s\n' "${PT[@]}" | sort -u)

mkdir -p "$T/game/citadel" "$T/game/core/panorama"
cp "$GAME_MOUNT/citadel/gameinfo.gi" "$T/game/citadel/gameinfo.gi"
ln -s "$CSDK_DIR/game/citadel/bin" "$T/game/citadel/bin"
cp "$CSDK_DIR/game/core/panorama/panorama_config.txt" \
  "$T/game/core/panorama/panorama_config.txt"
export WINEPREFIX="$T/wineprefix"
export DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1

# step-0 holds the game copy of each target. Source2Viewer-CLI writes each file at its
# VPK path (cleartext suffix) under the -o folder, so fresh-0/<target> is exact.
# New files have no game copy: git apply creates them.
mkdir -p "$T/step-0" "$T/fresh-0"
TO_DECOMPILE=()
while IFS= read -r D; do
  if [ -n "${NEW[$D]:-}" ]; then
    echo "+ new file $D (no decompile)" >&2
  elif is_raw "$D"; then
    echo "+ extracting raw $D" >&2
    Source2Viewer-CLI -i "$CITADEL_VPK" -o "$T/fresh-0" -f "$D" \
      || die "extract command failed for $D"
    if [ ! -f "$T/fresh-0/$D" ]; then
      # Not in the citadel pack: read the core pack next (Deadlock profile).
      Source2Viewer-CLI -i "$CORE_VPK" -o "$T/fresh-0" -f "$D" \
        || die "extract command failed for $D"
    fi
  else
    TO_DECOMPILE+=("$(compiled_path "$D")")
  fi
done <<<"$ALL"
if [ "${#TO_DECOMPILE[@]}" -gt 0 ]; then
  echo "+ decompiling ${TO_DECOMPILE[*]}" >&2
  FILTER=$(IFS=,; echo "${TO_DECOMPILE[*]}")
  Source2Viewer-CLI -i "$CITADEL_VPK" -d -o "$T/fresh-0" -f "$FILTER" \
    || die "decompile command failed"
fi
while IFS= read -r D; do
  [ -z "${NEW[$D]:-}" ] || continue
  [ -f "$T/fresh-0/$D" ] || die "the game VPKs hold no $D"
  mkdir -p "$T/step-0/$(dirname "$D")"
  cp "$T/fresh-0/$D" "$T/step-0/$D"
done <<<"$ALL"

# step-N is a copy of step-(N-1) with DiffMod N applied, so DiffMods that change the
# same file compose in the order given (spec rule 10).
N=0
for P in $PATCHES; do
  N=$((N + 1)); W="$T/step-$N"
  mkdir -p "$W"; cp -r "$T/step-$((N - 1))/." "$W/"
  if ! git -C "$W" apply "$PWD/$P"; then
    TGT=$(printf '%s\n' "${PT[N]}" | paste -sd ' ')
    if [ "$N" -gt 1 ] && git -C "$T/step-0" apply --check "$PWD/$P" 2>/dev/null; then
      # It fits the game files, so an earlier DiffMod on a shared target breaks it.
      EARLIER=""; J=0
      for Q in $PATCHES; do
        J=$((J + 1)); [ "$J" -lt "$N" ] || break
        if printf '%s\n' "${PT[J]}" | grep -qxFf <(printf '%s\n' "${PT[N]}"); then
          EARLIER="${EARLIER:+$EARLIER, }$Q"
        fi
      done
      die "$P clashes with $EARLIER (targets: $TGT); change the mod order or fix one of them"
    fi
    die "$P does not apply to game build $GAME_BUILD (targets: $TGT); re-derive it"
  fi
done
FINAL="$T/step-$N"

# Compile each target once, from its final state.
ADDON=citadel_addons/badge
while IFS= read -r D; do
  if is_raw "$D"; then
    echo "+ staging raw $D (no compile)" >&2
    mkdir -p "$T/stage/$(dirname "$D")"
    cp "$FINAL/$D" "$T/stage/$D"
    continue
  fi
  C=$(compiled_path "$D")
  mkdir -p "$T/content/$ADDON/$(dirname "$D")"
  cp "$FINAL/$D" "$T/content/$ADDON/$D"
  (cd "$T/game" && deadlock-resourcecompiler -v -f \
    -game "$(zpath "$T/game/citadel")" \
    "$(zpath "$T/content/$ADDON/$D")")
  OUT="$T/game/$ADDON/$C"
  if [ ! -f "$OUT" ]; then
    find "$T/game/citadel_addons" -type f >&2 2>/dev/null || true
    die "compile produced no $OUT"
  fi
  mkdir -p "$T/stage/$(dirname "$C")"
  cp "$OUT" "$T/stage/$C"
done <<<"$ALL"

# Pack with the python vpk library (scriptable and fast), in sorted order:
# same DiffMods plus same game build give the same VPK bytes.
python3 "$PACK_VPK" "$T/stage" "$T/$VPKNAME"

# Debug: the patched cleartext sources plus the compiled outputs, so a build can be
# inspected without a rebuild (result*-debug links). step-0 is the game copy, step-1..N
# are the patched states (each with the DiffMod that made it), step-N+1 is the staged
# build result. Skipped unless $DEBUG is set.
if [ -n "${DEBUG:-}" ]; then
  mkdir -p "$T/debug"
  printf 'spec: %s\ngame-build: %s\ndecompiler: %s\n' \
    "$SPEC" "$GAME_BUILD" "$DECOMPILER" >"$T/debug/build-info.txt"
  cp -r "$T/step-0" "$T/debug/step-0"
  N=0
  for P in $PATCHES; do
    N=$((N + 1))
    cp -r "$T/step-$N" "$T/debug/step-$N"
    cp "$PWD/$P" "$T/debug/step-$N/"
  done
  N=$((N + 1))
  cp -r "$T/stage" "$T/debug/step-$N"
fi
# Release: 7zipped archive of the vpk for upload (result*-debug/release).
# Skipped unless $RELEASE is set.
if [ -n "${RELEASE:-}" ]; then
  mkdir -p "$T/release"
  # 7z stores the file mtime: reset it, so the archive bytes are reproducible too.
  touch -d @0 "$T/$VPKNAME"
  7z a "$T/release/${VPKNAME%.vpk}.7z" "$T/$VPKNAME"
fi
