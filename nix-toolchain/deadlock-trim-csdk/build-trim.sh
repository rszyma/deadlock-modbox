#!/usr/bin/env bash
# Build the minimal Panorama toolchain (trimmed CSDK) from the full CSDK.
# Same sandbox setup as build/nix/build.sh: the game is bind-mounted where the
# derivation can read it, the game version keys the derivation.
#
#   ./nix-toolchain/deadlock-trim-csdk/build-trim.sh
#
# With a local unpacked Reduced_CSDK_12 tree instead of the nix fetch:
#
#   CSDK_PATH=/nix/store/...-Reduced_CSDK_12 ./nix-toolchain/deadlock-trim-csdk/build-trim.sh
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

CSDK_ARG=fullCsdkPath
source build/nix/game-env.sh

nix-build \
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
