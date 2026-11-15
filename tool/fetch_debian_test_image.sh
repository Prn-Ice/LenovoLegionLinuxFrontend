#!/usr/bin/env bash
# Verify the official Debian 12 cloud image before using it in a disposable VM.
set -euo pipefail
if [[ $# != 1 ]]; then
  echo 'Usage: bash tool/fetch_debian_test_image.sh OUTPUT_IMAGE' >&2
  exit 64
fi
image="$(realpath -m -- "$1")"
if [[ -e $image ]]; then echo "Output already exists: $image" >&2; exit 1; fi
base=https://cloud.debian.org/images/cloud/bookworm/latest
name=debian-12-genericcloud-amd64.qcow2
curl --fail --silent --show-error --location --retry 3 --max-time 60 \
  "$base/SHA512SUMS" -o "$image.SHA512SUMS"
expected="$(awk -v name="$name" '$2 == name || $2 == "*" name {print $1}' "$image.SHA512SUMS")"
if [[ ! $expected =~ ^[[:xdigit:]]{128}$ ]]; then
  echo 'The official checksum list has no unique Debian amd64 image entry.' >&2
  exit 1
fi
curl --fail --silent --show-error --location --retry 3 --max-time 600 \
  "$base/$name" -o "$image"
printf '%s  %s\n' "$expected" "$image" | sha512sum --check --status
sha256sum "$image" | cut -d' ' -f1 > "$image.sha256"
