# Power defaults investigation

Investigation: 2026-11-04. Frontend task: `lllf-zfg`. Blocking backend work:
`lllf-dok` (tracked here; implementation belongs in LenovoLegionLinux).

## Current status

Lenovo capability-data records contain a separate `default_value`, keyed by
feature and power mode. Upstream LenovoLegionLinux exposes **CPU PL1 and PL2**
defaults, but a complete, verified preset is still missing for the app's controls.
Do not implement Restore defaults using current readings, slider ranges, or the
hard-coded display values. Restore behavior has not been verified.

### Backend work in progress

Backend branch `feature/power-defaults-contract`, commit `3a84dcd`, now exports
cached firmware rows through the read-only `power_defaults_v1` diagnostic
attribute. Lookup fixtures cover missing, unsupported, valid-zero and invalid
records. The branch is pushed but **not merged or installed**. The kernel build
has not been checked because matching headers were unavailable. A restore preset
still needs complete model data and a verified PPAB default. See that branch's
`doc/POWER_DEFAULTS.md` and `lllf-dok` for the contract and next checks.

## Sources and versions

- Frontend baseline map last changed in commit
  `2f2fc4b4c2fa786213fd6eb3db5969dbb9db5508` (`feat(power): show hardware limit
  baselines`). The current map is in
  `lib/features/power/repository/power_repository.dart:148-159`, and its exact
  product/BIOS gate is at `:343-351`. The map adds reference values to the
  display; it does not read defaults from the driver.
- Nearby backend, inspected without changes:
  `../LenovoLegionLinux`, HEAD
  `dec598335b9482c4b63ff02f34c1bc26d1d6cabc`. Local line references below refer to
  `kernel_module/legion-laptop.c` at that revision.
- Upstream backend main resolved through GitHub on the investigation date to
  `7f04d9dde1bb4c85cc4136f127ae6fc0296b10e0` (2026-10-30).
  [Pinned source][upstream-driver] provides the default attributes described below.
- Nearby LenovoLegionToolkit HEAD:
  `31d0db273535a6f12e1122e23d397cd840ac9b58`. Its WMI readers provide an
  independent implementation of explicit defaults, not proof that a particular
  machine supplies all those records.
