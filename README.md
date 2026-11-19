# deadlock-modbox

![modbox logo](assets/logo.svg)

> Composable Deadlock UI mods built from .patch files, that use [DiffMod spec](https://github.com/diffmod/diffmod-spec).

This repo consists of 2 parts:
* a builder, for compiling diffmod files to .vpk (for Nix and Windows)
* a small collection of plain diffmod mods I personally use

Together, this works by:
1. sourcing fresh from game files that the mods change,
2. decompiling game files using [Source 2 Viewer](https://s2v.app/)
3. applying mod (.patch) files to decompiled game resources.
4. compiling back to a single `.vpk` file with resourcecompiler.exe from [Reduced_CSDK_12](https://deadlockmodding.pages.dev/modding-tools/csdk-12) modified game files.

For the reasons behind DiffMods,
and how they compare to classic VPK mods,
read the [DiffMod website](https://diffmod.github.io/diffmod-spec/).

## Spec conformance

Modbox follows `diffmod/v1` with the Deadlock profile.

- Plain DiffMods (rules 1-11): supported.
  The build reads the header keys,
  rejects renames, deletes and paths outside the VPK root,
  fails on a file type that the profile does not map,
  and names the mod and the targets when a mod does not apply.
  The build log starts with the spec version, the game build and the decompiler version.
- Companions (rules 12-19): not supported yet.
- Not checked yet: UTF-8 and LF line ends (rule 1).

## Mods in this repo

This repository contains several UI mods.
They are completely usable and kept up to date (by me),
and serve as examples of how plain DiffMod mods look like.

Each file in `mods/` is one mod.

- **Remove ESC menu animations**:
  the pause menu opens and closes at once.
- **Always show ability suggestions**:
  the badge on the next upgrade of your build shows all the time,
  not only in the HUD detail view.
- **Hide ability suggestions in Street Brawl**:
  hides the build suggestion badge in Street Brawl,
  against [the stuck badge bug](https://forums.playdeadlock.com/threads/minor-bug-with-suggested-ability-on-pocket-in-street-brawl.166966/).
  It overrides *Always show ability suggestions* in that mode.
- **Hide upgrade reminder**:
  hides the "hold <key> to upgrade" banner above the abilities.
- **Click outside to close shop**:
  a click on an empty area around the shop content closes the shop, same as ESC.
- **Click outside to close imbue dialog**:
  a click on the dimmed area around the imbue dialog cancels it, same as ESC.
- **Imbue cancel with mouse back**:
  the mouse back button (mouse4) cancels the imbue dialog, also when mouse4 has a game bind.
- **ESC Play button**:
  adds a Play button to the ESC menu, so you can queue without the Hideout terminals. QOL Lock has this feature bundled.

## Build

### Requirements

- Linux, x86_64.
- [Nix](https://nixos.org/download/) with flakes enabled.
- Your user is in the Nix `trusted-users`.
  The build passes the game folder into the sandbox with `--option extra-sandbox-paths`,
  and Nix ignores that option for other users.
- FUSE with `user_allow_other` in `/etc/fuse.conf`,
  or `sudo` rights:
  the build mounts the game folder at `/tmp/deadlock` with `bindfs`.
- Deadlock, installed through Steam.
- About 3 GB of download on the first build (the CSDK, which holds the compiler).
  No GPU needed: the compiler runs headless under Wine.

### Commands

```bash
# all mods in ./mods directory, in alphabetical order, as one VPK
./build/nix/build.sh

# build a single mod to standalone .vpk (./mods/remove-esc-menu-animations.patch)
./build/nix/build.sh remove-esc-menu-animations

# two mods as one VPK; the build applies them in this order
./build/nix/build.sh always-show-ability-suggestions hide-ability-suggestions-in-street-brawl
```

A mod argument can be the name, the file name or the path (`mods/<name>.patch`).
`just build <mods>` does the same inside `nix develop`.

| Variable | Use |
| --- | --- |
| `GAME_DIR` | The `Deadlock/game` folder, if it is not at `~/.steam/steam/steamapps/common/Deadlock/game`. |
| `CSDK_PATH` | A local unpacked `Reduced_CSDK_12` tree, in place of the pinned download. |

### Output

The build prints the paths at the end:

- `result/pak75_dir.vpk` for all mods,
  or `result-<a>+<b>/<a>+<b>.vpk` for the named ones.
- `result-debug` (or `result-<a>+<b>-debug`):
  `build-info.txt`,
  the decompiled game files (`step-0`),
  the state after each mod (`step-1` and on),
  the staged VPK files (last step),
  and a 7z of the VPK in `release/`.

The same mods and the same game build give the same VPK bytes.

To install the VPK by hand,
copy it to `Deadlock/game/citadel/addons/` with a free `pakNN_dir.vpk` name.
The game reads that folder only after the usual `gameinfo.gi` change for mods.
A mod manager such as Grimoire does both for you.

### After a game update

Build again.
Most mods apply to the new game files with no change.
If a mod does not apply,
the build names the mod and its target files:
re-derive that mod from the new game files (see below).

### Troubleshooting

If the CSDK download fails,
point the build at a local unpacked `Reduced_CSDK_12` tree:

```bash
CSDK_PATH=/path/to/Reduced_CSDK_12 ./build/nix/build.sh
```

## Make a mod

A mod is a diff over the decompiled game files.
Decompile the files that you want to change into a work folder,
stage them in a throwaway git index,
edit them,
then write the diff with a header.

```bash
nix develop
export DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1
GAME="$HOME/.steam/steam/steamapps/common/Deadlock/game"
W="$(mktemp -d)"

# 1. Decompile. -f takes VPK paths with the compiled suffix, separated by commas.
#    Each file lands at its VPK path: $W/panorama/styles/hud.css
Source2Viewer-CLI -i "$GAME/citadel/pak01_dir.vpk" -d -o "$W" \
  -f panorama/styles/hud.vcss_c,panorama/layout/hud.vxml_c
git -C "$W" init -q && git -C "$W" add -A

# 2. Edit the files in $W.
#    Put new files under a folder named after the mod,
#    for example $W/panorama/styles/my-mod/main.css.

# 3. Write the mod.
git -C "$W" add -N .
{
  printf '# spec: diffmod/v1\n'
  printf '# title: My mod\n'
  printf '# decompiler: source2viewer-cli/20.1\n'
  git -C "$W" diff --no-ext-diff --src-prefix=a/ --dst-prefix=b/
} > mods/my-mod.patch
```

The compiled suffixes are `.vcss_c` (`.css`), `.vxml_c` (`.xml`) and `.vjs_c` (`.js`).
Raw files such as `panorama/citadel_keybinds.cfg` have no compiled form:
extract them without `-d`.
A new `.css`, `.xml` or `.js` file needs a hook in a game file,
for example one `<include>` line in a layout.

## Toolchain

The Nix packages for the CSDK compiler (under Wine) and the decompiler
are described in [nix-toolchain/README.md](nix-toolchain/README.md).
