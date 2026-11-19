# R2 uploads and trim verification. Run with `just` inside `nix develop`.
# Uploads need R2 credentials in env: R2_ACCOUNT_ID, R2_ACCESS_KEY_ID,
# R2_SECRET_ACCESS_KEY, R2_BUCKET. The full CSDK blob is checked without
# any account via `nix run .#verify-csdk -- <gdrive zip>`; verify-csdk-trim
# below rebuilds locally, so run it from this repo with GAME_DIR set.

TRIM_URL := env_var_or_default("TRIM_URL", "https://pub-e045e6ce2c594838a11c17b87ad8cfa5.r2.dev/deadlock-trim-csdk.tar.zst")

[private]
guard-r2:
    #!/usr/bin/env bash
    set -euo pipefail
    : "${R2_ACCOUNT_ID:?set R2_ACCOUNT_ID}"
    : "${R2_ACCESS_KEY_ID:?set R2_ACCESS_KEY_ID}"
    : "${R2_SECRET_ACCESS_KEY:?set R2_SECRET_ACCESS_KEY}"
    : "${R2_BUCKET:?set R2_BUCKET}"

# Upload the full CSDK zip as-is (managers fetch it never; it exists as
# the trust root that trim rebuilds from). Pass a zip or set CSDK_ZIP:
upload-csdk-to-r2 file: guard-r2
    #!/usr/bin/env bash
    set -euo pipefail
    cd "{{ justfile_directory() }}"
    export RCLONE_CONFIG_R2_TYPE=s3 RCLONE_CONFIG_R2_PROVIDER=Cloudflare
    export RCLONE_CONFIG_R2_ENDPOINT="https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com"
    export RCLONE_CONFIG_R2_ACCESS_KEY_ID="${R2_ACCESS_KEY_ID}"
    export RCLONE_CONFIG_R2_SECRET_ACCESS_KEY="${R2_SECRET_ACCESS_KEY}"
    rclone copyto "{{ file }}" "R2:${R2_BUCKET}/Reduced_CSDK_12.zip" --progress

# Pack and upload the trim tarball. Prints the SRI hash to pin in
# nix-toolchain/deadlock-trim-csdk-bin/package.nix.
upload-csdk-trim-to-r2: guard-r2
    #!/usr/bin/env bash
    set -euo pipefail
    cd "{{ justfile_directory() }}"
    test -e result-trim || ./nix-toolchain/deadlock-trim-csdk/build-trim.sh
    tar -c --zstd --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner \
      -f deadlock-trim-csdk.tar.zst -C "$(readlink -f result-trim)" .
    nix hash file --sri deadlock-trim-csdk.tar.zst
    export RCLONE_CONFIG_R2_TYPE=s3 RCLONE_CONFIG_R2_PROVIDER=Cloudflare
    export RCLONE_CONFIG_R2_ENDPOINT="https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com"
    export RCLONE_CONFIG_R2_ACCESS_KEY_ID="${R2_ACCESS_KEY_ID}"
    export RCLONE_CONFIG_R2_SECRET_ACCESS_KEY="${R2_SECRET_ACCESS_KEY}"
    rclone copyto deadlock-trim-csdk.tar.zst "R2:${R2_BUCKET}/deadlock-trim-csdk.tar.zst" --progress

# Independent verification of the trim blob: rebuild the trim tree locally
# from the full CSDK plus your game files, then check it against the public
# endpoint (or pass one: just verify-csdk-trim file:///tmp/x.tar.zst).
# Thin wrapper over `nix run .#verify-csdk-trim`; no trust in the uploader
# needed and no account needed; rebuild or expose a mismatch.
verify-csdk-trim url=TRIM_URL:
    #!/usr/bin/env bash
    set -euo pipefail
    cd "{{ justfile_directory() }}"
    test -e result-trim || ./nix-toolchain/deadlock-trim-csdk/build-trim.sh
    nix run .#verify-csdk-trim -- "$(readlink -f result-trim)" "{{ url }}"
