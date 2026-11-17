#!/usr/bin/env bash
# Archive available desktop evidence even when the GUI check fails.

retain_appimage_evidence() {
  local home=$1 archive=$2 qualification_status=$3
  local versions_status=0 cpu_status=0 manifest_status=0 archive_status=0
  local files=() file
  dpkg-query -W fuse3 libc6 libgl1-mesa-dri libglx-mesa0 libegl1 libegl-mesa0 \
    libgles2 libllvm15 > "$home/appimage-versions.txt" 2>&1 || versions_status=$?
  lscpu > "$home/appimage-cpu.txt" 2>&1 || cpu_status=$?
  cp "$home/AppImage with spaces/"legion-frontend-*.json \
    "$home/appimage-release-manifest.json" 2> "$home/appimage-manifest-copy.log" \
    || manifest_status=$?
  printf 'qualification=%s\nversions=%s\ncpu=%s\nmanifest=%s\n' \
    "$qualification_status" "$versions_status" "$cpu_status" "$manifest_status" \
    > "$home/appimage-evidence-status.txt"
  for file in "$home"/appimage-*.{txt,log,json} "$home"/desktop-frame-*.png \
    "$home"/desktop-diagnostics-*.txt "$home/appimage-native-qualification.tar.gz"; do
    if [[ -f $file ]]; then files+=("${file##*/}"); fi
  done
  timeout 90 tar -czf "$archive" -C "$home" "${files[@]}" || archive_status=$?
  if (( qualification_status != 0 )); then return "$qualification_status"; fi
  if (( archive_status != 0 )); then return "$archive_status"; fi
  (( versions_status == 0 && cpu_status == 0 && manifest_status == 0 ))
}
