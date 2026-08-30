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
|---|---:|---:|---|
| Hybrid | `1` | `0` (`Default`) | iGPU drives normal work; dGPU remains available |
| Hybrid iGPU-only | `1` | `1` (`IGPUOnly`) | firmware requests dGPU ejection |
| Hybrid Auto | `1` | `2` (`Auto`) | firmware attaches/ejects the dGPU based on AC state |
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

No iGPU-mode write was performed during this investigation. Firmware evidence
is sufficient to harden the API, but display routing, session behavior, and
rollback still require a controlled hardware test before the frontend enables
the option.

The hardened kernel and combined CLI implementation is committed in the driver
repository as `5a2a2d1`.

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
|---:|---:|---|
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
`63` through `66`, but exposed them through an unsafe generic helper. Driver
commit `5a2a2d1` hardens the contract with these properties:

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

Driver commit `5a2a2d1` implements an authoritative user-space contract that
combines `gsync` and `igpumode` rather than exposing two unrelated controls:

```text
graphics-mode status
graphics-mode choices
graphics-mode set hybrid
graphics-mode set hybrid-igpu-only
graphics-mode set hybrid-auto
graphics-mode set discrete
```

Required behavior:

- `status` validates both raw reads and prints exactly one combined mode.
- `choices` advertises Hybrid/Discrete only when G-Sync support is positive and
  advertises iGPU-only/Auto only when iGPU-mode support is positive.
- `set` rejects a value outside `choices` before requesting privilege.
- Transitions to Hybrid, Hybrid iGPU-only, or Hybrid Auto set the historical
  Hybrid/MUX boolean first, then set `igpumode`.
- A transition to Discrete first restores `igpumode=Default`, then changes the
  Hybrid/MUX boolean.
- User space reports that Hybrid/Discrete MUX changes require reboot and that
  iGPU-only/Auto can change live dGPU availability.
- The existing `hybrid-mode-enable/disable` commands remain available during
  migration and retain their current meaning.

The Flutter model should replace `bool? hybridModeEnabled` with a graphics-mode
enum plus an available-mode set. It should add **Hybrid Auto**, label the
integrated option **Hybrid iGPU-only**, and enable either only when the combined
backend contract advertises it.

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

## Completion gate

Firmware semantics, the safe driver read/write contract, and the combined CLI
contract are now implemented. The frontend option remains disabled until that
driver is deployed and the controlled hardware matrix above demonstrates
display routing, session survival, suspend/resume, persistence, and BIOS
rollback on this machine.
