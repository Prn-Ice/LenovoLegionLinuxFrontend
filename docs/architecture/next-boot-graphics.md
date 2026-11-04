# Request a graphics change for the next boot

## Current status

This optional feature changes between Hybrid and Hybrid iGPU-only at the next
boot. Both directions have passed hardware tests on the recorded setup. Recovery
after a failed transition, pending-request cancellation, and current sleep tests
remain unverified. Tracked in `lllf-j9t.7`.

## Enable next-boot graphics changes

Enable both options in the host's NixOS configuration:

```nix
services.legionControl = {
  reconcileGraphicsAtBoot = true;
  nextBootGraphics = true;
};
```

Build and review the configuration before installing it. For initial setup,
install it for the next boot rather than activating it in a running desktop.
The reconciler does not restart during live configuration changes, but other
changed services may restart. The desktop request command becomes available once
the new control service is running.

Do not use the legacy `no-nvidia` specialisation. It changes firmware and removes
PCI devices during activation. Use the ordinary Hybrid configuration and the
internal panel, with external displays disconnected.

## Request a mode

From a desktop terminal, as your normal user:

```bash
legion-graphics-next-boot hybrid-igpu-only
```

Approve the Polkit prompt to save the request. Graphics mode stays unchanged
until you reboot. Save your work and reboot when ready.
Requests expire after 24 hours. If the request expires or the clock moves
backwards, submit a new request. Both cases block the attempt before any hardware
command.

Other commands:

```bash
legion-graphics-next-boot status
legion-graphics-next-boot cancel
legion-graphics-next-boot hybrid
```

Supported modes: Hybrid and Hybrid iGPU-only.
Cancel removes a pending request. To return to Hybrid after a change, request
Hybrid and reboot.

## What happens at boot

1. The reconciler runs before the display manager, normal user logins, user
   managers (including lingering users), and the privileged control service.
   Containerd, Docker, and NVIDIA persistence/power daemons are also ordered
   after the check if enabled.
   NVIDIA CDI generation requires successful reconciliation; Docker already
   depends on CDI in the toolkit-enabled host configuration. Text login and the
   recovery control service remain available after a failure; ordering alone
   does not prevent every other system service from starting after an abort.
2. The helper refuses selection outside system startup and refuses a request
   created in the current boot. A live rebuild cannot apply the queued mode.
3. Before any attempt, it durably marks the request as `applying`. It refuses
   running user managers, incomplete root inspection, existing NVIDIA clients,
   unsupported modes, and a non-Hybrid starting policy. Ejection additionally
   requires the connected internal eDP panel and no connected external displays.
4. It calls the existing guarded backend to select the requested mode. The
   backend checks again for NVIDIA clients immediately before changing the mode.
5. Reconciliation and existing module/device-node cleanup must succeed. Fresh
   root status must show the requested policy, matching settled topology,
   complete inspection, and zero clients before recording `completed`.
6. The display manager can then start. A failure blocks graphical login rather
   than forcing device removal. Individual commands have 40-second limits and
   the overall unit has a 210-second limit.

Another privileged process could open the GPU between the final check and the
firmware write. These checks reduce that risk but do not eliminate it. Do not
force device removal.

## Status and recovery

State is stored in `/var/lib/legion-graphics-boot/request.json`, in a private
root-owned directory. Updates use atomic replacement and file/directory fsync.
The saved boot ID prevents a service restart from applying a request in the same
boot. Startup output is in the journal:

```bash
journalctl -b -u legion-graphics-reconcile.service --no-pager
```

After a failure or interrupted attempt, submit a new request. A `failed` or
interrupted `applying` request blocks later automatic attempts, including on
another boot. Do not delete the state file or reset the service to bypass the
block. Cancelling or restarting the desktop must not clear it either. Do not
restart reconciliation from a running desktop.

If graphical startup is blocked, log into a text console using Ctrl+Alt+F3.
Queue Hybrid through the same typed control API, then reboot. A desktop Polkit
agent may be unavailable on the console; from an authenticated administrative
recovery shell, the same `legion-graphics-next-boot hybrid` client can be used.

If Linux recovery is unavailable, restore Hybrid/Switchable graphics in BIOS
and boot a known-good NixOS generation with this option disabled. A failed
attempt may still have changed the firmware setting. Clearing the error does not
restore it.

## Test coverage

- Python tests exercise real request-file persistence with fake hardware and
  systemd calls: queue/cancel, same-boot/live deferral, one-shot consumption,
  clients and inspection failures, unexpected user managers, displays,
  unsupported policy, late backend refusal, cleanup/readback failures, and
  explicit recovery after an interrupted attempt.
