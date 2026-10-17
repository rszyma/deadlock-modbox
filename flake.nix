{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" ];
      forAll = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
      toolchain = pkgs: {
        deadlock-csdk = pkgs.callPackage ./nix/packages/deadlock-csdk.nix { };
        # Vendored from nixpkgs (see nix/packages/source2viewer-cli/README.md).
        source2viewer-cli = pkgs.callPackage ./nix/packages/source2viewer-cli/package.nix { };
        deadlock-resourcecompiler =
          (pkgs.callPackage ./nix/packages/make-csdk-tool.nix { }) "deadlock-resourcecompiler"
            "resourcecompiler.exe";
        deadlock-cfgvpk =
          (pkgs.callPackage ./nix/packages/make-csdk-tool.nix { }) "deadlock-cfgvpk"
            "CSDKCfgVPK.exe";
      };
    in
    {
      # Following packages make a toolchain building mods (see nix/README.md).
      # For mod builder itself see ./build.sh instead.
      packages = forAll (pkgs: {
        inherit (toolchain pkgs)
          deadlock-csdk
          deadlock-resourcecompiler
          deadlock-cfgvpk
          source2viewer-cli
          ;
      });

      devShells = forAll (pkgs: {
        default = pkgs.mkShell {
          buildInputs = [
            (toolchain pkgs).deadlock-resourcecompiler
            (toolchain pkgs).source2viewer-cli
            pkgs.python3Packages.vpk
            pkgs.python3
          ];
        };
      });
    };
}
