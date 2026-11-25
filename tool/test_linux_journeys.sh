#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
fixture_root=$(mktemp -d "${TMPDIR:-/tmp}/lllf-gcc-restart.XXXXXX")
settings_root=''
cleanup() {
  rm -rf -- "$fixture_root"
  if [[ -n "$settings_root" ]]; then
    rm -rf -- "$settings_root"
  fi
}
trap cleanup EXIT
settings_root=$(mktemp -d "${TMPDIR:-/tmp}/lllf-settings-restart.XXXXXX")

cd "$repo_root"
flutter_bin=${FLUTTER:-flutter}
restart_define="--dart-define=LLLF_GCC_RESTART_FIXTURE=$fixture_root"
settings_define="--dart-define=LLLF_SETTINGS_RESTART_FIXTURE=$settings_root"

# Keep commands sequential: each restart pair shares one isolated root,
# and another Flutter command in this checkout can contend for the Linux runner.
# The full suite includes all main sections; each wait remains bounded in Dart.
timeout --signal=TERM --kill-after=10s 600s \
  "$flutter_bin" test integration_test/app_test.dart -d linux --no-pub
timeout --signal=TERM --kill-after=10s 180s \
  "$flutter_bin" test integration_test/restart_setup.dart -d linux --no-pub "$restart_define"
timeout --signal=TERM --kill-after=10s 180s \
  "$flutter_bin" test integration_test/restart_verify.dart -d linux --no-pub "$restart_define"
timeout --signal=TERM --kill-after=10s 180s \
  "$flutter_bin" test integration_test/settings_restart_setup.dart -d linux --no-pub "$settings_define"
timeout --signal=TERM --kill-after=10s 180s \
  "$flutter_bin" test integration_test/settings_restart_verify.dart -d linux --no-pub "$settings_define"
