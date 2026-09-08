# Legion driver issues handoff

## Objective

Make the LenovoLegionLinux driver return truthful fan-curve and power-limit data
on the Lenovo Legion Slim 7 16APH8, then validate the frontend against those
readings. The frontend rejects unusable zero-filled data and must not be
weakened to make unsupported controls appear. Phase 1 validated power-limit
reads and one controlled PL1 write; fan-curve support remains unresolved.

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

## Initial host and deployment (before Phase 1)

This table records the original capture. The Phase 1 build and boot validation
below record the subsequent driver revision and successful power-limit reads.

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

## Firmware analysis (M1CN48WW DSDT, captured 2026-08-30)

The DSDT was dumped read-only and decompiled (artifacts in `/tmp/opencode`,
regenerate with `iasl -d`). All WMI objects below live in the `GZFD` PNP0C14
device (`_UID GMZN`). This section is confirmed firmware behavior, not
hypothesis.

### Fan-curve firmware design

- `Fan_Get_Table` (LENOVO_FAN_METHOD `92549549-…`, method 5, `WMAB`->`GFAN`) is
  a stub on M1CN: it ignores its `FanID`/`SensorID` arguments and returns an
  88-byte buffer whose `fan_speed[10]` and `sensor_value[10]` are both copies of
  `CFST` — the ten curve step indices stored in EC RAM `F101`-`F10A`. It never
  returns temperatures or real fan speeds. The live `1,2,3,4,5,6,7,8,8,8` are
  those step indices, misinterpreted by the driver as percentages.
- The actual curve is a two-level design: predefined per-mode tables
  (`FNT0`, fifteen sub-tables with an RPM palette `0..4700` plus ten CPU temp
  thresholds; `FIN5`-`FIN9` with CPU/GPU/IC per-point temp min/max) and ten
  step indices selecting the RPM per point.
- `Fan_Set_Table` (method 6, `SFAN`) accepts mode + ten step indices (words at
  `0x06`-`0x18`) and programs EC `F101`-`F10A`, per-point RPM (`CRP*`, = palette
  value / 100), and full CPU/GPU/IC temp tables. The pinned driver's write
  buffer layout matches the field offsets but writes percentage-like values
  where step indices are required.
- The complete per-mode table (RPM palette, ten CPU temps, current/default max
  fan speed) is readable through WMI data block `A7`
  (`87FB2A6D-D802-48E7-9208-4576C5F5C8D8`, 15 instances, `WQA7`->`SFTW`),
  the block that Windows surfaces as `LENOVO_FAN_TABLE_DATA`. The kernel WMI
  core queries `WQxx` directly; the missing `WCA7` (expensive-flag enable) is
  safely skipped by the kernel.
- The authoritative per-point curve state lives in the memory-mapped `DFAN`
  region at `0xFE0B0F00` (0x1000 bytes), outside the driver's current RAM-IO
  window (`0xFE0B0400` + `0x600`):
  - CPU points `+0x00..`: `CLxx`/`CTxx` (temp min/max), `CRPx` (RPM/100),
    stride 6 per point; point 9 adds `CRA8`/`CTA9`.
  - GPU points from `+0x3C`: `GLxx`/`GTxx`/`GRP*` (same layout).
  - IC points from `+0x78`: `ELxx`/`ETxx`/`ERP*`.
  - Step indices `+0xE0..0xE9` (`F101`-`F10A`).
  - Power limits `+0xF0..`: `CCPL`,`CLPL`,`CSPL`,`CGDB` (16-bit), `GCDB`,
    `GPTL` (8-bit), `TPPT`,`GTGP` (16-bit), `CPPL`,`CCTL` (8-bit).
  There are no per-point accel/decel registers; acceleration is mode-level
  (constant per `FNT0` sub-table). `EC lockfancontroller` reads `true`.
- The old `read_file_fix` EC method used `ec_register_offsets_v0`
  (`EXT_FAN1_BASE 0xC540` etc.), which does not match this layout; live EC
  temp/RPM reads return 0. It must not be restored.

### Phase 0 read-only MMIO capture (2026-08-30, `balanced`, AC)

`/dev/mem` dumps of `DFAN 0xFE0B0F00` (two passes, identical) and `ECMM
0xFE0B0400` are archived in `/tmp/opencode/phase0/` with context
(`7.2.0`, fans 1900 RPM, CPU 55 C, GPU 48 C).

- Power limits at `DFAN +0xF0` are live and match the DSDT lazy-init defaults
  exactly: `CCPL 45`, `CLPL 54`, `CSPL 54`, `CGDB 0`, `GPTL 87`, `TPPT 45`,
  `GTGP 60`, `CPPL 65`, `CCTL 100`. The power-limit fix is de-risked.
- The entire curve area (`+0x00..0xB3`) and the step indices (`+0xE0..0xE9`)
  read zero. `F10A == 0`, so `GFAN` skips its EC refresh and returns the ACPI
  `CFST` package initializer (`1..8,8,8`) verbatim: the curve the driver
  exports today is a DSDT constant, not hardware state.
