#!/usr/bin/env bash
# Build the minimal Panorama toolchain (trimmed CSDK) from the full CSDK.
# Same sandbox setup as build/nix/build.sh: the game is bind-mounted where the
# derivation can read it, the game version keys the derivation.
#
#   ./build-trim.sh
#
# With a local unpacked Reduced_CSDK_12 tree instead of the nix fetch:
#
#   CSDK_PATH=/nix/store/...-Reduced_CSDK_12 ./build-trim.sh
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

# Optional full-CSDK override: same CSDK_PATH idea as build/nix/build.sh.
# The path is passed as a plain string on purpose, then bind-mounted
# into the sandbox explicitly (see SANDBOX_PATHS below).
CSDK_SANDBOX=""
CSDK_NIX_ARGS=()
SANDBOX_PATHS="/deadlock=$MNT"
if [ -n "${CSDK_PATH:-}" ]; then
  [ -d "$CSDK_PATH" ] || { echo "CSDK_PATH is not a directory: $CSDK_PATH" >&2; exit 1; }
  for f in game/bin_cs2/win64/resourcecompiler.exe game/citadel/bin game/core/panorama/panorama_config.txt; do
    [ -e "$CSDK_PATH/$f" ] || { echo "CSDK_PATH looks wrong, missing $f" >&2; exit 1; }
  done
  CSDK_REAL="$(realpath "$CSDK_PATH")"
  CSDK_SANDBOX="/csdk"
  SANDBOX_PATHS="$SANDBOX_PATHS $CSDK_SANDBOX=$CSDK_REAL"
  CSDK_NIX_ARGS=(--argstr fullCsdkPath "$CSDK_SANDBOX")
fi

nix shell nixpkgs#nix -c nix-build \
  --option extra-sandbox-paths "$SANDBOX_PATHS" \
  --argstr gameVersion "$GAMEVERSION" \
  "${CSDK_NIX_ARGS[@]}" \
  -o result-trim \
  nix-toolchain/deadlock-trim-csdk/trim.nix
echo
out_path=$(readlink -f result-trim)
drv=$(nix-store -q --deriver "$out_path")
debug_path=$(nix-store -q --outputs "$drv" | grep -- '-debug$')
ln -sfn "$debug_path" result-trim-debug
echo "trim tree: $out_path"
echo "manifest: $debug_path/files.txt"
