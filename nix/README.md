# deadlock-csdk-wine

Reduced CSDK 12 (Deadlock community SDK: CS2 workshop tools + community
fixes) packaged as Nix derivations, with its Windows tools wrapped to run
under Wine. No `/tmp` drops, no 6GB blobs in git — the SDK is fetched from
its Google Drive source by hash and unpacked into the Nix store.

## Packages

- `nix build .#deadlock-csdk` — the unpacked SDK tree (`Reduced_CSDK_12/...`)
- `nix build` — same (default)
- `nix run .#deadlock-resourcecompiler -- ...` — compile (args past `--`)
- `nix run .#deadlock-cfgvpk -- ...` — VPK packer
- `nix run .#source2viewer-cli -- ...` — decompiler from nixpkgs (native, no Wine;
binary is `Source2Viewer-CLI`)
- `nix develop` — shell with the wrappers + python3.

Binary flavors: `CSDK_BIN=bin|bin_cs2|bin_server|bin_tools` (default
`bin_cs2` — the only flavor that passes the schema check).

Wine state: set `WINEPREFIX` to a path that survives your environment
(first run auto-installs pinned upstream DXVK
dlls (`d3d11.dll`+`dxgi.dll`, `nix/packages/dxvk-dlls.nix`) into the prefix.

## Example: compile panorama sources

```bash
deadlock-resourcecompiler -game /path/to/game/citadel panorama/layout/hud.xml
```

(`WINEDEBUG=-all` keeps it quiet.)

## Compiling Deadlock panorama (working recipe)

Use the `bin_cs2` flavor (`CSDK_BIN=bin_cs2`; the others abort on schema
mismatches). It needs D3D (DXVK + llvmpipe Vulkan) and a specific modroot
layout — raw sources are NOT compiled, only `_c` loads in game:

```
modroot/
  content/citadel_addons/<addon>/panorama/{layout/*.xml,styles/*.css}  # inputs
  game/citadel/gameinfo.gi          # CSDK's copy (writable)
  game/citadel/bin -> <csdk>/game/citadel/bin   # symlink (modtools.dll lives here)
  game/citadel_addons/<addon>/       # _c outputs land here
  game/core/panorama/                # REAL files: copy panorama_config.txt
                                      # from <csdk>/game/core/panorama
                                      # (snapshot VPK extracts of it can be
                                      # corrupt; the CSDK copy parses clean)
  game/core/  (empty dir, may be required to exist)
```

Run with cwd inside `modroot/game`, headless env, e.g.:

```bash
cd modroot/game
WINEPREFIX=~/.wine64-dxvk WINEDLLOVERRIDES="d3d11,dxgi=n" \
VK_ICD_FILENAMES=<mesa>/share/vulkan/icd.d/lvp_icd.x86_64.json \
LD_LIBRARY_PATH=<vulkan-loader>/lib \
deadlock-resourcecompiler -v -f -game "Z:\path\to\modroot\game\citadel" \
  "Z:\path\to\modroot\content\citadel_addons\<addon>\panorama\layout\hud.xml"
```

(`<mesa>`/`<vulkan-loader>` from nixpkgs; DXVK `d3d11.dll`+`dxgi.dll` copied
into the prefix `system32` with the overrides above; no display needed.)
Gotchas found the hard way: run from `modroot/game` or search paths resolve
to garbage; `assettypes_common.txt` must sit next to the exe's flavor dir
(bin_cs2 has it, plain `bin/` does not); CSDK's own DLL sets disagree across
flavors except bin_cs2.

## After an environment wipe

If your setup wipes `$HOME` and `/nix/store` between sessions (containers,
remote builders), keep the prefix and any checkouts on persistent storage.
Recovery:

```bash
nix build .#deadlock-csdk              # 2.6GB re-download, slow
nix run .#deadlock-resourcecompiler -- --help   # wrapper (wine64 from cache)
rm -rf $WINEPREFIX                           # fresh prefix; DXVK reinstalls itself
```

Then recompile as usual. The CSDK store path is input-addressed, so
modroot symlinks pointing at it keep working across re-downloads.

## Costs and caveats

- First build downloads ~2.6GB (the CSDK zip, hash-pinned). If upstream
replaces the file, the build fails loudly instead of silently changing
tools — re-pin the hash (see Source pinning).
- `VK_ICD_FILENAMES` in the recipe forces llvmpipe (software Vulkan) so
compiles work headless. On a machine with a real GPU, unset it and let
Wine/DXVK use the hardware ICD — much faster for texture/model compiles.
- Engine drift: the CSDK predates the current game build. Compiled panorama
(`_c`) loads fine; anything else the old compiler emits (models,
materials, textures) is unverified against the current engine and may be
silently ignored. Byte-patches of stock files are immune (format stays
native).

## Source pinning

`nix/packages/deadlock-csdk.nix` fetches the zip by content hash (`sha256-teK/...uk68=`).
If the upstream file is replaced, the build fails loudly instead of
silently using different tools — re-pin the hash then.
