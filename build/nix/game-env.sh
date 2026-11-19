# shellcheck shell=bash disable=SC2034
# Shared setup for build/nix/build.sh and nix-toolchain/deadlock-trim-csdk/build-trim.sh.
# Source it from the repo root. Set CSDK_ARG first: the nix-build argument name that takes
# the sandbox path of a local CSDK tree (CSDK_PATH).
# Sets: GAME, MNT, GAMEVERSION, SANDBOX_PATHS, CSDK_NIX_ARGS.

GAME="${GAME_DIR:-$HOME/.steam/steam/steamapps/common/Deadlock/game}"
MNT=/tmp/deadlock

[ -d "$GAME" ] || { echo "game dir not found: $GAME (set GAME_DIR=... for a custom Steam library)" >&2; exit 1; }
GAME="$(realpath "$GAME")"
mkdir -p "$MNT"
# Re-export via FUSE so the sandbox build (nixbld user) can read the game:
# direct extra-sandbox-paths on $GAME fails when $HOME is 0700, and FUSE
# hides mounts from other users by default, hence allow_other below.
mount_source() {
  # /proc/mounts escapes spaces and other bytes as \ooo.
  printf '%b' "$(awk -v m="$MNT" '$2 == m { print $1; exit }' /proc/mounts)"
}
SRC="$(mount_source)"
if [ -n "$SRC" ] && [ "$SRC" != "$GAME" ]; then
  echo "$MNT shows $SRC, not $GAME: unmounting it" >&2
  fusermount -u "$MNT" 2>/dev/null || sudo umount "$MNT" \
    || { echo "unmount failed: run 'fusermount -u $MNT' and retry" >&2; exit 1; }
  SRC=""
fi
if [ -z "$SRC" ]; then
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

steam_inf() { grep -m1 "^$1=" "$MNT/citadel/steam.inf" | cut -d= -f2 | tr -d '\r'; }
GAMEVERSION="$(steam_inf VersionDate) $(steam_inf VersionTime)"
[ "$GAMEVERSION" != " " ] || { echo "no VersionDate/Time in $MNT/citadel/steam.inf" >&2; exit 1; }

# Optional CSDK override: a local unpacked Reduced_CSDK_12 tree in place of the pinned fetch:
#   CSDK_PATH=/nix/store/...-Reduced_CSDK_12 ./build/nix/build.sh ...
# The path is passed as a plain string on purpose: as a path value nix
# would ingest the whole 6 GB tree into the store on every evaluation.
# A bare string keeps eval instant, but then the tree is not part of the
# derivation closure - and the sandbox only exposes the closure, not the
# whole store. So the tree is bind-mounted into the sandbox explicitly
# (same mechanism as /deadlock above), and the string just points at it.
# The tree must exist (and stay) on the host; root a store copy once, e.g.:
#   nix-store --realise <path> --add-root /nix/var/nix/gcroots/csdk-local
SANDBOX_PATHS="/deadlock=$MNT"
CSDK_NIX_ARGS=()
if [ -n "${CSDK_PATH:-}" ]; then
  [ -d "$CSDK_PATH" ] || { echo "CSDK_PATH is not a directory: $CSDK_PATH" >&2; exit 1; }
  for f in game/bin_cs2/win64/resourcecompiler.exe game/citadel/bin game/core/panorama/panorama_config.txt; do
    [ -e "$CSDK_PATH/$f" ] || { echo "CSDK_PATH looks wrong, missing $f (want an unpacked Reduced_CSDK_12)" >&2; exit 1; }
  done
  SANDBOX_PATHS="$SANDBOX_PATHS /csdk=$(realpath "$CSDK_PATH")"
  CSDK_NIX_ARGS=(--argstr "$CSDK_ARG" /csdk)
fi
