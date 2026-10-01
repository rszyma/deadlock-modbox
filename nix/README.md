# Toolchain

Reduced CSDK 12 (Deadlock community SDK) as Nix derivations, with the
Windows tools wrapped to run under Wine. The SDK is fetched by hash and
unpacked into the Nix store.

## Packages

All of it is exposed (`nix flake show`) and on `PATH` inside
`nix develop`: `deadlock-csdk`, `deadlock-resourcecompiler`,
`deadlock-cfgvpk`, `source2viewer-cli`, plus `vpk`, `python3`, `jq`.

Binary flavors: `CSDK_BIN=bin|bin_cs2|bin_server|bin_tools` (default
`bin_cs2` - the only flavor that passes the schema check).

## Compiling panorama

Only `_c` files load in game - raw sources never do. Layout:

```
modroot/
  content/citadel_addons/<addon>/panorama/{layout/*.xml,styles/*.css}  # inputs
  game/citadel/gameinfo.gi          # writable copy
  game/citadel/bin -> <csdk>/game/citadel/bin   # symlink
  game/citadel_addons/<addon>/      # _c outputs land here
  game/core/panorama/panorama_config.txt  # copy from the CSDK, not from a VPK extract
```

Run with cwd inside `modroot/game`, headless:

```bash
cd modroot/game
WINEPREFIX=~/.wine64-dxvk WINEDLLOVERRIDES="d3d11,dxgi=n" \
VK_ICD_FILENAMES=<mesa>/share/vulkan/icd.d/lvp_icd.x86_64.json \
LD_LIBRARY_PATH=<vulkan-loader>/lib \
deadlock-resourcecompiler -v -f -game "Z:\path\to\modroot\game\citadel" \
  "Z:\path\to\modroot\content\citadel_addons\<addon>\panorama\layout\hud.xml"
```

DXVK (`d3d11.dll`+`dxgi.dll`) goes into the prefix `system32` with the
overrides above. `VK_ICD_FILENAMES` forces llvmpipe for headless machines -
unset it where a real GPU exists.

## Notes

- First build downloads ~2.6GB (hash-pinned; a replaced upstream file
  fails loudly - re-pin the hash in `nix/packages/deadlock-csdk.nix`).
- The CSDK predates the current engine. Compiled panorama loads fine;
  other compiled assets (models, materials, textures) are unverified and
  may be silently ignored.
