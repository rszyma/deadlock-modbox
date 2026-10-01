#!/usr/bin/env bash
# Full build: mount the game (FUSE passthrough, root at setup only),
# sync the hash input, build. With no args builds all the mods into one vpk;
# with a mod name builds just that (see `nix flake show`).
#   ./build.sh [mod]
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

nix develop --command ./tools/update-hashes.sh

if [ $# -eq 0 ]; then
  out_path=$(nix build --option extra-sandbox-paths "/deadlock=$MNT" --print-out-paths)
  echo "Result VPK:" $out_path/*
elif [ $# -eq 1 ]; then
  ATTR="${1#.#}"
  out_path=$(nix build --option extra-sandbox-paths "/deadlock=$MNT" --print-out-paths -o "result-$ATTR" ".#$ATTR")
  echo "Result VPK:" $out_path/*
else
  echo "usage: ./build.sh [mod]" >&2
  exit 1
fi
