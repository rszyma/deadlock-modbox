# Used by build/nix/build.sh.
# This can't be put in the flake as package, since flakes can't take package arguments
# (see https://github.com/NixOS/nix/issues/5107),
# but classical nix-build can, via --argstr.
{
  # space-separated mods/*.patch stems, or "" for all
  mods ? "",
  # VersionDate+VersionTime from the game's steam.inf, used to enforce rebuilds on game updates,
  # since game files are passed via extra-sandbox-paths and are not derivation inputs.
  # (it's a kind of a hidden input though).
  gameVersion,
  # Optional unpacked Reduced_CSDK_12 tree (see CSDK_PATH in build/nix/build.sh).
  # Skips the flaky Google Drive fetch.
  csdkPath ? "",
}:
let
  lock = builtins.fromJSON (builtins.readFile ../../flake.lock);
  np = lock.nodes.nixpkgs.locked;
  pkgs = import (builtins.fetchTarball {
    url = "https://github.com/${np.owner}/${np.repo}/archive/${np.rev}.tar.gz";
    sha256 = np.narHash;
  }) { };
  # Local CSDK tree (CSDK_PATH) or the pinned fetch when empty.
  csdk =
    if csdkPath == "" then
      pkgs.callPackage ../../nix-toolchain/deadlock-csdk/package.nix { }
    else
      csdkPath;
  tc = {
    deadlock-csdk = csdk;
    # Vendored from nixpkgs (see nix-toolchain/source2viewer-cli/README.md).
    source2viewer-cli = pkgs.callPackage ../../nix-toolchain/source2viewer-cli/package.nix { };
    deadlock-resourcecompiler =
      (pkgs.callPackage ../../nix-toolchain/make-csdk-tool/package.nix { inherit csdk; })
        "deadlock-resourcecompiler"
        "resourcecompiler.exe";
  };
  allMods = map (pkgs.lib.removeSuffix ".patch") (
    builtins.attrNames (
      pkgs.lib.filterAttrs (n: v: v == "regular" && pkgs.lib.hasSuffix ".patch" n) (
        builtins.readDir ../../mods
      )
    )
  );
  sel = if mods == "" then allMods else builtins.filter builtins.isString (builtins.split " +" mods);
  stem = builtins.concatStringsSep "+" sel;
in
pkgs.callPackage ./package.nix {
  inherit (tc) deadlock-resourcecompiler deadlock-csdk source2viewer-cli;
  inherit gameVersion;
  name = "deadlock-modbox-${if mods == "" then "bundle" else stem}";
  patches = map (m: "mods/${m}.patch") sel;
  vpkName = if mods == "" then "pak75_dir.vpk" else "${stem}.vpk";
}
