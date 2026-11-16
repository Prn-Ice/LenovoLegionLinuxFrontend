#!/usr/bin/env bash
# Build fresh experimental packages in the normal Ubuntu builder.
set -euo pipefail
if [[ $# != 4 || ! $1 =~ ^(A|B)$ || ! $2 =~ ^(deb|appimage)$ ]]; then
  echo 'Usage: build_experimental_packages.sh A|B deb|appimage PRIVATE_CONSUMER OUTPUT' >&2
  exit 64
fi
variant=$1
format=$2
consumer=$(realpath "$3")
output=$(realpath -m "$4")
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
git_common=$(git -C "$root" rev-parse --path-format=absolute --git-common-dir)
export_root=/tmp/opencode/flutter-shutdown-engine-experiment/export
[[ ! -e $output ]]
[[ -z $(git -C "$root" status --porcelain) ]]
mkdir -p "$output"
name="lllf-shutdown-${variant,,}-$format"
# ShellCheck cannot follow the EXIT trap that owns container cleanup.
# shellcheck disable=SC2329
cleanup() { timeout 30 docker stop -t 10 "$name" >/dev/null 2>&1 || true; }
trap cleanup EXIT
arguments=(dart tool/package_deb.dart --output "$output/release")
if [[ $format == appimage ]]; then
  arguments=(dart tool/package_appimage.dart --runtime-inputs "$consumer/runtime-inputs" --output "$output/release")
fi
docker image inspect --format '{{.Id}}' lllf-deb-builder:ubuntu22.04 > "$output/builder-image.txt"
set +e
timeout -k 30s 2700s docker run --rm --init --name "$name" --user "$(id -u):$(id -g)" \
  -v "$root:$root" -v "$git_common:$git_common:ro" \
  -v "$consumer:$consumer" -v "$output:$output" \
  -v "$export_root:$export_root:ro" -w "$root" \
  -e HOME="$consumer/home" -e PUB_CACHE="$consumer/pub-cache" \
  -e PATH="$consumer/flutter-sdk/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
  -e LLLF_ENGINE_EXPORT="$export_root" -e LLLF_APP_VARIANT="$variant" \
  lllf-deb-builder:ubuntu22.04 "${arguments[@]}" 2>&1 | tee "$output/build.log"
status=${PIPESTATUS[0]}
set -e
echo "$status" > "$output/build.exit"
exit "$status"
