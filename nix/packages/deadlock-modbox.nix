{
  stdenvNoCC,
  python3Packages,
  git,
  source2viewer-cli,
  deadlock-resourcecompiler,
  deadlock-csdk,
  name ? "deadlock-modbox",
  patches ? null,
  vpkName ? "pak75_dir.vpk",
}:

let
  # The game dir is mounted into the sandbox at build time (chroot kept):
  #   ./build.sh
  gameMount = "/deadlock";
in
stdenvNoCC.mkDerivation {
  inherit name;
  src = ../..;
  PATCHES = if patches == null then "mods/*.patch" else builtins.toString patches;
  VPKNAME = vpkName;
  # Sandboxed build; the game dir arrives via extra-sandbox-paths (a hidden
  # input by design here - the game version IS the input, see README).
  GAME_MOUNT = gameMount;
  CSDK_DIR = "${deadlock-csdk}";
  # Explicit game input: tools/update-hashes.sh refreshes this before every
  # build, so game updates change the derivation hash and force a rebuild.
  GAME_HASH = builtins.readFile ../../game-file-hashes.json;
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
  '';
}
