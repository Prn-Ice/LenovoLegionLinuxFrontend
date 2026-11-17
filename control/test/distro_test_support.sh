#!/usr/bin/env bash
# Persistent-file snapshots and VM guards for distro qualification.

assert_vm_marker() {
  local marker=/etc/legion-control-lifecycle-test-vm
  [[ $(stat -c %u "$marker") == 0 ]] || fail 'The VM marker must be owned by root.'
  printf 'legion-control-disposable-lifecycle-vm\n' | cmp - "$marker"
  [[ $(systemd-detect-virt --vm) =~ ^(qemu|kvm)$ ]] || fail 'This test requires a QEMU VM.'
}

assert_disposable_vm() {
  [[ $(id -u) == 0 ]] || fail 'This test requires root inside the disposable VM.'
  assert_vm_marker
}

persistent_files() {
  local root path value
  for root in /etc/systemd/system /usr/lib/systemd/system /etc/polkit-1 \
    /usr/share/polkit-1/actions /etc/dbus-1/system.d /usr/share/dbus-1/system.d /etc/udev/rules.d; do
    [[ -d $root ]] || continue
    while IFS= read -r -d '' path; do
      if [[ -L $path ]]; then value=$(readlink -- "$path"); else value=$(sha256sum -- "$path"); value=${value%% *}; fi
      printf '%q\t%s\t%q\n' "$path" "$(stat -c '%f:%u' -- "$path")" "$value"
    done < <(find "$root" \( -type f -o -type l \) -print0 | sort -z)
  done
}
