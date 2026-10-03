#!/usr/bin/env bash
# Build a VPK from selected patches from ./mod directory.
# Args: with no args defaults to all patches; with mod names builds just those.
#
#   ./build.sh [mod...]
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"; PROJ_ROOT="$PWD"

GAME="$HOME/.steam/steam/steamapps/common/Deadlock/game"
MNT=/tmp/deadlock

mkdir -p "$MNT"
if ! grep -q " $MNT " /proc/mounts 2>/dev/null; then
  BINDFS="$(nix build nixpkgs#bindfs --print-out-paths --no-link)/bin/bindfs"
  # allow_other requires elevated priviledges
  sudo "$BINDFS" -o allow_other "$GAME" "$MNT"
fi

GAMEVERSION="$(grep -m1 '^VersionDate=' "$MNT/citadel/steam.inf" | cut -d= -f2 | tr -d '\r') $(grep -m1 '^VersionTime=' "$MNT/citadel/steam.inf" | cut -d= -f2 | tr -d '\r')"
[ "$GAMEVERSION" != " " ] || { echo "no VersionDate/Time in $MNT/citadel/steam.inf" >&2; exit 1; }

if [ $# -eq 0 ]; then
  MODS=""; RESULT_LINK="result"
else
  MODS=""
  for MOD in "$@"; do
    M="${MOD#.#}"
    [ -f "mods/$M.patch" ] || { echo "no such mod: $M (see mods/)" >&2; exit 1; }
    MODS="${MODS:+$MODS }$M"
  done
  RESULT_LINK="result-$(echo "$MODS" | tr ' ' '+')"
fi

out_path=$(nix-build \
  --option extra-sandbox-paths "/deadlock=$MNT" \
  --argstr mods "$MODS" \
  --argstr gameVersion "$GAMEVERSION" \
  -o "$RESULT_LINK" \
  --no-build-output \
)
echo "debug:" $out_path/debug
echo "VPK:" $out_path/*.vpk
echo "7z:" $out_path/release/*.7z