- Native tests exercise the real service dispatcher, subprocess handling, and
  desktop client against a fake executable on a private D-Bus, including use of
  the same authorized connection for the request. Authorization is simulated;
  these are not real Polkit or hardware tests.
- Native service/package builds, rendered NixOS ordering, full host builds, and
  real boot tests are separate checks. Record deployment and hardware results
  separately in the linked issue, including the model, firmware, and installed
  revision.

## Historical results

### Results on 2026-11-03

- `python3 tool/test_graphics_boot.py`: all 17 tests passed.
- The native package built with warnings treated as errors; all three CTest
  suites passed, including real dispatcher/client calls on the private bus.
  The installed terminal client's `--help` smoke check passed.
- Existing detached-lifecycle, CDI-condition, hibernate-reconciliation-loop, and
  the 13 logged-TTY-capture cases passed. No hardware was used by those tests.
- Nix evaluation confirms the default remains disabled and preserves the
  original boot reconcile/cleanup commands. Enabling next-boot requests without
  boot reconciliation triggers the intended assertion.
- A full normal host generation built with the local module and opt-in enabled:
  `/nix/store/0ii71i7dhckpd9d4aranrhf3h377mdq0-nixos-system-nixos-26.11.20261101.0bb2eed`.
  This used a temporary evaluation overlay; the host configuration and its
  pre-existing dirty `flake.lock` were not edited.
- `systemd-analyze verify --man=no` passed for the rendered graphical,
  multi-user, user-manager, and reconciliation startup graph after materializing
  Nix store unit links into a temporary unit search directory. It reported only
  the existing CUPS `/var/run` socket-path warning; no ordering cycles.
- The generated reconciliation unit includes `X-RestartIfChanged=false` and
  the expected startup ordering. Source review of systemd 262's `manager_state`
  confirms that starting an ordinary job after boot does not change the manager
  back to the `starting` state used by the helper's live-activation guard.

At this stage, deployment, real Polkit authentication, and real next-boot
graphics/recovery tests were unperformed. Follow-up was `lllf-j9t.7.1`; later
sleep validation remains `lllf-j9t.6.7`. The following sections record the later
deployment, authentication, and successful transitions.

### Initial setup launcher

The host configuration enabled the option and pinned the implementation in
host commit `384070f2ec75d95bee958f0f33545b5ecd73a23b` (frontend input
`9b8724919942ddac8018afb1c71e2fdecacda1d7`). The pre-existing unrelated
`view-beads` lock edit was not included in that commit and remains untouched in
the working tree.

`tool/setup_next_boot_graphics.sh` uses that immutable committed Git flake,
rather than deploying unrelated working-tree changes. Run it as your normal
user from a desktop terminal. It blocks automatic sleep/shutdown for its
lifetime, asks for confirmation, validates the ordinary enabled configuration,
builds the reviewed generation, and asks for sudo to install it using
`nixos-rebuild boot`. It refuses pre-existing request state and checks that the
installed profile matches the build and the running generation/boot are
unchanged. It does not activate, select a graphics mode, log out, or reboot.
Errors stop the launcher and retain the log; there is no automatic rollback of
an ambiguous failed boot-loader installation.

Logs are private files in
`${XDG_STATE_HOME:-$HOME/.local/state}/legion-graphics-setup/`. Ten mocked setup
cases, Bash syntax, ShellCheck, and diff checks pass. No real installation was
performed by those tests. The local convenience link `~/legion-setup` points to
the launcher; use `bash ~/legion-setup`.

After a successful installation, save work and choose **Restart** from the
desktop menu when ready. Waking a saved hibernation session is not a setup boot.
The first boot should remain Hybrid: no iGPU-only request is queued by setup.
Verify its boot ID, running generation and reconciliation log before testing
the new authorization or requesting an actual mode change.

The exact committed host configuration for this launcher built successfully as
`/nix/store/4wbf4plndc06pzbyg63iifqqclvigzzg-nixos-system-nixos-26.11.20261101.0bb2eed`.
Its rendered startup graph passed the same materialized-unit verification, with
only the existing CUPS path warning. This build excludes the unrelated working
lock edit. At that point it was only a setup candidate, not an installed or
running generation.

### First setup boot validated

