#!/usr/bin/env bash
set -euo pipefail

usage='Usage: nix run .#tag -- [--push | --help]'
if (($# > 1)); then
  echo "$usage" >&2
  exit 2
fi
push=false
case "${1:-}" in
  '') ;;
  --push) push=true ;;
  --help|-h)
    printf '%s\n\n%s\n' "$usage" \
      'Sign and verify the pubspec.yaml version tag at HEAD; --push sends it to origin.'
    exit 0
    ;;
  *) echo "$usage" >&2; exit 2 ;;
esac

cd "$(git rev-parse --show-toplevel)"
commit=$(git rev-parse HEAD)
if [[ -n "$(git status --porcelain)" ]]; then
  echo 'Commit or stash working-tree changes before tagging.' >&2
  exit 1
fi

version=$(git show "$commit:pubspec.yaml" | yq -r '.version')
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$ ]]; then
  echo "Unsupported pubspec.yaml version: $version" >&2
  exit 1
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
