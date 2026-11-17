#!/usr/bin/env bash
# Archive available Debian evidence without replacing the qualification result.

retain_deb_evidence() {
  local home=$1 archive=$2 qualification_status=$3 archive_status=0 file
  local files=()
  for file in "$home"/deb-*.{txt,log,json} "$home"/deb-os-release \
    "$home"/desktop-frame-*.png "$home"/desktop-diagnostics-*.txt; do
    if [[ -f $file ]]; then files+=("${file##*/}"); fi
  done
  timeout 90 tar -czf "$archive" -C "$home" --files-from=/dev/null "${files[@]}" || archive_status=$?
  if ((qualification_status != 0)); then return "$qualification_status"; fi
  return "$archive_status"
}
