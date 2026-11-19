{
  lib,
  stdenvNoCC,
  python3,
  p7zip,
  git,
  source2viewer-cli,
  deadlock-resourcecompiler,
  deadlock-csdk,
  name ? "deadlock-modbox",
  patches ? null,
  vpkName ? "pak75_dir.vpk",
  debug ? true,
  release ? true,
  # VersionDate+VersionTime from the game's steam.inf, passed by build/nix/build.sh.
  # The game files enter the sandbox via extra-sandbox-paths and are no derivation input,
  # so this string keys the derivation: a game update gives a new derivation.
  gameVersion,
}:

stdenvNoCC.mkDerivation {
  inherit name;
  outputs = [
    "out"
    "debug"
  ];
  # Only the DiffMods: an edit elsewhere in the repo does not rebuild the mods.
  src = lib.fileset.toSource {
    root = ../..;
    fileset = ../../mods;
  };
  PATCHES = if patches == null then "mods/*.patch" else builtins.toString patches;
  VPKNAME = vpkName;
  # build/nix/build.sh mounts the game dir here via extra-sandbox-paths.
  GAME_MOUNT = "/deadlock";
  GAME_BUILD = gameVersion;
  DEBUG = if debug then "1" else "";
  RELEASE = if release then "1" else "";
  CSDK_DIR = "${deadlock-csdk}";
  DECOMPILER = "source2viewer-cli/${source2viewer-cli.version}";
  PACK_VPK = ../pack-vpk.py;
  nativeBuildInputs = [
    deadlock-resourcecompiler
    source2viewer-cli
    git
    (python3.withPackages (ps: [ ps.vpk ]))
    p7zip
  ];
  buildPhase = ''
    source ${./build-phase.sh}
  '';
  installPhase = ''
    mkdir -p $out $debug
    cp "$T"/*.vpk $out/
    if [ -d "$T/debug" ]; then cp -r "$T/debug" $debug/; fi
    if [ -d "$T/release" ]; then cp -r "$T/release" $debug/; fi
  '';
}
