# Poweroff Stall After Live dGPU Detach

## Scope

This investigation covers the generation-464 poweroff that followed a guarded
Hybrid to Hybrid iGPU-only live transition on 2026-09-01. Normal systemd
userspace teardown completed, but the machine did not visibly power off after
the console showed:

```text
systemd-shutdown[1]: Syncing filesystems and block devices.
systemd-shutdown[1]: Sending SIGTERM to remaining processes...
```

Power was removed after about ten minutes. The next cold boot was healthy.

## What The Journal Proves

The persisted journal does not identify a remaining process. Several known-good
reboots also end at `Sending SIGTERM to remaining processes` because
systemd-shutdown terminates journald during that step. Messages emitted later
in shutdown are console output and are not guaranteed to reach the journal.

The affected boot did establish these boundaries:

- Userspace services stopped normally in about two seconds.
- Swap and non-root filesystems were cleanly deactivated or unmounted.
- The first shutdown sync completed before the SIGTERM broadcast.
- The NVIDIA display and audio functions had disappeared before poweroff.
- The NVIDIA root port previously logged that it refused D0 to D3hot.
- The next boot had no filesystem recovery, I/O errors, failed units, or pstore
  record from this event.

The roughly ten-minute gap matches systemd's default `RebootWatchdogSec`, but
the SP5100 watchdog reported `bootstatus=0`. The next boot's reset reason was an
ACPI power-state transition. This does not prove that the watchdog fired.

## Current Hypotheses

The evidence does not yet distinguish these phases:

1. A userspace process remained after systemd's SIGTERM broadcast.
2. Exitrd, unmount, loop, device-mapper, or final sync cleanup stalled.
3. A kernel device shutdown callback stalled after PID 1 requested poweroff.
4. The final ACPI S5 transition stalled after all kernel callbacks completed.

The root-port power-state refusal makes the PCI or firmware phases plausible,
but it is not proof. Backend revision `dec5983` requires every NVIDIA PCI
function to disappear, checks NVIDIA HDMI-audio clients, reports final observed
availability to firmware, and revalidates delayed WMI callbacks against driver
removal.

## Hardened Retest Result

Generation 465 validated backend revision `dec5983` on hardware on 2026-09-02.
The guarded transition reached settled Hybrid iGPU-only state with complete root
client inspection, no active clients, and no NVIDIA PCI functions. Both the
pre-poweroff and final-target snapshots showed the NVIDIA root port suspended in
`D3cold` rather than refusing `D0` to `D3hot`.

The instrumented detached poweroff then completed normally. The final-target
snapshot contained no failed units, active swaps, process locks, or persistent
uninterruptible tasks. Its process listing briefly sampled one kworker in
`synchronize_rcu_normal`, but the subsequent per-task scan found no task still
in disk sleep and shutdown completed immediately afterward. NVIDIA modules and
their sleeping kernel threads remained loaded, while the NVIDIA devices were
absent.

The next boot had no filesystem recovery, I/O errors, failed units, or pstore
record. Early reconciliation restored the selected Hybrid iGPU-only policy and
settled detached after six attempts. The original stall therefore did not
reproduce after backend hardening and complete graphical/audio client
quiescing. Its precise root cause remains unknown, so a future recurrence needs
fresh console or pstore evidence rather than attribution to the transient
kworker.

## Safe Evidence Capture

Do not repeat a live detach only to reproduce this issue. Establish an ordinary
Hybrid poweroff baseline first. From a Linux virtual console:

```bash
./tool/arm_shutdown_diagnostics_tty.sh baseline
```

The tool:

- Requires settled Hybrid with the dGPU attached for the baseline case.
- Captures root process, task, PCI, graphics, mount, lock, and systemd state.
- Arms a runtime-only `final.target` service that captures the same evidence
  after normal services and mounts have stopped.
- Writes evidence under `/var/log/legion-shutdown-diagnostics/`.
- Does not change graphics policy or initiate poweroff.

Film the TTY continuously, review the pre-poweroff evidence, and only then run:

```bash
sudo systemctl poweroff
```

The generation-464 plain-Hybrid baseline completed normally on 2026-09-01. It
reached systemd-shutdown and powered off with the NVIDIA VGA and audio functions
attached. The next boot was healthy. The original stall therefore did not
reproduce without a live detach.

The baseline also exposed and fixed an instrumentation error: a script using
`#!/usr/bin/env bash` could not find Bash after `/run/wrappers` was unmounted.
The runtime unit now invokes the immutable Nix store Bash path directly and
runs the exact unit once as a non-disruptive smoke test while arming. It disarms
itself if that smoke test cannot create a snapshot.

After the next boot, verify that the `final-target` directory exists and note
the last console message. A missing final snapshot narrows the failure to the
first systemd shutdown phase. A complete final snapshot moves suspicion to
systemd-shutdown, kernel device shutdown, or ACPI S5.

Only after a clean baseline should the same tool be armed following an already
guarded and settled iGPU-only transition:

```bash
./tool/arm_shutdown_diagnostics_tty.sh detached
```

That mode additionally requires complete root client inspection and zero dGPU
clients. It does not perform the transition itself.

Use `tool/test_igpu_only_tty.sh` for the guarded transition. The hardened
preflight treats NVIDIA HDMI-audio handles as blockers, so the helper stops the
user PipeWire/WirePlumber services and sockets after ending the graphical
session. It restores audio after confirmed detach or a pre-write block, but
leaves audio and the display manager stopped if topology becomes uncertain.

After a confirmed detach, Plasma can reopen the persistent `/dev/nvidiactl`
node even though every NVIDIA PCI function is absent. Detached diagnostic
arming therefore stops the display manager, graphical login session, and user
audio services before repeating the root client check. A failed arm restores
the session automatically; a successful arm leaves it quiesced for poweroff.
The `disarm` command now restores the session as well.

To cancel the runtime instrumentation before poweroff:

```bash
./tool/arm_shutdown_diagnostics_tty.sh disarm
```

## Stall Response

For a controlled diagnostic boot, configure full Magic SysRq support before
testing. The current host value `kernel.sysrq=16` generally permits emergency
sync but not task dumps. The detached diagnostic guard therefore requires this
temporary runtime setting before it will arm:

```bash
sudo sysctl -w kernel.sysrq=1
```

If the console remains responsive during a stall:

1. Use `Alt+SysRq+w` to show uninterruptible tasks.
2. Use `Alt+SysRq+t` and `Alt+SysRq+l` if more task and CPU context is needed.
3. Before physical power removal, use `Alt+SysRq+s`, then `Alt+SysRq+u`.
4. Do not use `Alt+SysRq+b` or `Alt+SysRq+c` for this investigation.

For a later instrumented NixOS generation, console markers in both the root
`system-shutdown` path and shutdown ramfs, `initcall_debug`, and temporary
`printk.always_kmsg_dump=Y` can distinguish the exitrd, device-shutdown, and
final ACPI phases. Do not enable EFI shutdown dumps permanently because each
normal poweroff writes firmware-backed pstore data.
