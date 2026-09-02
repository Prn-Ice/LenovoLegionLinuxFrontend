# iGPU-only graphics mode driver investigation

## Objective

Determine whether the Lenovo Legion Slim 7 16APH8 (`82Y4`, BIOS `M1CN48WW`)
can safely expose a true integrated-only graphics mode through
LenovoLegionLinux. Do not equate this with Hybrid mode merely allowing the dGPU
to runtime-suspend.

Tracked work: `lllf-cqn.20`.

## Result

The firmware does provide an iGPU-only mode. It is one of four combined GPU
working modes, not an independent replacement for Hybrid:

| User-facing mode | `gsync` sysfs | `igpumode` | Firmware behavior |
| --- | ---: | ---: | --- |
| Hybrid | `1` | `0` (`Default`) | dGPU remains available |
| Hybrid iGPU-only | `1` | `1` (`IGPUOnly`) | requests dGPU ejection |
| Hybrid Auto | `1` | `2` (`Auto`) | AC controls dGPU attach/eject |
| Discrete | `0` | `0` (`Default`) | dGPU/MUX mode; reboot is required |

`gsync` is the historical, inverted Linux sysfs name used for the Hybrid/MUX
boolean. It should be preserved for compatibility, but user space should not
present it as G-Sync.

The live values captured on 2026-08-30 therefore mean **Hybrid**, not Discrete:

```text
igpumode             0
issupportigpumode    3
gsync                1
issupportgsync       2
```

Controlled hardware testing was completed on 2026-08-31 for the internal panel,
Plasma Wayland, suspend/resume, live rollback, and Auto AC/battery behavior. A
guarded iGPU-only transition and rollback both succeeded. Auto also followed AC
state, but its autonomous delayed eject creates a safety race that prevents it
from being exposed as a normal frontend action. External displays, X11,
hibernate, cold boot, and BIOS recovery remain unverified.

The hardened kernel and combined CLI implementation is in the driver repository
at `78f33ee`. The machine was returned to plain Hybrid mode after testing.

## Firmware evidence

The decompiled M1CN48WW DSDT was captured at `/tmp/opencode/DSDT.dsl`. The
GameZone WMI provider is `\_SB.GZFD` (`PNP0C14`, UID `GMZN`), and its serialized
`WMAA` dispatcher begins at `DSDT.dsl:19288`.

### Support values

The support results are capability codes, not available-mode bitmasks:

- Method `40` (`0x28`, `IsSupportGSync`) unconditionally returns `2`
  (`DSDT.dsl:19581-19584`).
- Method `63` (`0x3f`, `IsSupportIGPUMode`) returns `0` only when firmware
  selector `0x7e` contains the unsupported sentinel `0xaa`; otherwise it returns
  `3` (`DSDT.dsl:20018-20028`).

LenovoLegionToolkit treats both methods as supported when the result is greater
than zero. The numeric values `2` and `3` do not describe choices.

### iGPU mode encoding

Method `64` (`0x40`, `GetIGPUModeStatus`) reads firmware selector `0x78` and
maps it as follows (`DSDT.dsl:20030-20053`):

| Selector `0x78` | WMI result | Meaning |
| ---: | ---: | --- |
| `0x00` | `0` | `Default` |
| `0xa5` | `1` | `IGPUOnly` |
| `0xaa` | `2` | `Auto` |

Selector `0x70 == 0xaa` is a validity sentinel that makes the method return
`Default`. An unknown value at selector `0x78` has no explicit ACPI return and
must be rejected by the driver rather than exposed as another mode.

Method `65` (`0x41`, `SetIGPUModeStatus`) consumes one scalar integer
(`DSDT.dsl:20055-20090`):

- `0`: write selector `0x78 = 0`, then call `DGHP(1)` to attach the dGPU.
- `1`: write selector `0x78 = 0xa5`, then call `DGHP(0)` to eject the dGPU.
- `2`: attach or eject the dGPU according to AC/adapter state, then write
  selector `0x78 = 0xaa`.