The user ran the installer and restarted normally. The log
`~/.local/state/legion-graphics-setup/setup-20261103-230526-mySEqj.log`
records exit 0, successful boot-only installation of the reviewed `4wbf4...`
generation, and unchanged running generation/boot before the user's restart.
Boot-loader probing emitted warnings, but the installer completed and its
profile checks passed.

On 2026-11-03 at 23:07, boot ID changed from `3a1b0a31...` to
`4c417bfb-648d-4eb8-9cab-775b81cc77f9`. Both `/run/current-system` and the
installed system profile resolve to the exact reviewed `4wbf4...` generation.
This was a new setup boot, not return to the prior hibernated session.

The boot helper logged `starting`, complete zero-client
Hybrid/attached/settled status, successful cleanup, and `phase: none` (no queued
mode request). It finished at monotonic 9.102467 seconds. The control service
started at 9.104487, user-session admission at 9.106614, display manager at
9.121842, and user manager at 22.390164 seconds, confirming the observed startup
ordering. The installed client is available and the control service is active
with the fixed next-boot helper argument.

At this check, system and user failed-unit lists were both empty. The user journal
also contains historical crash-report replay and a transient KSplash timeout; these
are not evidence that a new graphics transition occurred or new crashes matching
the replayed records. The prior wake incident remains unresolved separately.

The next check was the real desktop Polkit/status round trip without queuing a
mode, before an explicit iGPU-only request and its separate user-triggered reboot.
This successful Hybrid setup boot did not validate an iGPU-only transition or
sleep.

### First requested iGPU-only boot validated

The real desktop status/authentication check returned `phase: none`. The user
then queued Hybrid iGPU-only using the typed client. The saved request in
`~/.local/state/legion-graphics-setup/request.log` records `phase: pending`,
originating boot `4c417bfb-648d-4eb8-9cab-775b81cc77f9`, and timestamp
`1793744498.93623`. No immediate mode change occurred.

After the user's next restart, boot ID is
`cfd9d39f-da60-46f3-9bfe-83db970b007d`, still on reviewed generation `4wbf4...`.
The 2026-11-03 23:24 journal records initial Hybrid/attached/settled status with
complete zero-client root inspection, followed by the guarded selection of
Hybrid iGPU-only. The backend settled detached after six recorded reconciliation
attempts (about 25 seconds), then reconciliation, cleanup, and fresh root
verification passed. The persisted result printed in the journal is
`phase: completed`, with the correct originating/attempted boot IDs and final
detached/settled/complete/zero-client status.

The boot helper finished at monotonic 34.966591 seconds; the control service,
user-session admission, and display manager began afterward at 34.968626,
34.971531, and 34.982289 seconds. The user manager began at 47.432017 seconds.
CDI generation was skipped by its condition, as intended for detached policy.
Both current system and user failed-unit lists are empty.

Read-only checks after desktop startup find no NVIDIA PCI functions, no
`/dev/nvidia*` nodes, and none of the NVIDIA GPU-driver modules
(`nvidia`, `nvidia_drm`, `nvidia_modeset`, `nvidia_uvm`). The distinct
`nvidia_wmi_ec_backlight` platform/backlight module remains loaded; it is not the
GPU driver stack and is not part of cleanup. The internal eDP-2 panel is
connected. Root port `0000:00:01.1` reports runtime `suspended` and `D3cold`.
Unprivileged CLI status agrees on detached/settled iGPU-only but reports
incomplete process inspection; do not mislabel that as a fresh root scan.

Two known NVIDIA SBIOS query assertions appear at 23:24:04, before the boot
helper started and before the mode transition. They remain under
`lllf-j9t.6.6`; do not claim a warning-free kernel or attribute them to the new
selection without evidence. The user confirms desktop, sound, and Wi-Fi all
work normally on this boot. At this stage, real Hybrid return/recovery, live
cancellation, and subsequent sleep coverage were pending.

### Requested return to Hybrid validated

The user queued Hybrid in
`~/.local/state/legion-graphics-setup/hybrid-request.log`: `phase: pending`,
timestamp `1793745347.3212276`, and originating boot `cfd9d39f...`. After the
user's restart, boot ID is `b4c098f2-8822-4116-8114-5b3edec9e3b4`, still on
reviewed generation `4wbf4...`.

The 23:37:51 root boot log initially shows the persisted iGPU-only policy with
NVIDIA re-enumerated and attached, complete zero-client inspection, and
reconciliation needed. The queued Hybrid selection succeeds, followed by
settled attached topology, cleanup's attached-policy path, and final complete
zero-client root verification. The request is recorded as `completed` with the
correct originating and attempted boot IDs.

