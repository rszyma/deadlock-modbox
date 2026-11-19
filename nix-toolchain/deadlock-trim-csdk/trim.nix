# Build the minimal Panorama toolchain from the full CSDK.
# The game dir is mounted into the sandbox at build time (see nix-toolchain/deadlock-trim-csdk/build-trim.sh);
# the version string keys the derivation, same trick as build/nix/default.nix.
{
  # VersionDate+VersionTime from the game's steam.inf.
  gameVersion,
  # Optional unpacked Reduced_CSDK_12 tree (same CSDK_PATH idea as build.sh).
  # Empty means the pinned nix fetch.
  fullCsdkPath ? "",
}:
let
  lock = builtins.fromJSON (builtins.readFile ../../flake.lock);
  np = lock.nodes.nixpkgs.locked;
  pkgs = import (builtins.fetchTarball {
    url = "https://github.com/${np.owner}/${np.repo}/archive/${np.rev}.tar.gz";
    sha256 = np.narHash;
  }) { };
  fullCsdk =
    if fullCsdkPath == "" then pkgs.callPackage ../deadlock-csdk/package.nix { } else fullCsdkPath;
in
pkgs.callPackage ./package.nix {
  inherit fullCsdk gameVersion;
}
