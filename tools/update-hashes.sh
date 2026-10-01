#!/usr/bin/env bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"; PROJ_ROOT="$PWD"

GAME="$HOME/.steam/steam/steamapps/common/Deadlock/game"
HASHFILE="$PROJ_ROOT/game-file-hashes.json"
KEYS=$(jq -r 'keys_unsorted[]' "$HASHFILE")
[ -n "$KEYS" ] || { echo "no keys in $HASHFILE"; exit 1; }

{
  for K in $KEYS; do
    [ -f "$GAME/$K" ] || { echo "no file at $GAME/$K"; exit 1; }
    printf '%s %s\n' "$K" "$(sha256sum "$GAME/$K" | cut -d' ' -f1)"
  done
} | jq -R -s 'split("\n") | map(select(length > 0) | split(" ") | {(.[0]): .[1]}) | add' > "$HASHFILE"
echo "synced game-file-hashes.json"
