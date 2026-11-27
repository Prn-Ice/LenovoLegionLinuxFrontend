#!/usr/bin/env bash
# Test the packaged app's privileged controls through official appimage-run.
set -euo pipefail
if [[ $# != 2 ]]; then
  echo 'Usage: bash tool/ci/test_appimage_nixos.sh APPIMAGE OUTPUT_DIRECTORY' >&2
  exit 64
fi
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
image=$(realpath -- "$1")
output=$(realpath -m -- "$2")
if [[ -e "$output" ]]; then echo "Output already exists: $output" >&2; exit 1; fi
mkdir -p "$output"
scratch=$(mktemp -d /tmp/legion-appimage-nixos.XXXXXXXX)
trap 'rm -rf -- "$scratch"' EXIT
jq -n --arg flake "git+file://$root" --arg image "$image" '{flake:$flake, image:$image}' >"$scratch/inputs.json"
expression="
  let
    config = builtins.fromJSON (builtins.readFile $scratch/inputs.json);
    flake = builtins.getFlake config.flake;
    pkgs = import flake.inputs.nixpkgs { system = \"x86_64-linux\"; };
    image = builtins.path { path = config.image; name = \"legion-frontend.AppImage\"; };
  in import (flake.outPath + \"/control/test/appimage_nixos.nix\") { inherit pkgs image; }
"
# Nix exposes failed sandbox outputs here without registering a valid result.
test_output=$(nix eval --impure --raw --expr "$expression" --apply 'drv: drv.outPath')
set +e
nix build --impure --print-build-logs --out-link "$output/result" --expr "$expression" 2>&1 | tee "$output/build-and-vm.log"
statuses=("${PIPESTATUS[@]}")
set -e
if ((statuses[0] != 0)); then
  evidence=(-C "$output" build-and-vm.log)
  if [[ -d $test_output ]]; then
    evidence+=(-C "$test_output")
    for file in gui.log sway.log wayland.log wayland-launcher.log wayland-diagnostics gui-evidence; do
      if [[ -e $test_output/$file ]]; then evidence+=("$file"); fi
    done
  fi
  timeout 90 tar -czf "$output/appimage-nixos-failure-evidence.tar.gz" "${evidence[@]}" ||
    echo 'Could not archive all NixOS failure evidence; see build-and-vm.log.' >&2
  exit "${statuses[0]}"
fi
if ((statuses[1] != 0)); then exit "${statuses[1]}"; fi
jq -n --arg commit "$(git -C "$root" rev-parse HEAD)" \
  --arg hash "$(sha256sum "$image" | cut -d' ' -f1)" \
  '{commit:$commit, appimage_sha256:$hash,
    nixos:"official appimage-run desktop and privileged control verified",
    desktop_shutdown:"X11 close button and Wayland window close verified",
    hardware:"unverified", desktop_authentication:"unverified"}' >"$output/manifest.json"
tar -czf "$output/appimage-nixos-qualification.tar.gz" -C "$output" manifest.json build-and-vm.log \
  -C "$(realpath "$output/result")" gui.log sway.log wayland.log wayland-launcher.log wayland-diagnostics gui-evidence