Reconciliation finishes at monotonic 9.583447 seconds, before control startup
(9.585930), session admission (9.588526), display-manager startup (9.606987), and
the user manager (26.398326). CDI generation now runs successfully, as expected
for Hybrid. NVIDIA VGA `0000:01:00.0` binds `nvidia`, audio `0000:01:00.1` binds
`snd_hda_intel`, and the NVIDIA GPU module stack is loaded again. After desktop
startup, Code opening NVIDIA handles is expected and is not a failed guard.

Both current system/user failed-unit lists are empty. The user confirms the
desktop, sound, and Wi-Fi all work normally after this return boot.
This validates a requested boot-time return to Hybrid, not live hot-attach or
recovery after an actually failed/interrupted hardware transition. Live pending
request cancellation and subsequent sleep coverage remain separate unperformed
checks.

### Sleep incidents

#### Runtime incident before deployment

Before deployment, the user reported a perceived hang, a power-button shutdown
attempt, and return to the previous session. Deployment was paused while clarifying that
event (`lllf-p4q`). The running system was still generation `lkvqlww...`, not the
built opt-in generation in the [initial build results](#results-on-2026-11-03).
The user confirms a dark screen with keyboard and power-button lights still on.
That is consistent with sleep/image preparation, but does not rule out a wake
problem. Whether a held power press actually extinguished the LEDs remains
unknown. With user approval, preparation resumed for boot-only setup, not a live
graphics change, and without treating the reported hang as resolved.

Read-only logs for boot `3a1b0a31-b6fc-4954-9318-b5a38ddb8ae3` show PowerDevil
requesting suspend-then-hibernate at 22:12 on 2026-11-03, a timer wake after the
configured 30 minutes, hibernate entry at 22:42:11, and return at 22:45:56.
Hibernation entry-to-return advances realtime about 225.166 seconds but monotonic
time only 23.947 seconds. The approximately 201-second difference, unchanged boot
ID, snapshot-save messages, and restore callbacks strongly support same-image
hibernation recovery. No explicit restored-image message was captured; this is
not proof that no hang occurred or that the power button forced a cold shutdown.

The root status logged around that cycle is Hybrid/attached/settled/complete with
normal desktop clients. It is not an iGPU-only validation. The Wi-Fi restore
timeout recurs under `lllf-j9t.6.5`. The post-resume loop also incorrectly rejects
normal Hybrid clients (`lllf-esn`); the sleep service can report success despite
that hook failure. Only the pre-existing DrKonqi failed unit remains. Neither
warning has been established as the cause of the user's perceived hang.

Preserve the unresolved power-button/wake context for subsequent hardware
validation.

#### Repeat dark-screen incident (2026-11-04)

The user reported the perceived hibernate hang again before the requested next
reboot. Boot ID remains `b4c098f2-8822-4116-8114-5b3edec9e3b4`, and the sleep
logs still show Hybrid/attached/settled status. The newly queued iGPU-only
request has not applied. Planned detached sleep validation is paused under
`lllf-p4q` and `lllf-j9t.6.7`; do not reboot into a different graphics policy as
part of diagnosing this incident without reviewing/cancelling the request.

The log records PowerDevil requesting suspend-then-hibernate at 00:00:09,
hibernate entry after the configured delay at 00:30:13, and return at 01:42:36.
Realtime advances about 4343.139 seconds across hibernation while monotonic time
advances about 17.854 seconds, consistent with image restore. Nevertheless,
KWin logs repeated `drmGetDeviceFromDevId failed! No such file or directory`
errors at 01:42:37-38. At 01:43:07, PowerDevil requests **another ordinary
suspend**, approximately 30 seconds after user sessions thawed. This suspend
returns at 01:48:42; KWin then reports output-configuration `EACCESS` and
`drmModeListLessees` permission errors. The cause of the second suspend is unknown
(button, lid, idle action, or power event). Successful sleep units do not explain
the reported display problem; current failed-unit lists are empty.

The known Wi-Fi restore timeout and Hybrid post-hook client rejection also
recur. Neither is established as the cause of the display problem.

Private evidence is retained at
`~/.local/state/legion-sleep-incidents/20261104-b4c098f2-rn5kuneg/`: sleep-unit,
logind, kernel, PowerDevil and compositor logs, JSON timing records, and a
snapshot of the user power configuration. The available logs and profile
configuration do not establish why PowerDevil issued the second request.
Preserve the incident and clarify the user's wake/button sequence before
changing power policy or running further sleep tests.