- Consequence: no tool has programmed the curve since boot. The DFAN curve
  registers only become authoritative after a `Fan_Set_Table` write (which
  populates all CPU/GPU/IC temp tables and per-point RPMs and sets `CMRD`).
  Until then, the truthful curve source is the per-mode `FNT0` tables via the
  `A7`/`SFTW` WMI block (RPM palette, CPU temp thresholds, current/default max
  speed) plus the step indices, composed per point
  (`RPM_i = FanTable_Data[step_i - 1]`).

### Power-limit firmware design

- The legacy CPU/GPU WMI method blocks are empty stubs on M1CN:
  `WMAC` (`14afd777-…`, LENOVO_CPU_METHOD) only implements method `0x0E`
  (support-OC -> 0) and `WMAD` (LENOVO_GPU_METHOD) unconditionally returns 0.
  Every legacy power-limit read is therefore structurally zero.
- The supported interface is the "Other Method" (`WMAE`,
  `dc2a8805-3a8c-41ba-a6f7-092e0089cd3b`, GetFeatureValue=17 /
  SetFeatureValue=18), which the pinned driver already implements for WMI3
  power-limit models. Verified live: temperature reads through it work
  (53 C CPU / 46 C GPU).
- M1CN feature map (reads lazily initialize EC defaults):
  - CPU short-term -> `CSPL` (default 54 W), long-term -> `CLPL` (54 W),
    peak -> `CPPL` (65 W), temperature limit -> `CCTL` (100 C),
    cross-load -> `CCPL` (45 W).
  - GPU power boost -> `CGDB` (20 W), cTGP -> `GTGP` (60 W),
    temperature limit -> `GPTL` (87 C), AC power-target offset -> `TPPT`.
  - APU SPPT (feature 5) and CPU L1 tau (feature 7) return hard 0:
    unsupported.
  - `SetFeatureValue` writes are gated on thermal mode `GZ44 == 0x03`
    (Custom), matching the required write gating.
- `model_m1cn` leaves `access_method_powerlimits` at `ACCESS_METHOD_NO_ACCESS`,
  but the power-limit show/store callbacks fall through to the stub legacy
  methods, and `legion_sysfs_is_visible` only checks legacy GUID presence.
  That is why zero-valued writable attributes are advertised.

### Phase 1 driver build (2026-08-30)

Local driver `main` now treats `read_file_fix` as retired. Commit `bafa1f3`
restores `kernel_module/` exactly from the deployed Kernel-7 upstream pin
`3893e20`; commit `f4849cd` adds the M1CN power-limit fix:

- select `ACCESS_METHOD_WMI3` for M1CN power limits;
- probe WMI3 GetFeatureValue-backed attributes during sysfs visibility and
  hide features that fail or return 0 (including M1CN APU SPPT and L1 tau);
- hide legacy-only power attributes for WMI3 models instead of calling stub
  CPU/GPU WMI methods;
- reject M1CN SetFeatureValue writes outside Custom mode with `-EPERM`;
- demote the unconditional legacy raw-value log from `pr_info` to `pr_debug`.

Do not globally hide `ACCESS_METHOD_NO_ACCESS`: most older model configs leave
that field unset and intentionally use the legacy fallback. Auditing and making
legacy access explicit is separate upstream work.

The NixOS configuration pins local driver commit `f4849cd` through a
`git+file` flake input. `nix build
.#nixosConfigurations.nixos.config.system.build.toplevel` succeeded and built
`/nix/store/79yjssydl0q1hfs4v9ggkfrsk7lmk9fl-lenovo-legion-module-0.0.22-unstable-2026-08-21`.
Its module contains the Custom-mode rejection path and has vermagic
`7.2.0 SMP preempt mod_unload`.

### Phase 1 boot validation (2026-08-30)

The rebuilt generation booted successfully. Both `/run/current-system` and
`/run/booted-system` resolve to
`/nix/store/pbl7sd31khrlg8ak8fqgwk2dq2rxl174-nixos-system-nixos-26.11.20260826.9fbb54b`,
and the active module resolves to the expected
`79yjssydl0q1hfs4v9ggkfrsk7lmk9fl` store path. Kernel `7.2.0` bound the
synthetic `legion` device, selected the M1CN configuration, mapped EC RAM, and
created sysfs, hwmon, platform-profile, and WMI support successfully.

The post-boot read-only capture was in `low-power` on battery (`ACAD=0`):

| Attribute | Value |
|---|---:|
| `cpu_shortterm_powerlimit` | `54 W` |
| `cpu_longterm_powerlimit` | `54 W` |
| `cpu_peak_powerlimit` | `65 W` |
| `cpu_cross_loading_powerlimit` | `45 W` |
| `cpu_temperature_limit` | `100 C` |
| `gpu_ctgp_powerlimit` | `60 W` |
| `gpu_temperature_limit` | `87 C` |
| `gpu_power_target_offset` | `45 W` |

