{ pkgs }:

let
  hash = "sha256-teK/qVj8zre8Lm8OlyPtyRTcudy/3ZcXvKQt3kguk68=";
in
pkgs.stdenvNoCC.mkDerivation {
  name = "Reduced_CSDK_12";

  src = pkgs.fetchurl {
    urls = [
      # The gdrive download link comes from https://deadlockmodding.pages.dev/modding-tools/csdk-12.
      # Downloading it via nix/curl often fails, returning a status 200 page with html about rate limiting.
      # To fix this flakiness, I've set up a mirror of the original file on Cloudflare R2.
      # You can verify that it is byte-exact by using `passthru.verify` script below.
      #
      # "https://drive.usercontent.google.com/download?id=1-Z-4CszWQNudzwzs6e6abPsp5RGFOURS&export=download&confirm=t"
      "https://pub-e045e6ce2c594838a11c17b87ad8cfa5.r2.dev/Reduced_CSDK_12.zip"
    ];
    name = "Reduced_CSDK_12.zip";
    inherit hash;
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

  # Anyone can confirm the R2 mirror is byte-identical to upstream. Do not trust, verify.
  # 1. Download the zip from google drive yourself:
  #   * https://deadlockmodding.pages.dev/modding-tools/csdk-12 - original page
  #   *
  # 2. Run `nix run .#deadlock-csdk.verify -- <your-download>.zip"`.
  passthru.verify = pkgs.writeShellApplication {
    name = "verify-deadlock-csdk";
    runtimeInputs = [ pkgs.nix ];
    text = ''
      if [ "$#" -ne 1 ]; then
        echo "usage: verify-deadlock-csdk <path to Reduced_CSDK_12.zip from google drive>" >&2
        exit 1
      fi
      ACTUAL="$(nix hash file --sri "$1")"
      if [ "$ACTUAL" = "${hash}" ]; then
        echo "Your downloaded file is identical to the R2 mirror"
      else
        echo "MISMATCH: got $ACTUAL want ${hash}" >&2
        exit 1
      fi
    '';
  };
}
