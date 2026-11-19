{
  stdenvNoCC,
  strace,
  rsync,
  source2viewer-cli,
  wine64,
  mesa,
  vulkan-loader,
  pkgs,
  dxvkDlls ? pkgs.callPackage ../dxvk-dlls/package.nix { },
  fullCsdk,
  # VersionDate+VersionTime from the game's steam.inf, same hidden-input
  # trick as build/nix/package.nix: game files arrive via
  # extra-sandbox-paths, the version string keys the derivation.
  gameVersion,
}:
stdenvNoCC.mkDerivation {
  name = "deadlock-trim-csdk";
  outputs = [
    "out"
    "debug"
  ];
  dontUnpack = true;
  GAME_MOUNT = "/deadlock";
  FULL_CSDK = "${fullCsdk}";
  _GAME_VERSION = gameVersion;
  # Wine toolchain, same set the dev wrapper uses (see ../make-csdk-tool/package.nix).
  # Passed as env so trim-csdk.sh traces the FULL_CSDK tree, not the
  # store CSDK the wrapper hardcodes.
  WINEBIN = "${wine64}/bin/wine";
  DXVK_TGZ = "${dxvkDlls}";
  VKICD_JSON = "${mesa}/share/vulkan/icd.d/lvp_icd.x86_64.json";
  VKLIB_DIR = "${vulkan-loader}/lib";
  nativeBuildInputs = [
    strace
    rsync
    source2viewer-cli
  ];
  buildPhase = ''
    bash ${./trim-csdk.sh} trace \
      --game "$GAME_MOUNT" --csdk "$FULL_CSDK" --out trim
    bash ${./trim-csdk.sh} repack \
      --csdk "$FULL_CSDK" --list trim/files.txt --out "$out"
    # Traced manifest lives in the debug output, not the shipped tree.
    mkdir -p "$debug"
    cp trim/files.txt trim/files.all.txt "$debug/"
  '';
  # buildPhase writes $out directly.
  dontInstall = true;
  # Windows binaries + data only: skip ELF fixup/strip.
  dontFixup = true;
}
