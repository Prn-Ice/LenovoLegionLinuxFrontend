#!/usr/bin/env bash
set -euo pipefail

usage='Usage: nix run .#tag -- [--prepare VERSION | --push | --help]'
if (($# > 2)) || { (($# > 1)) && [[ $1 != --prepare ]]; }; then
  echo "$usage" >&2
  exit 2
fi
push=false
prepare=false
case "${1:-}" in
  '') ;;
  --prepare)
    if (($# != 2)); then
      echo "$usage" >&2
      exit 2
    fi
    prepare=true
    ;;
  --push) push=true ;;
  --help|-h)
    printf '%s\n\n%s\n%s\n' "$usage" \
      '--prepare VERSION updates pubspec.yaml and Nix metadata for a release PR.' \
      'Without --prepare, sign and verify the version tag at HEAD; --push sends it to origin.'
    exit 0
    ;;
  *) echo "$usage" >&2; exit 2 ;;
esac
cd "$(git rev-parse --show-toplevel)"
commit=$(git rev-parse HEAD)
if [[ -n "$(git status --porcelain)" ]]; then
  echo 'Commit or stash working-tree changes before preparing or tagging a release.' >&2
  exit 1
fi

version=$(git show "$commit:pubspec.yaml" | yq -r '.version')
if $prepare; then
  version=$2
fi
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$ ]]; then
  echo "Unsupported release version: $version" >&2
  exit 1
fi
if $prepare; then
  # Change only the version line; YAML reserialization removes blank lines.
  sed -i "s/^version:.*$/version: $version/" pubspec.yaml
  if [[ "$(yq -r '.version' pubspec.yaml)" != "$version" ]]; then
    echo 'Expected a top-level version: line in pubspec.yaml.' >&2
    exit 1
  fi
  bash tool/packaging/update_nix_metadata.sh
  echo "Prepared $version. Review and commit the changes, then open a PR."
  echo 'After merge, run nix run .#tag -- --push from the release commit.'
  exit 0
fi
tag="v${version%%+*}"
ref="refs/tags/$tag"

if git show-ref --verify --quiet "$ref"; then
  if [[ "$(git rev-parse "$ref^{commit}")" != "$commit" ]]; then
    echo "$tag already points to another commit." >&2
    exit 1
  fi
else
  git tag -s "$tag" "$commit" -m "$tag"
fi
git verify-tag "$ref"
printf 'Verified %s at %s\n' "$tag" "$commit"

if [[ "$push" == true ]]; then
  git -c push.followTags=false push origin "$ref:$ref"
else
  echo 'Run nix run .#tag -- --push to push this tag to origin.'
fi
