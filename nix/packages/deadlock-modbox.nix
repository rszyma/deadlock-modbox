{
  lib,
  stdenvNoCC,
  python3Packages,
  git,
  source2viewer-cli,
  deadlock-resourcecompiler,
  deadlock-csdk,
  name ? "deadlock-modbox",
  patches ? null,
  vpkName ? "pak75_dir.vpk",
  debug ? true,
  # VersionDate+VersionTime from the game's steam.inf, baked in by
  # ./build.sh via a generated wrapper flake (flake refs take no
  # arguments). Keys the derivation, so game updates rebuild through the
  # normal cache.
  gameVersion,
}:

let
  # The game dir is mounted into the sandbox at build time (chroot kept):
  #   ./build.sh
  gameMount = "/deadlock";
in
stdenvNoCC.mkDerivation {
  inherit name;
  src = lib.cleanSource ../..;
  PATCHES = if patches == null then "mods/*.patch" else builtins.toString patches;
  VPKNAME = vpkName;
  # Sandboxed build; the game dir arrives via extra-sandbox-paths (a hidden
  # input by design here - the game version IS the input, see README).
  GAME_MOUNT = gameMount;
  DEBUG = if debug then "1" else "";
  CSDK_DIR = "${deadlock-csdk}";
  # The mounted game is a hidden input by design (see README);
  # We need to pass outside value to force rebuild on game update.
  _GAME_VERSION = gameVersion;
  nativeBuildInputs = [
    deadlock-resourcecompiler
    source2viewer-cli
    git
    python3Packages.vpk
  ];
  buildPhase = ''
    source ${../../tools/build-phase.sh}
  '';
  installPhase = ''
    mkdir -p $out
    cp "$T"/*.vpk $out/
    cp -r "$T/debug" $out/ 2>/dev/null || true
  '';
}
