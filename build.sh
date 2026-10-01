#!/usr/bin/env bash
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

nix build --option extra-sandbox-paths "/deadlock=$MNT" --print-out-paths "$@"