- A recognized value returns `1`. Invalid inputs have no defined return path.

`DGHP(1)` powers on the PCI function, waits 100 ms, and sends a bus-check
notification. `DGHP(0)` sends PCI eject and bus-check notifications, subject to
firmware power-state checks (`DSDT.dsl:13548-13579`). This proves that an
`igpumode` write can alter live PCI topology; it is not merely a next-boot
preference.

### dGPU notification

Method `66` (`0x42`, `NotifyDGPUStatus`) accepts only status `0` or `1`, records
it in selector `0x79`, and reconciles dGPU attachment with `IGPUOnly` or `Auto`
mode (`DSDT.dsl:20092-20128`). LenovoLegionToolkit retries this notification
while iGPU-only is selected if the dGPU remains visible. It is an internal
topology synchronization mechanism, not a user-facing graphics mode.

### Combined state machine

LenovoLegionToolkit independently corroborates the relationship in
`LenovoLegionToolkit.Lib/Features/Hybrid/HybridModeFeature.cs:19-29` and
`:157-172`:

```text
Hybrid             = GSync Off + IGPUMode Default
Hybrid iGPU-only   = GSync Off + IGPUMode IGPUOnly
Hybrid Auto        = GSync Off + IGPUMode Auto
Discrete           = GSync On  + IGPUMode Default
```

The Linux driver's `gsync` attribute inverts the raw firmware G-Sync value, so
the same combinations appear through sysfs as shown in the result table.

## Driver changes

The existing driver source at base commit `4055714` already defined methods
`63` through `66`, but exposed them through an unsafe generic helper. The kernel
work first landed in `5a2a2d1` and is included in `78f33ee`; it hardens the
contract with these properties:

- Hide `igpumode` and `notify_dgpu` unless method `63` returns a positive
  capability code.
- Hide `gsync` unless method `40` returns a positive capability code.
- Accept only `0`, `1`, or `2` for `igpumode`; reject other values with
  `-EINVAL` before calling firmware.
- Accept only `0` or `1` for `notify_dgpu`.
- Reject an iGPU-mode write with `-EOPNOTSUPP` when firmware reports no support.
- Serialize reads and writes through the existing WMI mutex.
- Validate the current mode before a write, avoid a no-op write, and require
  strict readback after the setter returns.
- Reject unknown firmware read values rather than silently treating them as a
  supported mode.

The generic writer previously parsed an unrestricted integer and truncated it
to one byte. It also did not lock WMI writes. This was especially dangerous for
method `65`, whose undefined inputs reach firmware code with live PCI side
effects.

The support attributes remain raw read-only diagnostics. User space should
interpret only zero versus positive; it should not expose `2` and `3` as mode
sets.

## User-space contract

Driver commit `78f33ee` implements an authoritative user-space contract that
combines `gsync` and `igpumode` rather than exposing two unrelated controls:

```text
graphics-mode status
graphics-mode status --json
graphics-mode choices
graphics-mode reconcile --json
graphics-mode set hybrid
graphics-mode set hybrid-igpu-only
graphics-mode set hybrid-auto
graphics-mode set discrete
```

Required behavior:

- `status` validates both raw reads and prints exactly one combined mode; JSON
  status separates selected policy, expected topology, effective topology,
  reconciliation state, available modes, and root-observed dGPU clients.
- `choices` advertises Hybrid/Discrete only when G-Sync support is positive and
  advertises iGPU-only/Auto only when iGPU-mode support is positive.
- `set` rejects a value outside `choices` before requesting privilege.
- A detach preflight scans root-visible `/proc/*/fd` handles for NVIDIA and its
  DRM nodes, fails closed when inspection is incomplete, and rechecks
  immediately before the firmware write.
- Transitions to Hybrid, Hybrid iGPU-only, or Hybrid Auto set the historical
  Hybrid/MUX boolean first, then set `igpumode`.
