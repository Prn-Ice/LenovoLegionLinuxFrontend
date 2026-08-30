# Legion driver issues handoff

## Objective

Make the LenovoLegionLinux driver return truthful fan-curve and power-limit data
on the Lenovo Legion Slim 7 16APH8, then validate the frontend against those
readings. The frontend already rejects the current zero-filled data and must not
be weakened to make unsupported controls appear.

This document captures the live state on 2026-08-30. The earlier Kernel 7
deployment history remains in
[fan-controller-kernel-7-handoff.md](fan-controller-kernel-7-handoff.md).

## Tracked work

| Issue | Scope |
|---|---|
| `lllf-cqn.8` | Make the M1CN fan controller expose a complete, usable curve. |
| `lllf-zfg` | Find authoritative defaults for every supported power-limit field. |
| Upstream [issue #132](https://github.com/johnfanv2/LenovoLegionLinux/issues/132) | Legion Slim 7 16APH8 support history and model evidence. |

Do not close `lllf-cqn.8` merely because the module binds or creates hwmon. The
current module does both, but the curve remains unusable.

## Host and deployment

| Item | Live value |
|---|---|
| Product | Lenovo `82Y4`, Legion Slim 7 16APH8 |
| BIOS | `M1CN48WW` |
| Kernel | NixOS `7.2.0` |
| Module | `/run/booted-system/kernel-modules/lib/modules/7.2.0/kernel/drivers/platform/x86/legion-laptop.ko` |
| Driver source | `johnfanv2/LenovoLegionLinux` at `3893e203332d60effea688a3043abd86046997ad` |
| Nix source pin | `/home/prnice/Dotfiles/nixos-flaky-tests/hosts/nixos/hardware/legion_slim.nix` |
| Platform root | `/sys/module/legion_laptop/drivers/platform:legion/legion` |
| hwmon name | `legion_hwmon` |
| Active profile during capture | `balanced`; choices are `low-power balanced performance custom` |

The Kernel 7 transition itself is complete. The boot log contains:

```text
legion legion: legion_laptop platform driver probing
legion legion: Read identifying information: DMI_SYS_VENDOR: LENOVO; DMI_PRODUCT_NAME: 82Y4; DMI_BIOS_VERSION:M1CN48WW
legion legion: Using configuration for system: M1CN
legion legion: legion_laptop loaded for this device
```

The source pin includes upstream [PR #423](https://github.com/johnfanv2/LenovoLegionLinux/pull/423)
and [PR #434](https://github.com/johnfanv2/LenovoLegionLinux/pull/434). Do not
revisit ACPI EC binding unless these probe facts regress.

## Safety constraints

- Do not unbind `PNP0C09:00` from `acpi-ec`.
- Do not force-load another model configuration.
- Do not write guessed values to power-limit, fan-curve, EC, ACPI, WMI, or
  debugfs interfaces.
- Do not treat file presence, a successful read, or a zero return as proof that
  a feature is supported.
- Do not use slider bounds or `CPUDefaultPowerLimit` as a complete default
  profile.
- Preserve unrelated changes in `/home/prnice/Dotfiles/nixos-flaky-tests`.
- Keep initial experiments read-only. Add one driver change at a time, build a
  new immutable NixOS generation, reboot, and capture before/after evidence.

## Issue 1: unusable fan curve

### Live evidence

The synthetic device and hwmon provider are present. At capture time:

| Attribute | Value |
|---|---:|
| `auto_points_size` | `10` |
| `fan1_input` / `fan2_input` | about `1900 RPM` |
| `fan1_max` / `fan2_max` | `10000 RPM` |
| `pwm1_auto_point1_pwm` | `2` |
| `pwm1_auto_point10_pwm` | `20` |
| every sampled `pwm2_auto_point*_pwm` | `0` |
| sampled CPU/GPU/IC temperatures and hysteresis | `0` |
| sampled acceleration and deceleration | `0` |

The frontend reads all ten points and rejects the curve if any required value is
missing or if PWM and temperature ranges are invalid. That behavior is in
`lib/core/services/legion_sysfs_service.dart`; it is intentional protection
against presenting or writing a fabricated curve.

### Driver path

At the pinned revision, `model_m1cn` selects:

```c
.access_method_fanspeed = ACCESS_METHOD_WMI3,
.access_method_temperature = ACCESS_METHOD_WMI3,
.access_method_fancurve = ACCESS_METHOD_WMI3,
.access_method_fanfullspeed = ACCESS_METHOD_WMI,
```

The former local `read_file_fix` branch changed M1CN fan-curve access from
`ACCESS_METHOD_WMI3` to `ACCESS_METHOD_EC`. That branch predated the Kernel 7
platform-device fixes and must not be restored wholesale. Its one-line access
method change is a useful controlled hypothesis only after read-only comparison
of WMI3 and EC/debugfs data.

### Investigation order

1. Capture all ten WMI3 points, live fan RPM, temperatures, `fan*_max`, and the
   read-only debugfs fan report in each firmware profile.
2. Determine whether the zero fields come directly from firmware, from wrong
   M1CN WMI feature IDs, or from conversion/indexing in the hwmon callbacks.
3. Compare the pinned M1CN callbacks with a known-working WMI3 model using the
   same EC chip ID `0x5507`.
4. Build a diagnostic driver that logs method, feature ID, point index, return
   status, raw payload, and converted value. Rate-limit or debug-gate these logs.
5. If WMI3 is confirmed unusable, test the isolated M1CN `ACCESS_METHOD_EC`
   patch in a new generation using reads only. Validate addresses against the
   model evidence in upstream issue #132 before enabling writes.
6. Enable frontend curve controls only after all ten points have credible,
   ordered temperatures, both fan channels, and repeatable round-trip behavior.

## Issue 2: zero power limits

### Live evidence

The platform root exposes CPU and GPU power-limit attributes, including:

```text
cpu_longterm_powerlimit
cpu_shortterm_powerlimit
cpu_peak_powerlimit
cpu_cross_loading_powerlimit
cpu_apu_sppt_powerlimit
cpu_default_powerlimit
gpu_ctgp_powerlimit
gpu_ppab_powerlimit
gpu_boost_clock
gpu_temperature_limit
```

Every frontend-consumed attribute currently reads `0`. Kernel logs generated by
these reads repeatedly contain:

```text
legion_laptop: get_simple_wmi_attributewith raw value: 0
```

The Flutter repository requires positive values and filters every zero reading,
leaving no controls to render. See `PowerRepository.loadSnapshot` in
`lib/features/power/repository/power_repository.dart` and `effectiveMin` in
`lib/features/power/models/power_limit.dart`.

### Driver path

`model_m1cn` does not initialize `access_method_powerlimits`, so its value is
`ACCESS_METHOD_NO_ACCESS`. The power-limit show/store callbacks nevertheless use
the legacy simple CPU/GPU WMI methods in their default switch branches. Sysfs
visibility checks only test whether the CPU/GPU WMI GUID exists; they do not
hide these attributes when the model's power-limit access method is
`ACCESS_METHOD_NO_ACCESS`.

This creates a misleading driver contract: files are visible and writable even
though all legacy reads return zero on this firmware. Other model configs
explicitly select `ACCESS_METHOD_WMI3` or `ACCESS_METHOD_WMI3_CLAMPED`, but that
does not prove either method is valid for M1CN.

### Investigation order

1. Verify zero results in `balanced` and `custom` while connected to AC, using
   reads only. Record the exact profile and AC state with every capture.
2. Instrument each legacy CPU/GPU WMI method to record status, payload length,
   raw bytes, extraction offset, and converted result. Avoid the current
   unconditional per-read logging.
3. Probe WMI3 feature availability read-only before assigning
   `ACCESS_METHOD_WMI3` to M1CN. Compare feature IDs and units with a working AMD
   Legion model rather than assuming parity from the EC chip ID.
4. If no truthful read method exists, fix sysfs visibility so M1CN does not
   advertise unsupported writable attributes. Returning unavailable is safer
   than exporting zero-valued controls.
5. If positive values become available, validate units, safe ranges, PL1/PL2
   coupling, persistence across profile changes, and read-after-write behavior
   before enabling writes.
6. Resolve `lllf-zfg` separately: current values are not authoritative defaults.
   A restore action requires a complete model-specific default source.

## Log amplification

Opening or polling the Power page reads multiple limit attributes. The current
driver logs `get_simple_wmi_attributewith raw value: 0` for each read, producing
large repeated kernel-log bursts. Driver diagnostics should use `pr_debug`,
dynamic debug, or a rate-limited path rather than unconditional informational
logging. The frontend should not be changed to consume zero values to suppress
the logs.

## Read-only capture commands

Run these after each test generation and save the output with the exact source
revision. Dynamic `hwmonN` names may change after reboot.

```bash
uname -r
modinfo legion_laptop
journalctl -k -b --no-pager | rg -i 'legion|acpi.*ec'
readlink -f /sys/bus/platform/devices/PNP0C09:00/driver
ls -la /sys/module/legion_laptop/drivers/platform:legion/legion
ls -la /sys/module/legion_laptop/drivers/platform:legion/legion/hwmon
sensors
cat /sys/firmware/acpi/platform_profile
cat /sys/firmware/acpi/platform_profile_choices
```

For the large fan and power attribute sets, use a small read-only capture script
that records path, read status, and value. Do not use shell redirection to any
sysfs or debugfs path.

## Success criteria

Fan support is complete when the synthetic device remains bound, all ten points
are complete and ordered, both fan channels and required temperature channels
contain plausible data across the curve, values are stable across repeated
reads, and the frontend accepts the curve without relaxed validation.

Power-limit support is complete when the driver either hides unsupported
attributes or returns documented positive values with verified units and safe
ranges. Writes require Custom mode, AC power, read-before-write, read-after-write,
and rollback validation. Restore defaults remains out of scope until every
exposed field has an authoritative model-specific default.
