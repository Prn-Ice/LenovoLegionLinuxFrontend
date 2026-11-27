#!/usr/bin/env bash
# Both package formats use the same tools. The Dockerfile pins its base image
# and copies no files, so its checksum identifies this builder recipe.
set -euo pipefail
context="$(dirname "$0")/../../packaging/appimage"
digest="$(sha256sum "$context/Dockerfile")"
image="lllf-package-builder:${digest%% *}"
if [[ ${RUNNER_ENVIRONMENT:-} == self-hosted ]] && docker image inspect "$image" >/dev/null 2>&1; then
  echo "Using local $image" >&2
else
  docker build --tag "$image" --file "$context/Dockerfile" "$context" >&2
fi
printf '%s\n' "$image"
