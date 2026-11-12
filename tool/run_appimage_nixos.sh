#!/usr/bin/env bash
# Supply NixOS loader paths while retaining the host ownership and process view.
set -euo pipefail
if [[ $# == 0 ]]; then
  echo 'Usage: nix run .#appimage-run -- APPIMAGE [ARGUMENTS...]' >&2
  exit 64
fi
for directory in / /nix/store; do
  if [[ $(stat -Lc '%u' "$directory") != 0 ]]; then
    echo 'Cannot launch with hidden root ownership. Run this command from a normal host terminal outside the FHS or user namespace.' >&2
    exit 1
  fi
done
image=$(realpath -- "$1")
shift
scratch=$(mktemp -d /tmp/legion-appimage-run.XXXXXXXX)
trap 'rm -rf -- "$scratch"' EXIT
export LLLF_APPIMAGE_INPUT="$image"
python3 - "$scratch/inputs.json" <<'PY'
import json
import os
import sys
from pathlib import Path
Path(sys.argv[1]).write_text(json.dumps({
    'image': os.environ['LLLF_APPIMAGE_INPUT'],
    'nixpkgs': os.environ['LLLF_APPIMAGE_NIXPKGS'],
    'packaging': os.environ['LLLF_APPIMAGE_PACKAGING'],
}))
PY
package=$(nix build --impure --no-link --print-out-paths --expr "
  let
    config = builtins.fromJSON (builtins.readFile $scratch/inputs.json);
    pkgs = import config.nixpkgs { system = \"x86_64-linux\"; };
    image = builtins.path { path = config.image; name = \"legion-frontend.AppImage\"; };
  in pkgs.callPackage config.packaging { inherit image; }
")
rm -rf -- "$scratch"
trap - EXIT
exec "$package/bin/legion-frontend" "$@"
