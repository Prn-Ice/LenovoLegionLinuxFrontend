# Request a graphics change for the next boot

Tracked in `lllf-j9t.7`. This replaces repeated logout/TTY checks for the
controlled Hybrid-to-iGPU-only workflow. It is opt-in and is not yet
hardware-validated.

## What changes

Enable both options in the host's NixOS configuration:

```nix
services.legionControl = {
  reconcileGraphicsAtBoot = true;
  nextBootGraphics = true;
};
```

Build and review the resulting generation before deployment. The boot reconciler
is marked not to restart on live configuration changes, avoiding a restart of
this display-manager dependency. Other host configuration changes can still
restart services: do not treat a general NixOS switch as risk-free. For initial
setup, installing the generation for a later boot is the conservative choice;
the desktop request command becomes available once the new control service is
running. No deployment is performed by the request command itself.

Do not use the host's legacy `no-nvidia` specialisation for this workflow. It
removes PCI devices and uses activation-time firmware commands rather than
this guarded contract. Use the ordinary Hybrid configuration and the internal
panel, with external displays disconnected.

From a desktop terminal, as your normal user:

```bash
legion-graphics-next-boot hybrid-igpu-only
```

Approve the normal Polkit prompt. The command saves a private, root-owned request
and prints confirmation. It does **not** change graphics mode, log you out, or
reboot. Save work and reboot yourself when ready. No new graphical page was added.
Requests expire after 24 hours; an expired request or a backwards clock change
blocks the attempt before any hardware command and requires a fresh request.

Other fixed operations:

```bash
legion-graphics-next-boot status
legion-graphics-next-boot cancel
legion-graphics-next-boot hybrid
```

Only Hybrid and Hybrid iGPU-only are accepted; Auto and Discrete are excluded.
Cancellation removes a pending request, not an already-applied firmware policy.
Requesting Hybrid queues a later-boot return to Hybrid.

## At boot

1. The reconciler runs before the display manager, normal user logins, user
   managers (including lingering users), and the privileged control service.
   Containerd, Docker, and NVIDIA persistence/power daemons are also ordered
   after the check if enabled. These ordering edges do not enable absent services.
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
   backend performs its own last-moment client inspection; the earlier snapshot
   is not treated as permission to detach later.
5. Reconciliation and existing module/device-node cleanup must succeed. Fresh
   root status must show the requested policy, matching settled topology,
   complete inspection, and zero clients before recording `completed`.
6. The display manager can then start. A failure blocks graphical login rather
   than forcing device removal. Individual commands have 40-second limits and
   the overall unit has a 210-second limit.

These gates control known startup sources. They are **not** a kernel-enforced
device-open lock against arbitrary system services or privileged programs.
The guarded backend still has a small inspection-to-firmware-write race. Do not
claim universal race freedom or add force-detach behavior to work around it.

## Evidence and recovery

State is stored in `/var/lib/legion-graphics-boot/request.json`, in a private
root-owned directory. Updates use atomic replacement and file/directory fsync.
The boot ID distinguishes a later boot from a live service restart. Startup
output is in the journal:

```bash
journalctl -b -u legion-graphics-reconcile.service --no-pager
```

`failed` or an interrupted `applying` request blocks later automatic attempts,
including on another boot. It must not be cleared by cancelling, deleting the
file, resetting the failed unit, or restarting the desktop. An explicit new
request is required. Do not restart reconciliation from a running desktop.

If graphical startup is blocked, log into a text console using Ctrl+Alt+F3.
Queue Hybrid through the same typed control API, then reboot. A desktop Polkit
agent may be unavailable on the console; from an authenticated administrative
recovery shell, the same `legion-graphics-next-boot hybrid` client can be used.
There is no automatic sudo fallback or generic root-command API.

If Linux recovery is unavailable, restore Hybrid/Switchable graphics in BIOS
and boot a known-good NixOS generation with this option disabled. A failed
attempt may already have changed firmware policy: do not assume that clearing
an error would restore the old topology.

## Verification boundaries

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
  real boot tests are separate gates. Deployment and successful hardware boot
  must not be inferred from unit tests or a build. Record their actual results
  in the linked issue and the handoff.

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

Deployment, real Polkit authentication, and real next-boot graphics/recovery
tests remain unperformed. Follow-up is `lllf-j9t.7.1`; later sleep validation
remains `lllf-j9t.6.7`. No generation was activated, no firmware was changed, and
no reboot was requested while implementing and testing this flow.
