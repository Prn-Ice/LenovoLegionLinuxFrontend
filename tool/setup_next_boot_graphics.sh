#!/usr/bin/env bash
# Initial setup only: install a reviewed boot generation, never switch/reboot.
set -euo pipefail

if [[ $EUID -eq 0 ]]; then
  printf 'Run as your normal user. The installer asks for sudo when needed.\n' >&2
  exit 1
fi
[[ $# -eq 0 || ( $# -eq 1 && $1 == --inhibited ) ]] || exit 64
console=$(tty 2>/dev/null || true)
if [[ ! $console =~ ^/dev/(pts/[0-9]+|tty[0-9]+)$ ]]; then
  printf 'Run this from a desktop terminal so you can confirm the installation.\n' >&2
  exit 1
fi

if [[ $# -eq 0 ]]; then
  # Release the inhibitor automatically when the installer exits. No sleep or
  # shutdown command is requested; this only prevents interruption of setup.
  exec systemd-inhibit --what=sleep:shutdown --mode=block --who='Legion setup' \
    --why='Building and installing a reviewed boot configuration' \
    bash "${BASH_SOURCE[0]}" --inhibited
fi

# A committed snapshot excludes unrelated uncommitted host configuration edits.
SOURCE='git+file:/home/prnice/Dotfiles/nixos-flaky-tests?rev=384070f2ec75d95bee958f0f33545b5ecd73a23b'
CONFIG="$SOURCE#nixosConfigurations.nixos.config"
umask 077
LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/legion-graphics-setup"
mkdir -p "$LOG_DIR"
LOG=$(mktemp "$LOG_DIR/setup-$(date +%Y%m%d-%H%M%S)-XXXXXX.log")
exec > >(tee -a "$LOG") 2>&1

# shellcheck disable=SC2329 # Invoked by the EXIT trap.
finish() {
  local result=$?
  trap - EXIT
  printf '\nSetup exit: %s\nLog saved: %s\n' "$result" "$LOG"
  exit "$result"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

fail() { printf 'ERROR: %s\n' "$1" >&2; exit 1; }

printf 'Legion next-boot setup: %s\nReviewed source: %s\n' "$(date --iso-8601=seconds)" "$SOURCE"
printf 'This builds and installs setup for a later boot only.\n'
printf 'It does NOT change running graphics, log out, queue a mode, or reboot.\n'
printf 'Uncommitted host edits are excluded. Continue? [y/N] '
read -r answer
[[ $answer == y || $answer == Y ]] || exit 0

boot_before=$(cat /proc/sys/kernel/random/boot_id)
current_before=$(readlink -f /run/current-system)
previous_boot=$(readlink -f /nix/var/nix/profiles/system)
printf '\nCurrent boot: %s\nRunning generation: %s\nPrevious boot profile: %s\n' \
  "$boot_before" "$current_before" "$previous_boot"
enabled=$(nix eval --json --no-write-lock-file "$CONFIG.services.legionControl.nextBootGraphics")
[[ $enabled == true ]] || fail 'The reviewed configuration does not enable next-boot graphics.'
tags=$(nix eval --json --no-write-lock-file "$CONFIG.system.nixos.tags")
[[ $tags == '[]' ]] || fail 'Setup requires the ordinary host configuration, not a specialisation.'

printf '\nBuilding the reviewed generation (this can take several minutes).\n'
built=$(nix build --no-write-lock-file --no-link --print-out-paths "$CONFIG.system.build.toplevel")
[[ $built == /nix/store/*-nixos-system-* && $built != *$'\n'* ]] || fail 'Build did not return exactly one NixOS generation.'
printf 'Reviewed generation: %s\n' "$built"
sudo -v
if ! sudo test ! -e /var/lib/legion-graphics-boot/request.json; then
  fail 'Existing graphics request state needs review before initial setup. Nothing installed.'
fi

printf '\nInstalling the boot entry only; your current desktop stays running.\n'
if ! sudo nixos-rebuild boot --flake "$SOURCE#nixos" --no-write-lock-file; then
  fail 'Boot installation failed. Do not reboot yet; share this log for review.'
fi
installed=$(readlink -f /nix/var/nix/profiles/system)
printf '\nInstalled boot generation: %s\n' "$installed"
[[ $installed == "$built" ]] || fail 'Installed generation differs from the reviewed build. Do not reboot; review the log.'
[[ $(readlink -f /run/current-system) == "$current_before" &&
   $(cat /proc/sys/kernel/random/boot_id) == "$boot_before" ]] ||
  fail 'The running system changed during setup; review the log before proceeding.'
printf '\nSetup installed for your next boot. Running graphics and session are unchanged.\n'
printf 'Save your work, then reboot normally when ready. This first boot should remain Hybrid.\n'
printf 'Choose Restart from the desktop menu; waking from sleep/hibernate does not load the new setup.\n'
printf 'After the desktop returns, tell the agent: setup boot finished.\n'
