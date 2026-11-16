#!/usr/bin/env bash
# Keep the first ordinary AppImage failure authoritative while collecting evidence.
set -euo pipefail
[[ $(id -u) == 0 && $(systemd-detect-virt --vm || true) == kvm ]]
output=/root/appimage-core-diagnostic
finish_diagnostic() {
  local status=$? collection_status=0 archive_status=0
  trap - EXIT
  timeout 600 bash control/test/appimage_core_diagnostic.sh collect "$output" "$status" \
    > /root/appimage-core-collection.log 2>&1 || collection_status=$?
  mkdir -p "$output"
  cp /root/appimage-core-collection.log "$output/"
  printf 'qualification=%s\ncollection=%s\n' "$status" "$collection_status" > "$output/diagnostic-status.txt"
  timeout 240 tar -czf /root/appimage-qualification.tar.gz -C /root appimage-core-diagnostic \
    2> /root/appimage-core-archive.log || archive_status=$?
  printf 'qualification=%s\ncollection=%s\narchive=%s\n' "$status" "$collection_status" "$archive_status"
  if (( status != 0 )); then exit "$status"; fi
  if (( collection_status != 0 )); then exit "$collection_status"; fi
  exit "$archive_status"
}
trap finish_diagnostic EXIT
bash control/test/qualify_appimage_ubuntu.sh
