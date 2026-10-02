# Used by ./build.sh.
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
}:
let
  lock = builtins.fromJSON (builtins.readFile ./flake.lock);
  np = lock.nodes.nixpkgs.locked;
  pkgs = import (builtins.fetchTarball {
    url = "https://github.com/${np.owner}/${np.repo}/archive/${np.rev}.tar.gz";
    sha256 = np.narHash;
  }) { };
  tc = {
    deadlock-csdk = pkgs.callPackage ./nix/packages/deadlock-csdk.nix { };
    deadlock-resourcecompiler =
      (pkgs.callPackage ./nix/packages/make-csdk-tool.nix { }) "deadlock-resourcecompiler"
        "resourcecompiler.exe";
  };
  allMods = map (pkgs.lib.removeSuffix ".patch") (
    builtins.attrNames (
      pkgs.lib.filterAttrs (n: v: v == "regular" && pkgs.lib.hasSuffix ".patch" n) (
        builtins.readDir ./mods
      )
    )
  );
  sel = if mods == "" then allMods else builtins.filter builtins.isString (builtins.split " +" mods);
  stem = builtins.concatStringsSep "+" sel;
in
pkgs.callPackage ./nix/packages/deadlock-modbox.nix {
  inherit (tc) deadlock-resourcecompiler deadlock-csdk;
  inherit gameVersion;
  name = "deadlock-modbox-${if mods == "" then "bundle" else stem}";
  patches = map (m: "mods/${m}.patch") sel;
  vpkName = if mods == "" then "pak75_dir.vpk" else "${stem}.vpk";
}
