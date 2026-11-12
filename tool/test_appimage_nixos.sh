#!/usr/bin/env bash
# Test the exact AppImage through the host-namespace NixOS launcher.
set -euo pipefail
if [[ $# != 2 ]]; then
  echo 'Usage: bash tool/test_appimage_nixos.sh APPIMAGE OUTPUT_DIRECTORY' >&2
  exit 64
fi
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
image=$(realpath -- "$1")
output=$(realpath -m -- "$2")
if [[ -e "$output" ]]; then echo "Output already exists: $output" >&2; exit 1; fi
mkdir -p "$output"
scratch=$(mktemp -d /tmp/legion-appimage-nixos.XXXXXXXX)
trap 'rm -rf -- "$scratch"' EXIT
export LLLF_APPIMAGE_NIX_SOURCE="$root" LLLF_APPIMAGE_NIX_IMAGE="$image"
python3 - "$scratch/inputs.json" <<'PY'
import json
import os
import sys
from pathlib import Path
Path(sys.argv[1]).write_text(json.dumps({
    'flake': 'git+file://' + os.environ['LLLF_APPIMAGE_NIX_SOURCE'],
    'image': os.environ['LLLF_APPIMAGE_NIX_IMAGE'],
}))
PY
nix build --impure --print-build-logs --out-link "$output/result" --expr "
  let
    config = builtins.fromJSON (builtins.readFile $scratch/inputs.json);
    flake = builtins.getFlake config.flake;
    pkgs = import flake.inputs.nixpkgs { system = \"x86_64-linux\"; };
    image = builtins.path { path = config.image; name = \"legion-frontend.AppImage\"; };
    runner = flake.packages.x86_64-linux.appimage-run;
  in import (flake.outPath + \"/control/test/appimage_nixos.nix\") { inherit pkgs image runner; }
" 2>&1 | tee "$output/build-and-vm.log"
python3 - "$root" "$image" "$output" <<'PY'
import hashlib
import json
import subprocess
import sys
from pathlib import Path
root, image, output = map(Path, sys.argv[1:])
manifest = {
    'commit': subprocess.check_output(['git', '-C', str(root), 'rev-parse', 'HEAD'], text=True).strip(),
    'appimage_sha256': hashlib.sha256(image.read_bytes()).hexdigest(),
    'nixos': 'host-namespace desktop and static helper control verified',
    'hardware': 'unverified',
    'desktop_authentication': 'unverified',
}
(output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
PY
tar -czf "$output/appimage-nixos-qualification.tar.gz" -C "$output" manifest.json build-and-vm.log
