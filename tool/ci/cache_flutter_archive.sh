#!/usr/bin/env bash
# Print the path to a verified SDK archive. Keep the last good file if a
# download fails; an incomplete download must never look like a cache hit.
set -euo pipefail
spec=packaging/appimage/build-inputs.json
digest="$(jq -er '.flutter.sha256' "$spec")"
archive="$1"
mkdir -p "$(dirname "$archive")"
verified() {
  [[ -f $1 ]] && printf '%s  %s\n' "$digest" "$1" | sha256sum --check --status
}
if ! verified "$archive"; then
  partial="$(mktemp "$archive.XXXXXXXX")"
  trap 'rm -f "$partial"' EXIT
  curl --fail --silent --show-error --location --retry 3 --max-time 900 \
    "$(jq -er '.flutter.url' "$spec")" -o "$partial"
  verified "$partial" || { echo 'Flutter archive checksum mismatch.' >&2; exit 1; }
  mv "$partial" "$archive"
fi
printf '%s\n' "$archive"
