{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" ];
      forAll = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
      toolchain = pkgs: {
        deadlock-csdk = pkgs.callPackage ./nix/packages/deadlock-csdk.nix { };
        deadlock-resourcecompiler =
          (pkgs.callPackage ./nix/packages/make-wine-wrapper.nix { }) "deadlock-resourcecompiler"
            "resourcecompiler.exe";
      };
    in
    {
      packages = forAll (pkgs: {
        default = pkgs.callPackage ./nix/packages/deadlock-modbox.nix {
          inherit (toolchain pkgs) deadlock-resourcecompiler deadlock-csdk;
        };
      });

      devShells = forAll (pkgs: {
        default = pkgs.mkShell {
          buildInputs = [
            (toolchain pkgs).deadlock-resourcecompiler
            pkgs.source2viewer-cli
            pkgs.python3Packages.vpk
            pkgs.python3
            pkgs.jq
          ];
        };
      });
    };
}
