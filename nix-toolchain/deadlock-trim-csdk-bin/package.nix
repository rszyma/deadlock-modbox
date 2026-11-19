{ pkgs }:

# Prebuilt minimal Panorama toolchain: the 38 files a UI compile reads.
# Built by nix-toolchain/deadlock-trim-csdk/package.nix; uploaded to R2 with
# `just upload-csdk-trim-to-r2`. Do not trust this blob: rebuild the tree
# yourself with build-trim.sh, then
# `nix run .#verify-csdk-trim -- <your-rebuilt-tree> [url]`
# (or the `just verify-csdk-trim` wrapper, which does both steps).
let
  # The single source of truth for the blob: fetchurl and passthru.verify
  # below both use it, so the pin cannot drift from the check.
  url = "https://pub-e045e6ce2c594838a11c17b87ad8cfa5.r2.dev/deadlock-trim-csdk.tar.zst";
  hash = "";
in
pkgs.stdenvNoCC.mkDerivation {
  name = "deadlock-trim-csdk";

  src = pkgs.fetchurl {
    urls = [
      # Fill after the first upload (upload-csdk-trim-to-r2 prints the hash to pin).
      url
    ];
    inherit hash;
  };

  # The tarball holds ./game at its top: unpack in place, so `game` stays a subdir.
  sourceRoot = ".";
  # stdenv does not ship zstd, and tar needs it for .tar.zst.
  nativeBuildInputs = [ pkgs.zstd ];

  # Windows binaries + data only: skip ELF fixup/strip.
  dontFixup = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -a game $out/
    runHook postInstall
  '';

  # Independent blob check without trusting the uploader and without any
  # account: downloads the tarball (pinned URL by default), unpacks it,
  # and diffs it against your locally rebuilt tree. Rebuild or expose
  # a mismatch.
  passthru.verify = pkgs.writeShellApplication {
    name = "verify-deadlock-trim-csdk";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.curl
      pkgs.diffutils
      pkgs.gnutar
    ];
    text = ''
      if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
        echo "usage: verify-deadlock-trim-csdk <rebuilt-tree> [url]" >&2
        exit 1
      fi
      BLOB_URL="${url}"
      if [ "$#" -eq 2 ]; then
        BLOB_URL="$2"
      fi
      TMP="$(mktemp -d)"
      trap 'chmod -R -f u+w "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
      curl -fL -o "$TMP/blob.tar.zst" "$BLOB_URL"
      mkdir -p "$TMP/blob"
      tar -xf "$TMP/blob.tar.zst" -C "$TMP/blob"
      if diff -r "$1" "$TMP/blob"; then
        echo "BLOB MATCHES LOCAL REBUILD"
      else
        echo "MISMATCH: blob differs from $1" >&2
        exit 1
      fi
    '';
  };
}
