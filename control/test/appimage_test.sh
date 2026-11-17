#!/usr/bin/env bash
# Check release launch and the bundled helper from FUSE and extraction.
# shellcheck disable=SC2016
set -euo pipefail
support=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=control/test/portable_session_test.sh
source "$support/portable_session_test.sh"
# shellcheck source=control/test/distro_test_support.sh
source "$support/distro_test_support.sh"
declare -A app=()
assert_disposable_vm
directory=$1
(cd "$directory" && sha256sum --check SHA256SUMS)
images=("$directory"/*.AppImage)
manifests=("$directory"/legion-frontend-*.json)
image=${images[0]} manifest=${manifests[0]}
jq -e '.portable_control and .default_control_mode == "privilegedControlHelper" and .host_executables == ["/bin/sh", "dirname", "mktemp", "rm"] and .native_runtime.helper.linkage == "static"' "$manifest"
ldconfig -p >/tmp/legion-ldconfig
reject grep -F libgtk-3.so.0 /tmp/legion-ldconfig
echo "ARTIFACT_SHA256 $(jq -r --arg name "$(basename "$image")" '.files[$name]' "$manifest") $(basename "$image")"
test ! -e /usr/lib/jvm
before=$(mktemp)
persistent_files >"$before"
mount_pid=
cleanup() {
  if [[ -n $mount_pid ]]; then
    kill -TERM -- "-$mount_pid" 2>/dev/null || true
    for ((attempt=0; attempt<50; attempt++)); do
      kill -0 -- "-$mount_pid" 2>/dev/null || break
      sleep 0.1
    done
    kill -KILL -- "-$mount_pid" 2>/dev/null || true
    wait "$mount_pid" 2>/dev/null || true
    mount_pid=
  fi
  rm -f /tmp/legion-unsealed-cleanup
}
trap cleanup EXIT
check_helper() {
  local appdir=$1 helper elf documents digest
  helper=$appdir/usr/lib/legion_frontend/libexec/legion-portable-control
  elf=$(as_user approved readelf -lW -dW "$helper")
  [[ $elf != *INTERP* && $elf != *'(NEEDED)'* ]]
  documents=$(as_user approved "$appdir/usr/bin/xdg-user-dir" DOCUMENTS)
  [[ $documents == /home/approved* ]]
  digest=$(as_user approved sha256sum "$helper")
  [[ ${digest%% *} == "$(jq -r '.appdir["./usr/lib/legion_frontend/libexec/legion-portable-control"].sha256' "$manifest")" ]]
  session_new app approved "$helper" false
  [[ ${app[cli]} == /usr/local/bin/legion_cli ]]
  session_prepare app success
  session_send app connect
  session_send app authorize
  session_send app enable
  printf 'enabled\n' | diff - <(session_value app battery-conservation)
  session_send app disable
  printf 'disabled\n' | diff - <(session_value app battery-conservation)
  reject grep -F .so "/proc/${app[helper]}/maps"
  session_close app
  wait_collected
}
setsid runuser -u approved -- "$image" --appimage-mount >/home/approved/appimage-mount.out 2>/home/approved/appimage-mount.err &
mount_pid=$!
wait_until 15 grep '^/tmp/.mount_' /home/approved/appimage-mount.out
mountpoint=$(head -n1 /home/approved/appimage-mount.out)
[[ $mountpoint == /tmp/.mount_* ]]
check_helper "$mountpoint"
echo 'PASS: bundled helper from FUSE with synthetic write/readback/restore'
cleanup
timeout 420 bash "$support/desktop_test_support.sh" "$image" appimage-gui-fuse.log fuse '' true
extraction='/home/approved/Extracted app with spaces'
as_user approved mkdir -p "$extraction"
as_user approved bash -c 'cd "$1"; "$2" --appimage-extract >/dev/null' bash "$extraction" "$image"
appdir=$extraction/squashfs-root
helper=$appdir/usr/lib/legion_frontend/libexec/legion-portable-control
size=$(jq -r .native_runtime.helper.cleanup.size "$manifest")
digest=$(jq -r .native_runtime.helper.cleanup.sha256 "$manifest")
found=false
# Match every embedded ELF candidate against the release's recorded cleanup hash.
while IFS=: read -r offset _; do
  ((offset > 0)) || continue
  dd if="$helper" of=/tmp/legion-unsealed-cleanup bs=1 skip="$offset" count="$size" status=none
  candidate=$(sha256sum /tmp/legion-unsealed-cleanup)
  if [[ ${candidate%% *} == "$digest" ]]; then found=true; break; fi
done < <(LC_ALL=C grep -abo $'\x7fELF' "$helper")
[[ $found == true ]] || fail 'The recorded cleanup ELF is not embedded in the helper.'
chmod 555 /tmp/legion-unsealed-cleanup
expect_status 2 timeout 5 /tmp/legion-unsealed-cleanup >/tmp/legion-unsealed.out
test ! -s /tmp/legion-unsealed.out
expect_status 2 timeout 5 runuser -u approved -- /tmp/legion-unsealed-cleanup >/tmp/legion-unsealed.out
test ! -s /tmp/legion-unsealed.out
rm /tmp/legion-unsealed-cleanup
check_helper "$appdir"
echo 'PASS: bundled helper from extraction with synthetic write/readback/restore'
timeout 420 bash "$support/desktop_test_support.sh" "$appdir/AppRun" appimage-gui-extracted.log extracted '' true
wait_until 10 bash -c 'test -z "$(findmnt -rn -t fuse,fuse.squashfuse)"'
diff "$before" <(persistent_files)
rm "$before"
assert_cleanup_succeeded
echo 'PASS: AppImage FUSE/extraction qualification; persistent integration files unchanged'
