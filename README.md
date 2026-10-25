# deadlock-modbox

![modbox logo](assets/logo.svg)

> Composable Deadlock UI mods built from .patch files.

## What this project solves

A Problem: Deadlock mods on sites like Gamebanana are distributed as .vpk files, which is a compiled, human-unreadable format, making them hard to audit and modify.

An even bigger problem with these, is that .vpk's are often incompatible with each other, and often break on game updates.

This project - Modbox - strives to solve (or remedy) the above issues.

## How does it work

In Modbox, mods are available as plain .patch files - this makes them human-readable, and easy to fix / modify / tweak.
In practice, it also makes mods of often fix themselves after Deadlock update breaks them, just by recompiling them agains latest Deadlock game files.

Mods collisions - all of your selected Modbox mods are compiled and merged into a single .vpk file. Any collisions between Modbox mods are detected at build time, and never collide in a mod manager.

Unlike other existing solutions for Deadlock modding (I know of), Modbox enables compiling .vpk natively on Linux, from CLI interface. This also makes mods creation with LLMs first-class.

### Comparison table

| | classic mods (.vpk) | Modbox mods (.patch) |
|---|---|---|
| Can you tell which game files it edits and how? | ❌ not easily; requires decompilation and diff tools to see what changed | ✅ yes; A mod is a plain-text file of changes, that should be applied to game files |
| When two mods edit the same game file | ❌ such mods are incompatible; second mod overwrites the first | ✅ both mods usually easily merge into one build<sup>*<sup> |
| When Deadlock updates and mods break | ❌ every mod author must reupload, you wait | ✅ often fixes itself after rebuild; can be done automatically on game launch |
| Mods for models, sounds, textures | ✅ supported, may change any resource type | ❌ not supported; patches only cover panorama UI files such as .xml / .css / .js |

> *: the only exception is when both mods touch the same lines/parts of gamefiles, which is quite rare for mods that change different things.

## Mod list in this repository

This repository contains several UI mods.
They are completely usable and kept up to date (by me),
and serve as examples of how mods made with Modbox look like.

- **Remove Esc Menu Animations** - removes the open/close animations from the pause menu, it opens instantly.
- **Always show ability suggestions** - Deadlock marks the
  next upgrade your build wants with a small badge, but normally shows
  it only when you open the details view. This shows it all the time.
- **Hide ability suggestions in Street Brawl** - hides the build-suggestion badge in Street Brawl mode, useful to mitigate
  [the bug with stuck suggestion badge](https://forums.playdeadlock.com/threads/minor-bug-with-suggested-ability-on-pocket-in-street-brawl.166966/)
- **Hide upgrade reminder** - hides the "hold <key> to upgrade" banner above the abilities.
- **Click outside to close shop** - clicking empty areas around the shop (side margins, the search column's empty areas) exits the upgrade shop, same as ESC. Uses the vanilla pattern from the shop's own Back footer (a plain panel with onactivate), applied at three levels so transparent overlays cannot swallow the click. Clicks on items, buttons and text entries are claimed by that content, and gaps between items are explicitly excluded - only the areas outside the content close it.
- **Click outside to close imbue dialog** - clicking the dimmed area around the imbue/ability-select dialog cancels it, same as ESC or its Cancel button. Same pattern: the dialog root carries the Cancel action and is forced full-screen, while the dialog content block swallows its own clicks so slots and buttons are unaffected.
- **Imbue cancel with mouse back** - pressing the mouse back button (mouse4) while the imbue/ability-select dialog is open cancels it, exactly like ESC. Capture happens below the game keybinds in panorama's own keybind file, so it works even when mouse4 is also bound to a game action like dash. No settings changes needed.
- **ESC Play button** - adds a Play button to the ESC pause menu, like QOL Lock does, so you can open the match-launch page without Hideout terminals. Standalone alternative to QOL Lock - this adds only Play.


## Building mods

The above mods are located in `./mods` directory. Each `.patch` file there is a separate mod, that might be build as standalone `.vpk`, or combined together with other mods (`.patch` files) into a single `.vpk`.

First, following dependencies are required:
- [Nix](https://nixos.org/download/) package manager (build tool)
- the Deadlock game installed through Steam.

Then, building .vpk from `./mods` directory is done end-to-end using `build.sh` command. Examples:
```bash
# build all mods in ./mods directory as one .vpk
./build.sh

# build a single mod to standalone .vpk (./mods/remove-esc-menu-animations.patch)
./build.sh remove-esc-menu-animations

# combine 2 mods to a single .vpk
./build.sh always-show-ability-suggestions hide-upgrade-reminder
```

After the build successfully completes, you will see a path to VPK file.
This file is ready to be dropped into a game directory, or installed without your mod manager (I recommend Grimoire).

### Troubleshooting

If the CSDK download fails (its Google Drive file changes hash), point the build at a local unpacked `Reduced_CSDK_12` tree instead:

```bash
CSDK_PATH=/nix/store/...-Reduced_CSDK_12 ./build.sh
```

On game updates, when your mods stop working,
first try to rebuild whem using `./build.sh` (as above).
Chances are your issue will get fixed by itself, but there's also a chance the patch stopped working and needs an adjustment.

## Creating new mods

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

The same workflow works for layout (`.xml` -> `.vxml_c`) and script
(`.js` -> `.vjs_c`) files. A patch may also *add* a new file (for
example a new `panorama/scripts/*.js` included from a patched layout)
using a `--- /dev/null` + `+++ b/<path>` hunk; the build then skips
decompiling it and compiles it directly.
