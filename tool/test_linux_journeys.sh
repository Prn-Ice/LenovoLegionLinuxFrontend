#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
fixture_root=$(mktemp -d "${TMPDIR:-/tmp}/lllf-gcc-restart.XXXXXX")
cleanup() {
  rm -rf -- "$fixture_root"
}
trap cleanup EXIT

cd "$repo_root"
flutter_bin=${FLUTTER:-flutter}
restart_define="--dart-define=LLLF_GCC_RESTART_FIXTURE=$fixture_root"

# Keep these commands sequential: both restart phases share this isolated root,
# and another Flutter command in this checkout can contend for the Linux runner.
timeout --signal=TERM --kill-after=10s 180s \
  "$flutter_bin" test integration_test/app_test.dart -d linux --no-pub
timeout --signal=TERM --kill-after=10s 180s \
  "$flutter_bin" test integration_test/restart_setup.dart -d linux --no-pub "$restart_define"
timeout --signal=TERM --kill-after=10s 180s \
  "$flutter_bin" test integration_test/restart_verify.dart -d linux --no-pub "$restart_define"
