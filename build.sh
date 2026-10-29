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

# Optional CSDK override: the Google Drive fetch is flaky (changing hashes),
# so a local unpacked Reduced_CSDK_12 tree can be used instead:
#   CSDK_PATH=/nix/store/...-Reduced_CSDK_12 ./build.sh ...
# The path is passed as a plain string on purpose: as a path value nix
# would ingest the whole 6 GB tree into the store on every evaluation.
# A bare string keeps eval instant, but then the tree is not part of the
# derivation closure - and this sandbox only exposes the closure, not the
# whole store. So the tree is bind-mounted into the sandbox explicitly
# (same mechanism as /deadlock above), and the string just points at it.
# The tree must exist (and stay) on the host; root a store copy once, e.g.:
#   nix-store --realise <path> --add-root /nix/var/nix/gcroots/csdk-local
CSDK_SANDBOX=""
CSDK_NIX_ARGS=()
SANDBOX_PATHS="/deadlock=$MNT"
if [ -n "${CSDK_PATH:-}" ]; then
  [ -d "$CSDK_PATH" ] || { echo "CSDK_PATH is not a directory: $CSDK_PATH" >&2; exit 1; }
  for f in game/bin_cs2/win64/resourcecompiler.exe game/citadel/bin game/core/panorama/panorama_config.txt; do
    [ -e "$CSDK_PATH/$f" ] || { echo "CSDK_PATH looks wrong, missing $f (want an unpacked Reduced_CSDK_12)" >&2; exit 1; }
  done
  CSDK_REAL="$(realpath "$CSDK_PATH")"
  CSDK_SANDBOX="/csdk"
  SANDBOX_PATHS="$SANDBOX_PATHS $CSDK_SANDBOX=$CSDK_REAL"
  CSDK_NIX_ARGS=(--argstr csdkPath "$CSDK_SANDBOX")
else
  # Pre-fetch csdk and setup gcroot; it's quite large download (2.4G) and would be a shame if it were to be deleted by nix GC.
  nix build -L .#deadlock-csdk --out-link nix/.gcroots/deadlock-csdk
fi

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

out_path=$(nix shell nixpkgs#nix -c nix-build \
  --option extra-sandbox-paths "$SANDBOX_PATHS" \
  --argstr mods "$MODS" \
  --argstr gameVersion "$GAMEVERSION" \
  "${CSDK_NIX_ARGS[@]}" \
  -o "$RESULT_LINK" \
  # --no-build-output \
)
echo
echo "debug:" $out_path/debug
echo "VPK:" $out_path/*.vpk
echo "7z:" $out_path/release/*.7z
