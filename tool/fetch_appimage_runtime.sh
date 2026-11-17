#!/usr/bin/env bash
# Download and verify the pinned AppImage runtime and its source archives.
set -euo pipefail
if [[ $# != 1 ]]; then
  echo 'Usage: bash tool/fetch_appimage_runtime.sh OUTPUT_DIRECTORY' >&2
  exit 64
fi
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
output="$(realpath -m -- "$1")"
specification="$root/packaging/appimage/build-inputs.json"
items="$(jq -ec '[.runtime, .runtime_sources[]]' "$specification")"
mkdir -p -- "$output"
while IFS= read -r item; do
  name="$(jq -er '.file' <<< "$item")"
  digest="$(jq -er '.sha256' <<< "$item")"
  url="$(jq -er '.url' <<< "$item")"
  target="$output/$name"
  if [[ ! -f $target ]] || ! printf '%s  %s\n' "$digest" "$target" | sha256sum --check --status; then
    temporary="$target.part"
    curl --fail --silent --show-error --location --retry 3 --max-time 180 \
      "$url" --output "$temporary"
    if ! printf '%s  %s\n' "$digest" "$temporary" | sha256sum --check --status; then
      rm -- "$temporary"
      echo "Checksum does not match: $name" >&2
      exit 1
    fi
    mv -- "$temporary" "$target"
  fi
done < <(jq -c '.[]' <<< "$items")
jq . "$specification" > "$output/build-inputs.json"
echo "Verified AppImage runtime inputs: $output"
