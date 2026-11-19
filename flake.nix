{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" ];
      forAll = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
      toolchain = pkgs: {
        deadlock-csdk = pkgs.callPackage ./nix-toolchain/deadlock-csdk/package.nix { };
        # Vendored from nixpkgs (see nix-toolchain/source2viewer-cli/README.md).
        source2viewer-cli = pkgs.callPackage ./nix-toolchain/source2viewer-cli/package.nix { };
        deadlock-resourcecompiler =
          (pkgs.callPackage ./nix-toolchain/make-csdk-tool/package.nix { }) "deadlock-resourcecompiler"
            "resourcecompiler.exe";
      };
      # treefmt with its tools on PATH (see treefmt.toml).
      # A plain writeShellScriptBin: its build runs no check, so CI only fetches cached tools.
      treefmt =
        pkgs:
        pkgs.writeShellScriptBin "treefmt" ''
          export PATH=${
            pkgs.lib.makeBinPath [
              pkgs.treefmt
              pkgs.nixfmt
              pkgs.shellcheck
            ]
          }:$PATH
          exec treefmt "$@"
        '';
    in
    {
      # The toolchain that builds mods (see nix-toolchain/README.md).
      # The mod builder itself is build/nix/build.sh.
      packages = forAll (pkgs: {
        inherit (toolchain pkgs)
          deadlock-csdk
          deadlock-resourcecompiler
          source2viewer-cli
          ;
        # Mirror-vs-upstream check: `nix run .#verify-csdk -- <gdrive zip>`.
        verify-csdk = (toolchain pkgs).deadlock-csdk.verify;
        # Trim blob check: `nix run .#verify-csdk-trim -- <rebuilt-tree> [url]`.
        verify-csdk-trim = (pkgs.callPackage ./nix-toolchain/deadlock-trim-csdk-bin/package.nix { }).verify;
      });

      # `nix fmt`; CI runs `nix fmt -- --ci`.
      formatter = forAll treefmt;

      devShells = forAll (pkgs: {
        default = pkgs.mkShell {
          packages = [
            (toolchain pkgs).deadlock-resourcecompiler
            (toolchain pkgs).source2viewer-cli
            pkgs.python3Packages.vpk
            pkgs.python3
            pkgs.just
            pkgs.bindfs
            pkgs.rclone
            pkgs.strace
            pkgs.zstd
            (treefmt pkgs)
          ];
        };
      });
    };
}
