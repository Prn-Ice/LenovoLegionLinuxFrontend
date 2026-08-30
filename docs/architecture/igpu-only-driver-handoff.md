# iGPU-only graphics mode driver handoff

## Objective

Determine whether the Lenovo Legion Slim 7 16APH8 (`82Y4`, BIOS `M1CN48WW`)
can safely expose a true integrated-only graphics mode through
LenovoLegionLinux. Do not equate this with Hybrid mode merely allowing the dGPU
to runtime-suspend.

Tracked work: `lllf-cqn.20`.

The frontend now presents three graphics concepts:

- **Hybrid**: iGPU handles normal work and the dGPU remains available on demand.
- **Integrated only**: shown unavailable until an authoritative backend contract
  exists.
- **Discrete only**: dGPU remains primary.

The UI intentionally does not write `igpumode` yet.

## Key discovery

The local driver already contains an incomplete iGPU-mode interface. In
`/home/prnice/Projects/personal/LenovoLegionLinux/kernel_module/legion-laptop.c`:

- GameZone WMI method `63` reports iGPU-mode support.
- Method `64` reads iGPU mode.
- Method `65` writes iGPU mode.
- Method `66` notifies dGPU status.
- `enum IGPUState` defines `default = 0`, `iGPUOnly = 1`, and `auto = 2`.
- Read/write `igpumode`, write-only `notify_dgpu`, and read-only
  `issupportigpumode` sysfs attributes are registered unconditionally with the
  other GameZone attributes.

Relevant source locations at local commit `f4849cd`:

| Area | Lines |
|---|---:|
| WMI method IDs and `IGPUState` | `legion-laptop.c:2425-2434` |
| `igpumode` show/store | `legion-laptop.c:5540-5558` |
| support and dGPU notification attributes | `legion-laptop.c:5560-5591` |
| sysfs attribute registration | `legion-laptop.c:6388-6428` |
| visibility policy | `legion-laptop.c:6526-6582` |

Python exposes only the separate boolean `gsync` feature as `hybrid-mode`; it
does not model `igpumode` or `issupportigpumode`. See
`python/legion_linux/legion_linux/legion_cli.py:277-298` and
`python/legion_linux/legion_linux/legion.py:482-484`.

## Live read-only evidence

Captured on 2026-08-30 from the currently booted driver at
`/sys/module/legion_laptop/drivers/platform:legion/legion`:

```text
igpumode             0
issupportigpumode    3
gsync                1
issupportgsync       2
```

File presence is not proof of support because the current visibility callback
does not gate these attributes through methods `63` or `40`. The support values
`3` and `2` must not be coerced to booleans without understanding whether they
are bitmasks, mode sets, or firmware-specific status codes.

Do not write `1` or `2` to `igpumode` based only on the enum names. The generic
store helper accepts an unrestricted integer and performs no enum bounds check,
read-before-write, or read-after-write validation.

## Questions to answer

1. What do GameZone methods `63` through `66` do in the M1CN48WW DSDT, including
   input/output buffer layout and return codes?
2. Are `issupportigpumode = 3` and `issupportgsync = 2` bitmasks? If so, which
   bits correspond to `default`, `iGPUOnly`, `auto`, Hybrid, and Discrete?
3. Is `igpumode` an independent policy used only while Hybrid is enabled, or is
   it part of one mutually exclusive graphics-mode state machine?
4. Does selecting iGPU-only require a sequence involving `gsync`, `igpumode`,
   and/or `notify_dgpu` rather than one isolated write?
5. Does firmware apply the change immediately, after logout, after reboot, or
   only after a cold boot?
6. Which internal and external display connectors are routed through the dGPU
   on this model, and what becomes unavailable in iGPU-only mode?
7. Is the state persistent across reboot, suspend/resume, firmware updates, and
   AC removal? What is the proven rollback path?

## Investigation sequence

### 1. Preserve a baseline

Record exact kernel, module, source commit, BIOS, AC/battery state, graphics
session, connected displays, and these read-only facts:

```bash
cat /sys/module/legion_laptop/drivers/platform:legion/legion/{gsync,issupportgsync,igpumode,issupportigpumode}
lspci -nnk | rg -A3 -i 'vga|3d|display'
for card in /sys/class/drm/card*; do readlink -f "$card/device"; done
loginctl show-session "$XDG_SESSION_ID" -p Type -p Remote
```

Capture DRM connector status and each GPU's `boot_vga`, driver binding, runtime
status, and power-control state. Do not wake a suspended dGPU merely to collect
optional telemetry.

### 2. Trace firmware semantics

Use the already decompiled M1CN48WW ACPI artifacts in `/tmp/opencode` as a
starting point, but regenerate them if they are no longer available. Trace the
GameZone WMI dispatcher for method IDs `0x3f` through `0x42` and document every
firmware branch and side effect.

Compare this with LenovoLegionToolkit or other authoritative Lenovo software
only as supporting evidence. UI labels are not sufficient evidence for a raw
firmware value.

### 3. Fix the read contract first

Before any write experiment:

- Validate support-method return semantics.
- Hide `igpumode` and `notify_dgpu` when unsupported instead of relying on the
  shared GameZone GUID being present.
- Validate read values strictly against the proven mode set.
- Prefer an enum-style `graphics_mode` plus `graphics_mode_choices` contract if
  `gsync` and `igpumode` form one state machine.
- If they are independent, expose separate accurately named capabilities rather
  than forcing them into one enum.
- Preserve the existing `gsync` attribute or CLI behavior while external users
  migrate; do not silently change its meaning.

### 4. Add a guarded write path

Only after read semantics are proven:

- Reject values outside the advertised choices with `-EINVAL`.
- Return `-EOPNOTSUPP` when firmware does not advertise the requested mode.
- Serialize related WMI operations and define any required method sequence.
- Read before writing, read back after firmware has settled, and report a
  mismatch as failure.
- Surface whether reboot or cold boot is required.
- Keep a tested recovery path through BIOS/UEFI before the first experimental
  iGPU-only write.

Do not guess WMI values, write EC or MMIO registers, unbind `acpi-ec`, force
another model configuration, remove the dGPU PCI device as a substitute for a
firmware mode, or test while an external display is the only usable screen.

### 5. Validate all consequences

For every supported mode, verify after the required reboot/cold boot:

- authoritative mode readback;
- PCI and DRM device topology;
- internal panel and every physical external display output;
- dGPU runtime power state and whether it can unexpectedly wake;
- suspend/resume and hibernate;
- AC and battery operation;
- graphics session startup on Wayland and X11 where supported;
- return to Hybrid/Auto and Discrete, including recovery after a failed boot.

Do not claim a battery-life improvement without comparable measured idle data.

## Proposed user-space contract

If firmware proves that these are mutually exclusive modes, prefer:

```text
graphics-mode status
graphics-mode choices
graphics-mode set hybrid
graphics-mode set integrated-only
graphics-mode set discrete-only
```

The CLI must print the authoritative current mode and available choices, reject
unsupported values before requesting privilege, and state the reboot
requirement. The Flutter follow-up should replace `bool? hybridModeEnabled` with
an enum plus available-mode set and enable Integrated only only when explicitly
advertised.

If firmware instead proves that `igpumode` is a policy layered on Hybrid mode,
model that relationship directly and revise the frontend labels before enabling
the option.

## Success criteria

The investigation is complete when the support values and mode relationship are
understood from firmware evidence, unsupported sysfs files are hidden, all
accepted values are bounded and read back authoritatively, reboot and display
consequences are documented, and a safe rollback has been demonstrated. The
frontend option remains disabled until that contract is shipped and tested.