- A transition to Discrete first restores `igpumode=Default`, then changes the
  Hybrid/MUX boolean.
- Reconciliation uses observed PCI availability with `NotifyDGPUStatus`, up to
  five attempts at five-second intervals. Exit `2` means the write was blocked
  by preflight; exit `3` means the selector was accepted but topology did not
  settle.
- User space reports that Hybrid/Discrete MUX changes require reboot and that
  iGPU-only/Auto can change live dGPU availability.
- The existing `hybrid-mode-enable/disable` commands remain available during
  migration and retain their current meaning.

The Flutter model should replace `bool? hybridModeEnabled` with a graphics-mode
enum plus authoritative selected/effective/reconciliation state. It should
label the integrated option **Hybrid iGPU-only** and represent **Hybrid Auto**
truthfully when another tool selected it. Auto must remain non-actionable; an
advertised firmware choice is not sufficient evidence that a desktop action is
safe.

## Controlled hardware validation

Before the first iGPU-only write:

1. Close all dGPU clients and verify the dGPU is runtime-suspended or powered
   off.
2. Disconnect every external display and keep the internal panel usable.
3. Confirm the BIOS/UEFI graphics-mode control can restore Hybrid mode without
   relying on the operating system.
4. Capture PCI, DRM connector, driver binding, runtime-power, AC state, and
   current combined mode.
5. Test `Hybrid -> Hybrid iGPU-only -> Hybrid` first. Test Auto separately on
   battery and AC only after rollback succeeds.

For every transition, verify:

- strict mode readback;
- PCI and DRM topology after firmware settles;
- internal panel and every physical external display output;
- dGPU runtime state and unexpected wakeups;
- Wayland and X11 session behavior where supported;
- suspend/resume and hibernate;
- persistence across reboot and cold boot;
- recovery through BIOS/UEFI after a failed userspace boot.

Do not write EC or MMIO registers directly, unbind `acpi-ec`, remove the dGPU
PCI device as a substitute for firmware mode, or run the first test while an
external display is the only usable screen. Do not claim a battery-life
improvement without comparable measured idle data.

### Results from 2026-08-31

#### Unguarded detach attempts

Plasma and later detached Code/Electron processes retained NVIDIA handles.
Firmware partially removed the dGPU and rollback required reboot. The detailed
evidence is in the `lllf-j9t` notes.

#### Guarded Hybrid to Hybrid iGPU-only

Passed with complete root inspection, zero clients, two reconciliation
attempts, NVIDIA PCI/DRM removal, and AMD-only Plasma Wayland on internal eDP.
Evidence: `/tmp/lllf-igpu-only-2026-08-31T12-37-01+01-00.log`.

#### iGPU-only suspend/resume

Passed; AMD/internal eDP resumed and NVIDIA remained detached. The detailed
evidence is in the `lllf-j9t` notes.

#### iGPU-only to Hybrid rollback

Passed in one attempt. NVIDIA VGA/audio, drivers, DRM, and `nvidia-smi`
recovered before Plasma restart.
Evidence: `/tmp/lllf-restore-hybrid-2026-08-31T14-58-56+01-00.log`.

#### Hybrid to Auto on AC

Passed; selected Auto remained attached and settled, with Plasma functional.
Evidence: `/tmp/lllf-auto-ac-2026-08-31T15-20-41+01-00.log`.

#### Auto AC to battery

Passed only with all graphical clients stopped. Firmware detached autonomously
after about 29 seconds, briefly reporting partial topology, without explicit
CLI reconciliation.
Evidence: `/tmp/lllf-auto-battery-2026-08-31T17-17-01+01-00.log`.

#### Auto battery suspend/resume

Passed; the NVIDIA slot remained absent and AMD/internal eDP resumed. The
detailed evidence is in the `lllf-j9t` notes.

#### Auto battery to AC

