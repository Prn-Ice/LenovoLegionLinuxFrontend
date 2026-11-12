#!/usr/bin/env bash
# Build a distro-native Debian package in an isolated Ubuntu container.
set -euo pipefail
if [[ $# != 2 ]]; then
  echo 'Usage: bash tool/build_deb.sh FLUTTER_SDK_ARCHIVE OUTPUT_DIRECTORY' >&2
  exit 64
fi
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
sdk="$(realpath -- "$1")"
output="$(realpath -m -- "$2")"
if [[ -e $output ]]; then echo "Output already exists: $output" >&2; exit 1; fi
if [[ -n $(git -C "$root" status --porcelain) ]]; then
  echo 'Debian packaging requires a clean checkout.' >&2
  exit 1
fi
expected="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["flutter"]["sha256"])' "$root/packaging/appimage/build-inputs.json")"
printf '%s  %s\n' "$expected" "$sdk" | sha256sum --check --status
mkdir -p -- "$output"
scratch="$(mktemp -d /tmp/legion-deb-build.XXXXXXXX)"
container=
cleanup() {
  if [[ -n $container ]]; then docker rm -f "$container" >/dev/null; fi
  rm -rf -- "$scratch"
}
trap cleanup EXIT
git clone --quiet --depth 1 --no-local --single-branch "file://$root" "$scratch/source"
test "$(git -C "$scratch/source" rev-parse HEAD)" = "$(git -C "$root" rev-parse HEAD)"
docker build --tag lllf-deb-builder:ubuntu22.04 \
  --file "$root/packaging/appimage/Dockerfile" "$root/packaging/appimage" > "$output/builder.log" 2>&1
container="$(docker create --user root --entrypoint bash lllf-deb-builder:ubuntu22.04 -c '
  set -e
  tar -xJf /tmp/flutter.tar.xz -C /opt
  rm /tmp/flutter.tar.xz
  chown -R builder:builder /opt/flutter /home/builder
  runuser -u builder -- bash -c "
    set -e
    cd /home/builder/source
    flutter config --no-analytics
    dart tool/package_deb.dart --output build/deb-output
  "
')"
docker cp "$sdk" "$container:/tmp/flutter.tar.xz"
docker cp "$scratch/source/." "$container:/home/builder/source"
docker start -a "$container" 2>&1 | tee "$output/build.log"
result="$(docker inspect --format '{{.State.ExitCode}}' "$container")"
if [[ $result != 0 ]]; then exit "$result"; fi
docker cp "$container:/home/builder/source/build/deb-output/." "$output"
docker inspect --format '{{.Image}}' "$container" > "$output/builder-image.txt"
echo "Built Debian package: $output"