All eight values were identical across three passes two seconds apart.
`cpu_apu_sppt_powerlimit`, `cpu_l1_tau`, `cpu_default_powerlimit`,
`gpu_ctgp2_powerlimit`, `gpu_default_ppab_ctrgp_powerlimit`,
`gpu_ppab_powerlimit`, and `gpu_boost_clock` are hidden. The boot journal has no
`get_simple_wmi_attributewith raw value`, WMI evaluation, or power-write
rejection messages. Focused frontend power repository, bloc, state, and widget
tests pass (38 tests). The running frontend displayed the six supported fields
with the same live values (CPU 54/54/65/45 W, GPU 60 W/87 C) and correctly
disabled editing while on battery.

This completes read-path and visibility validation. This capture did not test
writes because the machine was on battery; the controlled AC test is recorded
below.

### Phase 1 controlled write validation (2026-08-30)

With AC connected (`ACAD=1`) and platform profile set to `custom`, the
frontend's authenticated `io.github.prnice.LegionControl1` D-Bus path was used
for a minimal CPU sustained-limit test:

1. Writing the existing `cpu_longterm_powerlimit` value (`54 W`) succeeded and
   read back `54 W` immediately and after ten seconds.
2. Writing `53 W` read back `53 W` immediately and after ten seconds.
3. The original `54 W` value was restored in a `finally` path and still read
   `54 W` after ten seconds.
4. The kernel journal contained no power-limit rejection, WMI evaluation, ACPI,
   or `legion_laptop` error from the test.
5. The platform profile was restored to its pre-test `balanced` state; PL1
   remained `54 W` and AC remained connected.

This proves the M1CN WMI3 SetFeatureValue path and read-back for one conservative
PL1 round trip. It does not establish model-safe ranges, validate the other
limits, test battery writes, or prove persistence across profile changes or
reboots. Keep the frontend's AC + Custom gate and do not expose Restore defaults
from this result.

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

The WMI3 read question is now answered (see firmware analysis and the Phase 0
capture): method 5 returns a DSDT constant until a curve is programmed, and the
DFAN curve area is zero on clean boots. Remaining steps:

1. Implement the M1CN curve reader by composition: query the `A7`/`SFTW` data
   block for the active mode's `FACT` (RPM palette, CPU temp thresholds, max
   speeds) and the step indices from method 5; expose per-point RPM and CPU
   temps with `fan*_max` from `CurrentFanMaxSpeed`. GPU/IC temp pairs and
   per-point accel/decel are mode-level firmware constants (`FINx`/`FNT0`),
   documented as such.
2. Curve writes through `Fan_Set_Table` with the correct M1CN payload: mode
   byte + ten step indices (each 0..10, ordered), validated before the call.
   After a write, verify the round-trip by reading back the step indices and
   the now-populated DFAN curve registers (CPU/GPU/IC temps, both fan RPM
   channels) through a read-only `DFAN` ioremap.
3. Keep the WMI3 `Fan_Get_Table` reader for the step indices only (debugfs).
4. Writes require Custom mode (firmware gates on `GZ44 == 3`) and AC power;
   enforce both in the driver, with read-before-write and read-after-write.
5. Enable frontend curve controls only after all ten points have credible,
   ordered temperatures, both fan channels, and repeatable round-trip behavior.

## Issue 2: zero power limits

### Initial evidence (before Phase 1)

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

Every frontend-consumed attribute in this initial capture read `0`. Kernel logs generated by
these reads repeatedly contain:

```text
legion_laptop: get_simple_wmi_attributewith raw value: 0
```

The Flutter repository requires positive values and filters every zero reading,
leaving no controls to render. See `PowerRepository.loadSnapshot` in
`lib/features/power/repository/power_repository.dart` and `effectiveMin` in
`lib/features/power/models/power_limit.dart`.

### Original driver path (before Phase 1)

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

Phase 1 selected WMI3, hid unsupported and legacy-only attributes, demoted the
per-read logging, and validated reads and one PL1 write round trip. The legacy
methods are stubs; the Other Method implements the real limits. Remaining work:

1. Validate model-safe ranges, PL1/PL2 coupling, other fields, and persistence
   across profile changes and reboots before expanding write support. Writes
   are firmware-gated to Custom mode (`GZ44 == 3`); retain frontend AC + Custom
   gating and verify driver enforcement of both prerequisites.
2. Keep any audit of the historical `ACCESS_METHOD_NO_ACCESS` legacy fallback
   separate; older model configurations need explicit migration before changing
   that fallback globally.
3. Resolve `lllf-zfg` separately: the DSDT lazy-init defaults (54/54/65 W CPU,
   20/60 W GPU, 100/87 C) plus the `A7`/`SFTW` per-mode tables are a credible
   model-specific default source; verify them against a second capture before
   building a restore action.

## Log amplification

Opening or polling the Power page reads multiple limit attributes. The original
driver logged `get_simple_wmi_attributewith raw value: 0` for each read, producing
large repeated kernel-log bursts. Phase 1 demoted this log to `pr_debug`; boot
validation confirmed the repeated messages were absent. Diagnostics should use `pr_debug`,
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
