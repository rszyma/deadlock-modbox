# deadlock-modbox

![modbox logo](assets/logo.svg)

Deadlock mods on Linux the opensource way.

## Introduction

Deadlock mods on Sites like Gamebanana are distributed in compiled, human-unreadable form, making them much harder to audit and modify. In modbox this is not the case - mods are available as plain .patch files.

Unlike other existing solutions for Deadlock modding, Modbox enables compiling .vpk on Linux from CLI interface. This enables LLMs to make mods more easily.

Detect mod collisions at build time. Mods are compiled and merged into a single .vpk file, so your mods never unexpectedly stop working trying to override the same game files.

## Mod list in this repository

- **Always show ability suggestions** - Deadlock marks the
  next upgrade your build wants with a small badge, but normally shows
  it only when you open the details view. This shows it all the time.
- **Instant ESC** - removes the open/close
  animations from the pause menu, it opens instantly.

Q: Only 2 mods?\
A: Currently yes :P. But the point is to spread the idea. Hopefully we will get more mods as .patch files with time!

## Usage - building .vpk file

You need [Nix](https://nixos.org/download/) and the game installed
through Steam.

Then, building .vpk from `./mods` directory is done end-to-end by following commands:
```bash
# build all mods in ./mods directory as one .vpk
./build.sh

# build only a specific mod into a .vpk
./build.sh always-show-ability-suggestions
./build.sh instant-esc
```

This produces `result/pak75_dir.vpk` (or `result-<mod>/<mod>.vpk` for a
single mod). Take the file and install it with your mod manager
(I recommend Grimoire). `nix eval '.#mods' --apply builtins.attrNames` lists every buildable mod.

On game updates, when your mods stop working,
first try to rebuild whem using `./build.sh` (as above).
Chances are your issue will get fixed by itself, but there's also a chance the patch stopped working and might need an adjustment.

## Adding new mods

Mods are text edits to the game's UI files, stored as `mods/*.patch`
(one file per mod, named after the mod). To make one:

```bash
nix develop
DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1 Source2Viewer-CLI -i "$HOME/.steam/steam/steamapps/common/Deadlock/game/citadel/pak01_dir.vpk" -d -o /tmp/fresh -f panorama/<path>/<file>.vcss_c
```

Edit the decompiled copy in `/tmp/fresh` (keep a pristine copy first),
then save the difference:

```bash
diff -u --label a/panorama/<path>/<file>.css --label b/panorama/<path>/<file>.css /tmp/orig.css /tmp/edited.css > mods/my-mod-name.patch
```
