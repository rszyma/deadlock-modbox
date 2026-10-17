#!/usr/bin/env bash
# Build a VPK from selected patches from ./mod directory.
# Args: with no args defaults to all patches; with mod names builds just those.
#
#   ./build.sh [mod...]
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"; PROJ_ROOT="$PWD"

GAME="${GAME_DIR:-$HOME/.steam/steam/steamapps/common/Deadlock/game}"
MNT=/tmp/deadlock

[ -d "$GAME" ] || { echo "game dir not found: $GAME (set GAME_DIR=... for a custom Steam library)" >&2; exit 1; }
mkdir -p "$MNT"
# Re-export via FUSE so the sandbox build (nixbld user) can read the game:
# direct extra-sandbox-paths on $GAME fails when $HOME is 0700, and FUSE
# hides mounts from other users by default, hence allow_other below.
if ! grep -q " $MNT " /proc/mounts 2>/dev/null; then
  if command -v bindfs >/dev/null 2>&1; then
    BINDFS=bindfs
  else
    BINDFS="$(nix build nixpkgs#bindfs --print-out-paths --no-link)/bin/bindfs"
  fi
  # Try unprivileged first: no sudo needed when /etc/fuse.conf enables user_allow_other.
  if ! "$BINDFS" -o allow_other "$GAME" "$MNT" 2>/dev/null; then
    echo "unprivileged bindfs failed, retrying with sudo" >&2
    sudo "$BINDFS" -o allow_other "$GAME" "$MNT" \
      || { echo "hint: run 'sudo -v' in a terminal first, or enable user_allow_other in /etc/fuse.conf for passwordless mounts" >&2; exit 1; }
  fi
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
  # --no-build-output \
)
echo
echo "debug:" $out_path/debug
echo "VPK:" $out_path/*.vpk
echo "7z:" $out_path/release/*.7z
