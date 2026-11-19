{ pkgs }:

pkgs.stdenvNoCC.mkDerivation {
  name = "Reduced_CSDK_12";

  src = pkgs.fetchurl {
    urls = [
      # The gdrive download link comes from https://deadlockmodding.pages.dev/modding-tools/csdk-12.
      # The R2 URL is a mirror hosted by me, and used here because downloading via nix/curl
      # from gdrive often fails - with status 200 and the content returned is html about rate limiting.
      # That's why R2 link is tried first - because trying gdrive first would often fail on hash mismatch.
      "https://pub-e045e6ce2c594838a11c17b87ad8cfa5.r2.dev/Reduced_CSDK_12.zip"
      "https://drive.usercontent.google.com/download?id=1-Z-4CszWQNudzwzs6e6abPsp5RGFOURS&export=download&confirm=t"
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
