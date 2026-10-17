# source2viewer-cli (vendored)

Copy of nixpkgs' `pkgs/by-name/so/source2viewer-cli/{package.nix,deps.json,update.sh`,
bumped to 20.1 while nixpkgs-unstable still ships 19.2.

Why: the Oct 16 2026 Deadlock update changed the panorama binary format and
19.2 crashes on every `*.vcss_c` decompile
(`UnexpectedMagicException: Unknown KVType for variable 'datatype': 26`),
which broke all mod builds with a cryptic `find: .../fresh-0` error.
Upstream 20.1 ("adds support for files from the latest CS2 and Deadlock
updates") decompiles the current game files fine.

Revert to `pkgs.source2viewer-cli` (flake.nix + default.nix) once nixpkgs
ships >= 20.1, then delete this directory.

Updating (same flow as nixpkgs, see update.sh):

```bash
# 1. bump `version` in package.nix
# 2. delete the `hash`, rebuild once to read the real one from the error:
#    nix-build -E 'with import <nixpkgs> {}; callPackage ./nix/packages/source2viewer-cli/package.nix {}'
#    (a stale-but-valid hash silently reuses the OLD sources from the store,
#    so never guess - always read the `got:` line)
nix-build -E 'with import <nixpkgs> {}; (callPackage ./nix/packages/source2viewer-cli/package.nix {}).fetch-deps' -o /tmp/s2v-fetch-deps
/tmp/s2v-fetch-deps   # regenerates deps.json in place, no args needed
```