- Historical local evidence:
  [firmware and boot evidence](https://github.com/Prn-Ice/LenovoLegionLinuxFrontend/blob/b83540b6c1ee81e820c479a51b12955ec23a66dc/docs/architecture/legion-driver-issues-handoff.md),
  especially lines 116-155 and 188-223, plus `lllf-zfg`'s 2026-08-30 comment.
  `/tmp/opencode/DSDT.dsl` and `/tmp/opencode/phase0/` are **absent** now. No
  matching DSDT/capture artifacts were found in the personal-projects tree.
  Only the earlier reports remain; the original files could not be rechecked.

## Available defaults by source and model

| Source / scope | Verified defaults | Remaining gap |
|---|---|---|
| Nearby backend WMI3 models | `struct capdata01` already contains `id`, `supported`, `default_value`, `step`, `min_value`, `max_value` (`:2543-2552`); probe caches available records (`:8328-8355`) | No complete userspace default export; cached data alone does not establish model coverage |
| Current upstream models supplying supported capability rows | `cpu_longterm_powerlimit_defaults` and `cpu_shortterm_powerlimit_defaults` export explicit per-mode defaults | Only two limits; each model must actually supply the relevant mode rows |
| Q7CN / Legion Pro 7 16IAX10H / 83F5 | Upstream documents measured per-mode PL1/PL2 defaults from capdata01 | Different hardware; not an M1CN preset and not complete coverage of this frontend's limits |
| 82Y4 / M1CN48WW | Historical DSDT lazy-init candidates and repeated current-value captures; exact-identity frontend baseline map | No retained raw capability/default records establishing a complete Custom preset; PPAB unresolved |
| Legacy CPU/GPU WMI models | Dedicated default getters exist in Toolkit; backend exposes legacy `cpu_default_powerlimit` and `gpu_default_ppab_ctrgp_powerlimit` | Partial, model-dependent legacy methods, not a complete named preset; historical M1CN legacy methods are stubs |
| Other model or BIOS revision | No complete model-specific preset established here | Remain unavailable until records are verified; do not broaden the 82Y4/M1CN48WW map |

The current upstream implementation at lines 8192-8211 and 9071-9148:

1. Selects a row by feature in bits 31..16, power mode in bits 15..8, sub-ID
   zero in bits 7..0, and supported bit 0.
2. Emits `profile:watts` entries from **`cd->default_value`**, not a current
   GetFeatureValue result or a range endpoint.
3. Skips absent mode rows and returns `-ENODATA` if none exist. Visibility is
   based on at least one matching row (`:9326-9337`), so an attribute's presence
   does not guarantee a Custom-mode default.

The upstream Q7CN evidence distinguishes custom WMI settings from limits
actually enforced in other modes; see [pinned feature documentation][upstream-features].

### Where to add backend support

The local driver already queries WMI data GUID
`7A8F5407-CB67-4D6E-B547-39B3BE018154` and retains `default_value`. Its
`clamped_value` (`:5754-5786`) uses feature/mode/support matching for bounds;
it does not export defaults. Reuse the newer upstream lookup/export approach
instead of adding a frontend model-value database. Do not assume the current
upstream model configuration is interchangeable with the local M1CN fixes:
upstream `model_m1cn` (`:1030-1061`) does not select the local explicit WMI3
power-limit access configuration.

`CPUDefaultPowerLimit` wraps `cpu_default_powerlimit` in Python. The driver's
attribute is read-only (`:5942-5951`) and delegates to one legacy method. The
similarly named GPU default attribute delegates to a legacy GPU method
(`:6213-6222`). Neither attribute provides a complete reset. No complete
defaults command/contract was found in the inspected local Python backend.

### How LenovoLegionToolkit reads defaults

LenovoLegionToolkit's [capability reader][toolkit-capability] reads
`LENOVO_CAPABILITY_DATA_01` properties `IDs`, `DefaultValue`, `MinValue`,
`MaxValue`, and `Step`. Its [V3 controller][toolkit-v3] keeps current values
separate from `DefaultValue` (`:250-285`) and selects mode-specific defaults
by adjusted capability ID (`:331-346`). In particular, the object named
`GetDefaultStateAsync` also reads current values. Do not treat all values
returned by this method as defaults.

The [legacy per-mode reader][toolkit-legacy] explicitly reads
`LENOVO_DEFAULT_VALUE_IN_DIFFERENT_MODE_DATA`, including separate CPU long/short,
peak, cross-load, APU, CPU-temperature and GPU default properties. Check whether
these firmware records exist on `82Y4/M1CN48WW` before using them.

## Recorded M1CN values

| Field | Reported lazy-init candidate | Preserved observed value |
|---|---:|---:|
| CPU short-term / `CSPL` | 54 W | 54 W |
| CPU long-term / `CLPL` | 54 W | 54 W |
| CPU peak / `CPPL` | 65 W | 65 W |
| CPU cross-load / `CCPL` | 45 W | 45 W |
| CPU temperature / `CCTL` | 100 C | 100 C |
| GPU cTGP / `GTGP` | 60 W | 60 W |
| GPU temperature / `GPTL` | 87 C | 87 C |
| GPU PPAB / power boost / `CGDB` | **20 W** | **0 W** |
| AC power-target offset / `TPPT` | No explicit initializer value quoted in the retained firmware-design section | 45 W |

Phase 0 recorded balanced mode on AC. The post-boot capture recorded low-power
on battery and eight readable fields across three passes. The second boot
comment confirms stable values but explicitly retains the PPAB discrepancy.
These captures show stable readings. The later controlled PL1 write and restore
demonstrated a 54→53→54 W round trip. They do not identify factory defaults.

The A7/SFTW fan table's `DefaultFanMaxSpeed` is a **fan** default; it supplies
no missing power-limit default. APU SPPT and CPU L1 tau were reported as
hard-zero unsupported firmware branches; that does not establish the same
semantics for PPAB.

## PPAB: known facts and open questions

### Confirmed in the backend

- Local `gpu_ppab_powerlimit_show` uses WMI3
  `OtherMethodFeature_GPU_POWER_BOOST`, ID `0x02010000` (`:2528`, `:6120-6136`).
  For this configuration it does not read the known-stub legacy GPU method.
- `legion_wmi3_power_limit_supported` (`:6599-6619`) hides a feature when its
  getter fails or returns zero. Only AC power-target offset is exempt. Thus a
  hidden PPAB file is consistent with the recorded zero, **not independent
  proof that firmware declares PPAB unsupported**.
- The earlier report's statement that captured power values "match the DSDT
  lazy-init defaults exactly" must be read narrowly: its own table includes
  `CGDB 0`, contradicting its later `CGDB 20 W` initializer claim. It cannot be
  used as evidence that PPAB matched.

### Still unknown

It is unclear why the reported 20 W initializer did not produce the observed
zero-valued MMIO/WMI result. Without the original DSDT branch conditions, feature
dispatch, raw capability records and capture ordering, this investigation cannot
distinguish an inactive initializer, different firmware state, wrong historical
mapping, or subsequent firmware updates to that register.

Do not use either 0 or 20 W as the PPAB restore default. Do not expose PPAB based
on the initializer alone or globally reinterpret all zero reads as unsupported.
A future restore design must explain how it handles missing PPAB data.

## Required work

`lllf-dok` blocks `lllf-zfg`. Required next work:

1. Recover or preserve exact-model firmware evidence with product, BIOS, table
   identity/hash and capability-row provenance. For M1CN, inspect the PPAB
   dispatch, initialization condition and declared support/default records.
   Some getters initialize firmware state. Inspect static tables or saved records
   first to avoid changing hardware during discovery.
2. Export explicit per-feature, per-mode defaults through a read-only backend
   contract, including unsupported/unavailable status, units and provenance.
   Extend the upstream PL1/PL2 mechanism rather than interpreting live values.
3. Establish coverage for every exposed field, with a clear distinction between
   read-only diagnostics and fields a restore would write. Disable restore when
   required defaults or Custom rows are missing, records are invalid, duplicate
   or truncated, the firmware is unknown, or PPAB remains unresolved.
4. Use support flags and ranges to determine whether zero is valid. Do not treat
   every zero as unsupported. Test missing and partial records, mode selection,
   valid zero, and model/BIOS mismatch with fixtures before frontend integration.
5. Once all required defaults are verified, add restore with confirmation, AC
   power and Custom-mode checks, the existing staged batch/rollback flow, and
   failure and recovery tests.

Also verify the sources for `_m1cn48wwHardwareDefaults`. Keep the hardware
defaults label only for entries backed by recoverable authoritative evidence.
Handle any app behavior change separately.

[upstream-driver]: https://github.com/johnfanv2/LenovoLegionLinux/blob/7f04d9dde1bb4c85cc4136f127ae6fc0296b10e0/kernel_module/legion-laptop.c
[upstream-features]: https://github.com/johnfanv2/LenovoLegionLinux/blob/7f04d9dde1bb4c85cc4136f127ae6fc0296b10e0/doc/FEATURES_AND_TESTING.md
[toolkit-capability]: https://github.com/LenovoLegionToolkit-Team/LenovoLegionToolkit/blob/31d0db273535a6f12e1122e23d397cd840ac9b58/LenovoLegionToolkit.Lib/System/Management/WMI.LenovoCapabilityData01.cs
[toolkit-v3]: https://github.com/LenovoLegionToolkit-Team/LenovoLegionToolkit/blob/31d0db273535a6f12e1122e23d397cd840ac9b58/LenovoLegionToolkit.Lib/Controllers/GodMode/GodModeControllerV3.cs
[toolkit-legacy]: https://github.com/LenovoLegionToolkit-Team/LenovoLegionToolkit/blob/31d0db273535a6f12e1122e23d397cd840ac9b58/LenovoLegionToolkit.Lib/System/Management/WMI.LenovoDefaultValueInDifferentModeData.cs
