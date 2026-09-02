#!/usr/bin/env bash
set -euo pipefail

CLI="/run/current-system/sw/bin/legion_cli"
HOOK="/etc/systemd/system-sleep/legion-hibernate-diagnostics"
RUNTIME_LATEST="/run/legion-hibernate-diagnostics/latest"
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
STARTED_AT=$(date --iso-8601=seconds)
LOG="/tmp/lllf-igpu-only-hibernate-${STARTED_AT//:/-}.log"
display_manager_stopped=0
audio_services_stopped=0
hibernate_requested=0
diagnostics_enabled=0
evidence_armed=0
pm_debug_original=
pm_print_original=

exec > >(tee -a "$LOG") 2>&1

restart_user_audio() {
	if [[ "$audio_services_stopped" -eq 1 ]]; then
		systemctl --user start \
			pipewire.socket pipewire-pulse.socket \
			pipewire.service wireplumber.service pipewire-pulse.service
		audio_services_stopped=0
	fi
}

restore_pm_diagnostics() {
	if [[ "$diagnostics_enabled" -eq 1 ]]; then
		local restore_failed=0
		printf '%s\n' "$pm_debug_original" | sudo tee /sys/power/pm_debug_messages >/dev/null || restore_failed=1
		printf '%s\n' "$pm_print_original" | sudo tee /sys/power/pm_print_times >/dev/null || restore_failed=1
		[[ "$restore_failed" -eq 0 ]] || return 1
		diagnostics_enabled=0
	fi
}

wait_for_hibernate_cycle() {
	local previous_start=$1
	local active_state current_start service_result
	local observed=0

	for ((attempt = 0; attempt < 600; attempt++)); do
		current_start=$(systemctl show systemd-hibernate.service \
			--property=ExecMainStartTimestampMonotonic --value) || return 1
		if [[ -n "$current_start" && "$current_start" != "0" &&
			"$current_start" != "$previous_start" ]]; then
			observed=1
			break
		fi
		sleep 0.2
	done

	[[ "$observed" -eq 1 ]] || return 1
	for ((attempt = 0; attempt < 1500; attempt++)); do
		active_state=$(systemctl show systemd-hibernate.service \
			--property=ActiveState --value) || return 1
		case "$active_state" in
		inactive) break ;;
		failed) return 1 ;;
		activating | active | deactivating) ;;
		*) return 1 ;;
		esac
		sleep 0.2
	done
	[[ "$active_state" == "inactive" ]] || return 1

	service_result=$(systemctl show systemd-hibernate.service \
		--property=Result --value) || return 1
	[[ "$service_result" == "success" ]]
}

# shellcheck disable=SC2329 # Invoked by the EXIT trap.
cleanup() {
	local status=$?
	trap - EXIT
	if [[ "$evidence_armed" -eq 1 && "$hibernate_requested" -eq 0 ]]; then
		sudo "$HOOK" cancel || true
	fi
	if [[ "$diagnostics_enabled" -eq 1 ]]; then
		restore_pm_diagnostics || true
	fi
	if [[ "$display_manager_stopped" -eq 1 && "$hibernate_requested" -eq 0 ]]; then
		printf '\nRestarting the display manager after an interrupted preflight.\n' >&2
		restart_user_audio || true
		sudo systemctl start display-manager.service || true
	elif [[ "$display_manager_stopped" -eq 1 ]]; then
		printf '\nGraphics state is uncertain; keep the display manager and user audio stopped.\n' >&2
		printf 'Use %s/restore_hybrid_tty.sh if detached topology is not confirmed.\n' "$SCRIPT_DIR" >&2
	fi
	exit "$status"
}
trap cleanup EXIT

fail() {
	printf 'ERROR: %s\n' "$1" >&2
	printf 'Hibernation has not started. Log: %s\n' "$LOG" >&2
	exit 1
}

tty_path=$(tty 2>/dev/null || true)
case "$tty_path" in
/dev/tty[0-9]*) ;;
*) fail "Run this script from a Linux virtual console such as Ctrl+Alt+F3, not $tty_path." ;;
esac

