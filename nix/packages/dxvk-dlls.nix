{ pkgs }:

# DXVK dlls for the Wine prefix, pinned from upstream (nixpkgs' top-level
# dxvk package ships no dlls).
pkgs.fetchurl {
  url = "https://github.com/doitsujin/dxvk/releases/download/v2.7.1/dxvk-2.7.1.tar.gz";
  hash = "sha256-2Fznx59X7NdlqqG55wB8uHXm/en20zHfeZvOc9UTzoc=";
}