Passed with Plasma running. Firmware hot-added NVIDIA VGA/audio and both
drivers bound successfully. Evidence is in the boot journal at
`2026-08-31 17:25:48`.

#### Final Auto to Hybrid restore

Passed in one attempt; the machine is back in attached, settled Hybrid mode.
Evidence: `/tmp/lllf-restore-hybrid-2026-08-31T17-29-36+01-00.log`.

The tests establish these safety constraints:

1. Stopping only `display-manager.service` is insufficient. The graphical user
   target, Wayland/X11 sessions, and detached Electron applications can retain
   dGPU handles. Root handle inspection must remain authoritative.
2. Selected policy is not effective topology. On an earlier iGPU-only reboot,
   the selector persisted but NVIDIA enumerated and bound before
   `legion_laptop` loaded. Reconciliation must run before the display manager.
3. Auto is not safe for ordinary desktop use. Once selected, later AC loss can
   trigger firmware ejection independently of the CLI preflight. A userspace
   power monitor cannot atomically observe AC loss, prevent new opens, quiesce
   every client, and beat the autonomous firmware transition.
4. The repeated `00:01.1` D0-to-D3hot refusal, NVIDIA SBIOS/EDID assertions, and
   `00:08.1` spurious PME interrupts did not prevent tested transitions, but
   remain residual warnings rather than validated harmless behavior.

### Hibernate failure on generation 465

Do not hibernate while Hybrid iGPU-only is selected. Two attempts on
2026-09-02 failed with the same sequence:

- Boot `1b5154c8` requested hibernation at 09:10:57. The kernel entered the
  hibernation path at monotonic 2962.114, but rolled back during S4 snapshot
  preparation before creating an image or reaching platform power-down. At
  monotonic 2973.482 the NVIDIA root port reported `Card present` and `Link
  Up`; systemd reported that hibernation had returned after 12.647 seconds of
  monotonic wall time.
- Boot `bc895c16` requested hibernation at 09:20:10. The pre-image S4 path
  rolled back again. The NVIDIA slot became present at monotonic 148.093, and
  systemd reported a return after 9.786 seconds.
- Both returns re-enumerated the NVIDIA VGA and audio functions and loaded
  NVIDIA DRM into the thawed AMD-only Wayland session. KWin then logged failed
  DRM lessee queries, output configuration, EGL initialization, and `card0`
  access before the display became unusable.
- Both attempts required forced shutdown. The first subsequent boot attempt
  visibly stalled at GRUB or kernel text before persistent journaling; the
  second boot succeeded. Boot `76d2cb91` then reconciled the selected iGPU-only
  policy to detached in six attempts before starting SDDM, with no failed units
  or pstore record.

The kernel's pre-image `pm_wakeup_pending()` check is the path that can return
successfully without writing an image, which matches the observed silent
rollback. ACPI wake for `GPP0` / PCI root port `0000:00:01.1` is enabled, and
NVIDIA hotplug coincides with that rollback. This makes the root-port wake path
the leading hypothesis, not a proven cause. Do not repeat the test or toggle
the wake source until diagnostics can survive the failed S4 path and an aborted
hibernate can reconcile topology before the graphical session thaws.

The following acceptance items remain open:

- external HDMI and USB-C routing with physical displays;
- X11 behavior;
- safe resolution of the detached hibernate failure;
- exercised BIOS/UEFI recovery;
- comparable idle-power measurements before making battery-life claims.

## Completion gate

Firmware semantics, the guarded driver/CLI contract, internal-panel live
transitions, suspend/resume, and live Hybrid rollback are validated. Safe
frontend work may expose read-only selected/expected/effective status now.

Hybrid Auto must remain disabled. Hybrid iGPU-only must remain a controlled TTY
operation until early-boot reconciliation and a typed privileged frontend flow
can preserve the root preflight contract without claiming success before
effective topology settles. The overall feature is not complete until the open
matrix items above are either validated or explicitly excluded from the
shipping scope.