[[ $# -eq 0 ]] || fail "Usage: $0"
[[ -x "$CLI" ]] || fail "Validated CLI is unavailable at $CLI."
[[ -x "$HOOK" ]] || fail "Hibernate-only diagnostics are unavailable at $HOOK."
[[ -r /sys/power/disk ]] || fail "Kernel hibernation modes are unavailable."
[[ $(</sys/power/disk) == *"shutdown"* ]] || fail "The kernel does not advertise shutdown hibernation mode."

sleep_config=$(systemd-analyze cat-config systemd/sleep.conf)
hibernate_mode=
config_section=
# systemd replaces the mode list on each assignment, so the final Sleep value is authoritative.
while IFS= read -r config_line; do
	config_line=${config_line#"${config_line%%[![:space:]]*}"}
	case "$config_line" in
	\[*\]) config_section=$config_line ;;
	HibernateMode=*)
		[[ "$config_section" == "[Sleep]" ]] && hibernate_mode=${config_line#*=}
		;;
	esac
done <<<"$sleep_config"
[[ "$hibernate_mode" == "shutdown" ]] ||
	fail "Effective systemd sleep configuration is not exactly HibernateMode=shutdown."

for status_path in /sys/class/drm/card[0-9]-*/status; do
	[[ -r "$status_path" ]] || continue
	read -r connector_status <"$status_path"
	connector=${status_path%/status}
	connector=${connector##*/}
	if [[ "$connector_status" == "connected" && "$connector" != *-eDP-* ]]; then
		fail "External connector $connector is active. Disconnect every external display first."
	fi
done

printf 'Starting guarded Hybrid iGPU-only shutdown-mode hibernate test at %s\n' "$STARTED_AT"
printf 'Runner log: %s\n' "$LOG"
sudo -v

graphics_state=$(sudo "$CLI" --donotexpecthwmon graphics-mode status --json)
[[ "$graphics_state" == *'"selected_mode": "hybrid-igpu-only"'* ]] ||
	fail "Selected graphics policy must be Hybrid iGPU-only."
[[ "$graphics_state" == *'"effective_dgpu_state": "detached"'* ]] ||
	fail "The dGPU must be fully detached."
[[ "$graphics_state" == *'"reconciliation": "settled"'* ]] ||
	fail "Graphics topology must be settled."

pm_debug_original=$(</sys/power/pm_debug_messages)
pm_print_original=$(</sys/power/pm_print_times)
diagnostics_enabled=1
printf '1\n' | sudo tee /sys/power/pm_debug_messages >/dev/null
printf '1\n' | sudo tee /sys/power/pm_print_times >/dev/null
[[ $(</sys/power/pm_debug_messages) == "1" ]] || fail "Could not enable pm_debug_messages."
[[ $(</sys/power/pm_print_times) == "1" ]] || fail "Could not enable pm_print_times."

sudo "$HOOK" arm "$STARTED_AT"
evidence_armed=1

printf 'Stopping the graphical session and user audio before the final root preflight.\n'
sudo systemctl stop display-manager.service
display_manager_stopped=1
systemctl --user stop graphical-session.target

while read -r session_id _; do
	session_type=$(loginctl show-session "$session_id" --property=Type --value 2>/dev/null || true)
	if [[ "$session_type" == "wayland" || "$session_type" == "x11" ]]; then
		sudo loginctl terminate-session "$session_id"
	fi
done < <(loginctl list-sessions --no-legend)

pkill -TERM -x code 2>/dev/null || true
sleep 5

audio_services_stopped=1
systemctl --user stop \
	pipewire-pulse.socket pipewire.socket \
	wireplumber.service pipewire-pulse.service pipewire.service

graphics_state=$(sudo "$CLI" --donotexpecthwmon graphics-mode status --json)
printf '\nFinal root graphics status:\n%s\n' "$graphics_state"
[[ "$graphics_state" == *'"selected_mode": "hybrid-igpu-only"'* ]] ||
	fail "Graphics policy changed while quiescing the user session."
[[ "$graphics_state" == *'"effective_dgpu_state": "detached"'* ]] ||
	fail "The dGPU is no longer fully detached."
[[ "$graphics_state" == *'"reconciliation": "settled"'* ]] ||
	fail "Graphics topology changed while quiescing the user session."
[[ "$graphics_state" == *'"client_inspection_complete": true'* ]] ||
	fail "Root dGPU client inspection must be complete."
[[ "$graphics_state" == *'"active_clients": []'* ]] ||
	fail "The detached test still has active dGPU clients."

printf 'shutdown\n' | sudo tee /sys/power/disk >/dev/null
[[ $(</sys/power/disk) == *"[shutdown]"* ]] ||
	fail "Could not select shutdown hibernation mode in /sys/power/disk."

printf '\n============================================================\n'
printf 'PREFLIGHT PASSED. HIBERNATION HAS NOT STARTED.\n'
printf '============================================================\n'
printf 'systemd is configured for HibernateMode=shutdown.\n'
printf 'The hibernate-only hook will verify [shutdown] and persist root evidence.\n'
printf 'The graphical session and user audio are stopped.\n'
printf 'If power-off succeeds, press the power button once to resume the image.\n'
printf 'If this operation returns immediately, do not restart the desktop manually.\n'
printf '\nType HIBERNATE-SHUTDOWN to begin: '
read -r confirmation
[[ "$confirmation" == "HIBERNATE-SHUTDOWN" ]] || fail "Confirmation did not match."

journalctl --sync
sync
hibernate_service_state=$(systemctl show systemd-hibernate.service \
	--property=ActiveState --value)
[[ "$hibernate_service_state" == "inactive" ]] ||
	fail "systemd-hibernate.service must be inactive before the request."
previous_hibernate_start=$(systemctl show systemd-hibernate.service \
	--property=ExecMainStartTimestampMonotonic --value)
set +e
sudo systemctl hibernate
result=$?
if [[ "$result" -eq 0 ]]; then
	hibernate_requested=1
	wait_for_hibernate_cycle "$previous_hibernate_start"
	result=$?
fi
set -e

printf '\nHibernate command returned with exit %d at %s.\n' "$result" "$(date --iso-8601=ns)"
if sudo test -r "$RUNTIME_LATEST"; then
	evidence_dir=$(sudo cat "$RUNTIME_LATEST")
	printf 'Persistent diagnostic evidence: %s\n' "$evidence_dir"
	if sudo test -e "$evidence_dir/UNSAFE-HIBERNATION-MODE"; then
		printf 'ERROR: The hibernate hook observed a mode other than shutdown.\n' >&2
		[[ "$result" -ne 0 ]] || result=1
	fi
	if sudo test -e "$evidence_dir/CAPTURE-FAILED"; then
		printf 'ERROR: The hibernate hook recorded a capture failure.\n' >&2
		[[ "$result" -ne 0 ]] || result=1
	fi
	for required_capture in \
		pre-hibernate/summary.txt \
		pre-hibernate/pci-and-graphics.txt \
		pre-hibernate/power-and-firmware.txt \
		pre-hibernate/sys-kernel-debug-wakeup_sources.txt \
		pre-hibernate/sys-power-pm_wakeup_irq.txt \
		pre-hibernate/kernel-journal.txt \
		post-hibernate/summary.txt \
		post-hibernate/pci-and-graphics.txt \
		post-hibernate/power-and-firmware.txt \
		post-hibernate/sys-kernel-debug-wakeup_sources.txt \
		post-hibernate/sys-power-pm_wakeup_irq.txt \
		post-hibernate/kernel-journal.txt; do
		if ! sudo test -e "$evidence_dir/$required_capture"; then
			printf 'ERROR: Missing hibernate evidence: %s\n' "$required_capture" >&2
			[[ "$result" -ne 0 ]] || result=1
		fi
	done
else
	printf 'ERROR: The diagnostic hook did not publish an evidence path.\n' >&2
	[[ "$result" -ne 0 ]] || result=1
fi

if ! restore_pm_diagnostics; then
	printf 'ERROR: Could not restore kernel power-management diagnostics.\n' >&2
	[[ "$result" -ne 0 ]] || result=1
fi

set +e
graphics_state=$(sudo "$CLI" --donotexpecthwmon graphics-mode status --json)
graphics_result=$?
set -e
if [[ "$graphics_result" -ne 0 ]]; then
	printf 'ERROR: Returned root graphics inspection failed.\n' >&2
	[[ "$result" -ne 0 ]] || result=1
fi
printf '\nReturned root graphics status:\n%s\n' "$graphics_state"
if [[ "$result" -eq 0 &&
	"$graphics_state" == *'"selected_mode": "hybrid-igpu-only"'* &&
	"$graphics_state" == *'"effective_dgpu_state": "detached"'* &&
	"$graphics_state" == *'"reconciliation": "settled"'* &&
	"$graphics_state" == *'"client_inspection_complete": true'* &&
	"$graphics_state" == *'"active_clients": []'* ]]; then
	printf '\nDetached topology is settled; restarting user audio and the display manager.\n'
	restart_user_audio
	sudo systemctl start display-manager.service
	display_manager_stopped=0
	hibernate_requested=0
	evidence_armed=0
else
	printf '\nHibernate or detached-topology validation failed.\n' >&2
	printf 'Keep the graphical session stopped and preserve the evidence above.\n' >&2
	printf 'Run %s/restore_hybrid_tty.sh to recover Hybrid safely.\n' "$SCRIPT_DIR" >&2
	[[ "$result" -ne 0 ]] || result=1
fi

printf 'Command exit: %d\nRunner log: %s\n' "$result" "$LOG"
exit "$result"
