{ pkgs }:

pkgs.stdenvNoCC.mkDerivation {
  name = "Reduced_CSDK_12";

  src = pkgs.fetchurl {
    url = "https://drive.usercontent.google.com/download?id=1-Z-4CszWQNudzwzs6e6abPsp5RGFOURS&export=download&confirm=t";
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
