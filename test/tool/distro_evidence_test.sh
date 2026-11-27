#!/usr/bin/env bash
# Keep failure evidence and the original result before disposable VM cleanup.
# Fake programs and child shells expand their own variables.
# shellcheck disable=SC2016
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
# shellcheck source=control/test/helper_session_test.sh
source "$root/control/test/helper_session_test.sh"
fake() { printf '#!/usr/bin/env bash\n%s\n' "$2" >"$fixture/bin/$1"; chmod 755 "$fixture/bin/$1"; }
run_shell() {
  status=0
  timeout 10 bash -euo pipefail -c "$1" 'evidence test' "${@:2}" >"$fixture/stdout" 2>"$fixture/stderr" || status=$?
}
retrieve() {
  export JOURNAL=${2:-0} TRANSFER=${3:-0}
  fake ssh 'echo journal >> "$EVENTS"; exit "$JOURNAL"'
  fake scp 'echo archive >> "$EVENTS"; exit "$TRANSFER"'
  run_shell 'source "$1"; trap '\''echo cleanup >> "$EVENTS"'\'' EXIT; retrieve_distro_evidence "$2" appimage-qualification.tar.gz "$3" 2222 -i "key with spaces"' \
    "$root/tool/ci/distro_evidence.sh" "$fixture" "$1"
}
archive() {
  export COLLECTION=${2:-0}
  fake dpkg-query 'echo versions; exit "$COLLECTION"'
  fake lscpu "echo 'fixture CPU'"
  mkdir -p "$fixture/AppImage with spaces"
  printf '{}\n' >"$fixture/AppImage with spaces/legion-frontend-fixture.json"
  printf 'LLVM fixture failure\n' >"$fixture/appimage-gui-fuse.log"
  printf 'fixture maps\n' >"$fixture/appimage-runtime-fuse.txt"
  printf 'native qualification fixture\n' >"$fixture/appimage-native-qualification.tar.gz"
  run_shell 'source "$1"; retain_appimage_evidence "$2" "$2/evidence.tar.gz" "$3"' \
    "$root/control/test/appimage_evidence.sh" "$fixture" "$1"
}
failed_qualification() {
  retrieve 134
  [[ $status == 134 ]]
  diff <(printf '%s\n' journal archive cleanup) "$EVENTS"
  grep -F qualification=134 "$fixture/qualification-status.txt"
}
collection_errors() {
  retrieve 23 7 9
  [[ $status == 23 ]]
  diff <(printf '%s\n' journal archive cleanup) "$EVENTS"
  grep -F journal=7 "$fixture/qualification-status.txt"
  grep -F archive=9 "$fixture/qualification-status.txt"
}
missing_archive() { retrieve 0 0 9; [[ $status == 9 ]]; }
partial_gui() {
  archive 134 7
  [[ $status == 134 ]]
  tar -tzf "$fixture/evidence.tar.gz" >"$fixture/members"
  grep -Fx appimage-gui-fuse.log "$fixture/members"
  grep -Fx appimage-runtime-fuse.txt "$fixture/members"
  grep -Fx appimage-native-qualification.tar.gz "$fixture/members"
  reject grep -Fx appimage-gui-extracted.log "$fixture/members"
  tar -xOzf "$fixture/evidence.tar.gz" appimage-cpu.txt | grep -F 'fixture CPU'
  tar -xOzf "$fixture/evidence.tar.gz" appimage-evidence-status.txt | grep -F versions=7
}
collection_failure_after_success() { archive 0 7; [[ $status != 0 ]]; test -f "$fixture/evidence.tar.gz"; }
archive_failure_preserves_failure() { fake tar 'exit 33'; archive 134; [[ $status == 134 ]]; test -f "$fixture/appimage-cpu.txt"; }
archive_failure_after_success() { fake tar 'exit 33'; archive 0; [[ $status == 33 ]]; }
for case in failed_qualification collection_errors missing_archive partial_gui \
  collection_failure_after_success archive_failure_preserves_failure archive_failure_after_success; do
  (
    fixture=$(mktemp -d "${TMPDIR:-/tmp}/desktop evidence.XXXXXXXX")
    trap 'rm -rf -- "$fixture"' EXIT
    mkdir "$fixture/bin"
    export PATH="$fixture/bin:$PATH" EVENTS="$fixture/events"
    "$case"
    echo "PASS: $case"
  )
done
