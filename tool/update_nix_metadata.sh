#!/usr/bin/env bash
# Keep Nix's pure JSON inputs aligned with the Flutter manifests.
set -euo pipefail
if [[ $# -gt 1 || ( $# == 1 && $1 != --check ) ]]; then
  echo 'Usage: bash tool/update_nix_metadata.sh [--check]' >&2
  exit 64
fi
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
temporary="$(mktemp -d /tmp/legion-nix-metadata.XXXXXXXX)"
trap 'rm -rf -- "$temporary"' EXIT
for manifest in pubspec.yaml pubspec.lock; do
  name=${manifest%.yaml}
  yq -S . "$root/$manifest" > "$temporary/$name.json"
  if [[ ${1:-} == --check ]]; then
    diff -u "$root/packaging/nix/$name.json" "$temporary/$name.json"
  else
    mkdir -p "$root/packaging/nix"
    cp "$temporary/$name.json" "$root/packaging/nix/$name.json"
  fi
done
