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
          (pkgs.callPackage ./nix/packages/make-csdk-tool.nix { }) "deadlock-resourcecompiler"
            "resourcecompiler.exe";
        deadlock-cfgvpk =
          (pkgs.callPackage ./nix/packages/make-csdk-tool.nix { }) "deadlock-cfgvpk"
            "CSDKCfgVPK.exe";
      };
    in
    {
      # Bundle (everything merged) as default; toolchain flat; mods under
      # .#mods.<name>, auto-discovered from mods/*.patch.
      packages = forAll (
        pkgs:
        {
          default = pkgs.callPackage ./nix/packages/deadlock-modbox.nix {
            inherit (toolchain pkgs) deadlock-resourcecompiler deadlock-csdk;
            name = "deadlock-modbox-bundle";
          };
        }
        // {
          inherit (toolchain pkgs) deadlock-csdk deadlock-resourcecompiler deadlock-cfgvpk;
          inherit (pkgs) source2viewer-cli;
        }
      );

      mods =
        let
          pkgs = nixpkgs.legacyPackages.x86_64-linux;
          tc = toolchain pkgs;
          mkMod =
            file:
            let
              mod = nixpkgs.lib.removeSuffix ".patch" file;
            in
            {
              name = mod;
              value = pkgs.callPackage ./nix/packages/deadlock-modbox.nix {
                inherit (tc) deadlock-resourcecompiler deadlock-csdk;
                name = "deadlock-modbox-${mod}";
                patches = [ "mods/${file}" ];
                vpkName = "${mod}.vpk";
              };
            };
          modFiles = builtins.attrNames (
            nixpkgs.lib.filterAttrs (n: v: v == "regular" && nixpkgs.lib.hasSuffix ".patch" n) (
              builtins.readDir ./mods
            )
          );
        in
        builtins.listToAttrs (map mkMod modFiles);

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
