{ pkgs }:

pkgs.stdenvNoCC.mkDerivation {
  name = "Reduced_CSDK_12";

  src = pkgs.fetchurl {
    urls = [
      # Original gdrive download link from https://deadlockmodding.pages.dev/modding-tools/csdk-12.
      # Download via nix/curl often fails (even though via browser always works),
      # so I've set up a mirror on Cloudflare R2, so at least 1 stable mirror is up.
      "https://drive.usercontent.google.com/download?id=1-Z-4CszWQNudzwzs6e6abPsp5RGFOURS&export=download&confirm=t"
      "https://pub-e045e6ce2c594838a11c17b87ad8cfa5.r2.dev/Reduced_CSDK_12.zip"
    ];
    name = "Reduced_CSDK_12.zip";
    hash = "sha256-teK/qVj8zre8Lm8OlyPtyRTcudy/3ZcXvKQt3kguk68=";
  };

  nativeBuildInputs = [ pkgs.unzip ];

  unpackPhase = ''
    runHook preUnpack
    unzip -q $src -d unpack
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -a unpack/Reduced_CSDK_12/. $out/
    runHook postInstall
  '';

  # Windows binaries + data only: skip ELF fixup/strip (also saves a full
  # tree scan of ~12k files / ~6GB).
  dontFixup = true;
}
