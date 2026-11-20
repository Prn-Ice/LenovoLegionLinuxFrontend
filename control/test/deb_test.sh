#!/usr/bin/env bash
# Install, upgrade, exercise, and purge the package inside a disposable VM.
set -euo pipefail
support=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=control/test/helper_session_test.sh
source "$support/helper_session_test.sh"
# shellcheck source=control/test/distro_test_support.sh
source "$support/distro_test_support.sh"
# Session helpers access these maps by name.
# shellcheck disable=SC2034
declare -A app=() active=()
assert_disposable_vm
release=$1
(cd "$release" && sha256sum --check SHA256SUMS)
manifests=("$release"/legion-frontend-*.json)
packages=("$release"/*.deb)
manifest=${manifests[0]} package=${packages[0]}
[[ $(sha256sum "$package" | cut -d' ' -f1) == "$(jq -r --arg name "$(basename "$package")" '.files[$name]' "$manifest")" ]]
jq -e '.control == true and .default_control_mode == "privilegedControlHelper"' "$manifest"
test ! -e /usr/lib/jvm
before=$(mktemp)
persistent_files >"$before"
reject systemctl cat legion-control.service
timeout 180 apt-get install -y --no-install-recommends "$package"
version=$(jq -r .package_version "$manifest")
[[ $(dpkg-query -W -f='${Version}' legion-linux-frontend) == "$version" ]]
diff "$before" <(persistent_files)

verify_bundle() {
  local entry name path type mode entries
  entries=$(mktemp)
  jq -c '.payload | to_entries[]' "$manifest" >"$entries"
  while IFS= read -r entry; do
    name=$(jq -r .key <<<"$entry")
    path=/usr/${name#./}
    [[ $(stat -c %u "$path") == 0 ]]
    type=$(jq -r .value.type <<<"$entry")
    if [[ $type == link ]]; then
      [[ $(readlink "$path") == "$(jq -r .value.target <<<"$entry")" ]]
    else
      mode=$(jq -r .value.mode <<<"$entry")
      ((8#$(stat -Lc %a "$path") == 8#$mode))
    fi
    if [[ $type == file ]]; then
      [[ $(sha256sum "$path" | cut -d' ' -f1) == "$(jq -r .value.sha256 <<<"$entry")" ]]
    fi
  done <"$entries"
  rm "$entries"
  desktop-file-validate /usr/share/applications/io.github.prnice.legion_linux_frontend.desktop
  appstreamcli validate --no-net /usr/share/metainfo/io.github.prnice.legion_linux_frontend.metainfo.xml
}
verify_bundle
timeout 420 bash "$support/desktop_test_support.sh" \
  /usr/bin/legion_frontend deb-gui.log 'Debian package' /usr/lib/legion_frontend/legion_frontend
helper=/usr/lib/legion_frontend/libexec/legion-control-helper
session_new app approved "$helper" false
[[ ${app[cli]} == /usr/local/bin/legion_cli ]]
session_prepare app success
session_send app connect
session_send app authorize
session_send app resume-after-idle
session_send app enable
printf 'enabled\n' | diff - <(session_value app battery-conservation)
session_send app disable
printf 'disabled\n' | diff - <(session_value app battery-conservation)
session_close app
for user in denied challenge; do
  reject as_user "$user" "$helper" --control >/tmp/deb-denied.out 2>&1
  reject grep -F 'CONTROL_READY ' /tmp/deb-denied.out
done
wait_collected
# Preserve the administrator's service bytes and permissions through upgrade and purge.
printf '# Existing administrator-managed Legion service fixture\n' >/etc/systemd/system/legion-control.service
coexistence=$(mktemp)
persistent_files >"$coexistence"
session_new active approved "$helper" false
session_prepare active success
session_send active connect
session_send active authorize
session_send active enable
dpkg-deb -R "$package" /tmp/upgrade
upgraded=$version+qualification
sed -i "s/^Version: .*/Version: $upgraded/" /tmp/upgrade/DEBIAN/control
# Installation covers compression; this fixture checks upgrade behavior.
dpkg-deb --root-owner-group -Znone --build /tmp/upgrade /tmp/upgrade.deb
timeout 180 apt-get install -y --no-install-recommends /tmp/upgrade.deb
[[ $(dpkg-query -W -f='${Version}' legion-linux-frontend) == "$upgraded" ]]
verify_bundle
printf 'enabled\n' | diff - <(session_value active battery-conservation)
session_send active disable
printf 'disabled\n' | diff - <(session_value active battery-conservation)
session_close active
diff "$coexistence" <(persistent_files)
timeout 180 apt-get purge -y legion-linux-frontend
test ! -e /usr/lib/legion_frontend
test ! -e /usr/bin/legion_frontend
diff "$coexistence" <(persistent_files)
rm "$before" "$coexistence"
assert_cleanup_succeeded
jq -n '{installation:true, desktop:true, helper:true, denied:true, missing_agent:true, upgrade:true, purge:true, existing_integration_preserved:true}' >/home/approved/deb-checks.json
echo 'PASS: Debian package install, desktop, helper, upgrade, and purge'
