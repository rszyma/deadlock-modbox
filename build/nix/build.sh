#!/usr/bin/env bash
# Build one VPK from DiffMods in ./mods, applied in the order given.
# With no args, builds all of them (alphabetical order).
# A mod is named by its stem, its file name or its path:
#
#   build/nix/build.sh [mod...]
#   build/nix/build.sh hide-upgrade-reminder mods/esc-play-button.patch
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

MODS=""
for MOD in "$@"; do
  M="${MOD#.#}"
  M="${M#mods/}"
  M="${M%.patch}"
  case "$M" in
    *.vpk) echo "$MOD is a companion name (*.vpk.patch); Modbox builds plain DiffMods only" >&2; exit 1 ;;
  esac
  [ -f "mods/$M.patch" ] || { echo "no such mod: $MOD (see mods/)" >&2; exit 1; }
  MODS="${MODS:+$MODS }$M"
done
if [ -z "$MODS" ]; then
  RESULT_LINK="result"
else
  RESULT_LINK="result-$(echo "$MODS" | tr ' ' '+')"
fi

CSDK_ARG=csdkPath
source build/nix/game-env.sh

if [ -z "${CSDK_PATH:-}" ]; then
  # Pre-fetch the CSDK with a gcroot: it is a large download (about 3 GB), and nix GC must not delete it.
  nix build -L .#deadlock-csdk --out-link .gcroots/deadlock-csdk
fi

# nix-build, not nix build: only nix-build takes --argstr.
nix-build \
  --option extra-sandbox-paths "$SANDBOX_PATHS" \
  --argstr mods "$MODS" \
  --argstr gameVersion "$GAMEVERSION" \
  "${CSDK_NIX_ARGS[@]}" \
  -o "$RESULT_LINK" \
  build/nix
out_path=$(readlink -f "$RESULT_LINK")
drv=$(nix-store -q --deriver "$out_path")
debug_path=$(nix-store -q --outputs "$drv" | grep -- '-debug$')
ln -sfn "$debug_path" "$RESULT_LINK-debug"
echo "debug: $debug_path"
for f in "$out_path"/*.vpk; do echo "VPK: $f"; done
for f in "$debug_path"/release/*.7z; do
  if [ -e "$f" ]; then echo "7z: $f"; fi
done
