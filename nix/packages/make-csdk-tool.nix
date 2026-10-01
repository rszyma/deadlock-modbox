{
  pkgs,
  csdk ? pkgs.callPackage ./deadlock-csdk.nix { },
  dxvkDlls ? pkgs.callPackage ./dxvk-dlls.nix { },
}:

# CSDK_BIN selects the binary flavor: bin | bin_cs2 | bin_server | bin_tools.
# Only bin_cs2 passes the schema check; the rest abort. Run with cwd
# inside modroot/game/ or search paths resolve to garbage (see README).
# First run copies DXVK's d3d11/dxgi into the prefix for headless D3D.
name: exe:
pkgs.writeShellScriptBin name ''
  bin="''${CSDK_BIN:-bin_cs2}"
  : "''${WINEPREFIX:=$HOME/.wine-deadlock-csdk}"
  export WINEPREFIX WINEDEBUG=-all
  export WINEDLLOVERRIDES="''${WINEDLLOVERRIDES:-d3d11,dxgi=n}"
  export VK_ICD_FILENAMES="''${VK_ICD_FILENAMES:-${pkgs.mesa}/share/vulkan/icd.d/lvp_icd.x86_64.json}"
  export LD_LIBRARY_PATH="''${LD_LIBRARY_PATH:-}:${pkgs.vulkan-loader}/lib"
  if [ ! -f "$WINEPREFIX/drive_c/windows/system32/dxgi.dll" ]; then
    mkdir -p "$WINEPREFIX/drive_c/windows/system32"
    tar -xzf ${dxvkDlls} -C "$WINEPREFIX/drive_c/windows/system32" \
      --strip-components=2 dxvk-2.7.1/x64/d3d11.dll dxvk-2.7.1/x64/dxgi.dll
  fi
  unset DISPLAY
  exec ${pkgs.wine64}/bin/wine "${csdk}/game/$bin/win64/${exe}" "$@"
''
