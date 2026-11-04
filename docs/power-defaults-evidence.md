# Authoritative power defaults: firmware evidence

Investigation: 2026-11-04. Frontend task: `lllf-zfg`. Blocking backend work:
`lllf-dok` (tracked here; implementation belongs in LenovoLegionLinux).

## Decision

There is a concrete firmware source for defaults: Lenovo capability-data records
contain a separate `default_value`, keyed by feature and power mode. Current
upstream LenovoLegionLinux exports these for **CPU PL1 and PL2**, but neither the
nearby backend nor the evidence retained for 82Y4/M1CN48WW supplies a verified,
complete preset for every exposed limit. Do not implement Restore defaults from
live readings, slider ranges, or the existing hard-coded frontend baseline map.

This is not a claim that firmware defaults are unavailable on all models. It is
a distinction between an implemented source, actual model/BIOS records, and a
complete frontend restore contract. No model gains complete restore eligibility
from this investigation alone.

### Subsequent staged backend implementation

Backend branch `feature/power-defaults-contract`, commit `3a84dcd`, now exports
cached firmware rows through the read-only `power_defaults_v1` diagnostic
attribute. Lookup fixtures cover missing, unsupported, valid-zero and invalid
records. The branch is pushed separately and is **not merged or deployed**.
Kernel compilation remains unverified because matching headers were unavailable;
exact-model coverage and PPAB provenance still block a restore preset. See that
branch's `doc/POWER_DEFAULTS.md` and `lllf-dok` for the contract and next checks.

## Evidence versions and scope

- Frontend baseline map last changed in commit
  `2f2fc4b4c2fa786213fd6eb3db5969dbb9db5508` (`feat(power): show hardware limit
  baselines`). The current map is in
  `lib/features/power/repository/power_repository.dart:148-159`, and its exact
  product/BIOS gate is at `:343-351`. It annotates displayed readings; it is not
  a backend defaults discovery API.
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
  Those prior analyses are retained reports, not raw bytes rechecked today.

## What exists for each source/model class

| Source / scope | Authoritative default availability | Remaining gap |
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
This further rules out treating stable current settings as factory defaults.
No daemon, power-mode transition, or hardware command from those docs was run.

### Existing backend integration point

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
(`:6213-6222`). Neither name promises a complete multi-field reset. No complete
defaults command/contract was found in the inspected local Python backend.

### Independent upstream firmware contract

LenovoLegionToolkit's [capability reader][toolkit-capability] reads
`LENOVO_CAPABILITY_DATA_01` properties `IDs`, `DefaultValue`, `MinValue`,
`MaxValue`, and `Step`. Its [V3 controller][toolkit-v3] keeps current values
separate from `DefaultValue` (`:250-285`) and selects mode-specific defaults
by adjusted capability ID (`:331-346`). In particular, the object named
`GetDefaultStateAsync` also reads current values; its name alone is not evidence
that all its values are defaults.

The [legacy per-mode reader][toolkit-legacy] explicitly reads
`LENOVO_DEFAULT_VALUE_IN_DIFFERENT_MODE_DATA`, including separate CPU long/short,
peak, cross-load, APU, CPU-temperature and GPU default properties. This is
another firmware-interface lead, not a universal constant database. Neither
Toolkit implementation establishes that these records exist on 82Y4/M1CN48WW.

## M1CN historical observations, without promoting them to a preset

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
Repeated observations verify read stability, not factory-reset semantics.
The later controlled PL1 write/restore demonstrated a 54→53→54 W round trip,
not an authoritative defaults query.

The A7/SFTW fan table's `DefaultFanMaxSpeed` is a **fan** default; it supplies
no missing power-limit default. APU SPPT and CPU L1 tau were reported as
hard-zero unsupported firmware branches; that does not establish the same
semantics for PPAB.

## PPAB: what is resolved and what remains bounded

**Resolved at the backend mapping/visibility level:**

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

**Not resolved at the firmware level:** why the reported 20 W initializer did
not produce the observed zero-valued MMIO/WMI result. Without the original
DSDT branch conditions, feature dispatch, raw capability records and capture
ordering, this investigation cannot distinguish an inactive initializer,
different firmware state, wrong historical mapping, or subsequent firmware
updates to that register. These are possibilities to discriminate, not findings.

Neither 0 nor 20 W is approved as a restore default. Do not expose PPAB based
on the initializer alone or globally reinterpret all zero reads as unsupported.
Its exclusion must be explicit in a future completeness decision. Existing
visibility stays unchanged in this documentation-only investigation.

## Backend blocker and completion criteria

`lllf-dok` blocks `lllf-zfg`. Required next work:

1. Recover or preserve exact-model firmware evidence with product, BIOS, table
   identity/hash and capability-row provenance. For M1CN, inspect the PPAB
   dispatch, initialization condition and declared support/default records.
   A getter with lazy initialization is not automatically side-effect-free;
   prefer static table/captured record analysis during read-only discovery.
2. Export explicit per-feature, per-mode defaults through a read-only backend
   contract, including unsupported/unavailable status, units and provenance.
   Extend the upstream PL1/PL2 mechanism rather than interpreting live values.
3. Establish coverage for every exposed field, with a clear distinction between
   read-only diagnostics and fields a restore would write. Do not let a partial
   map silently imply complete coverage. Missing Custom rows, unknown firmware,
   invalid/duplicate/truncated records and unresolved PPAB must fail closed.
4. Verify zero semantics from capability support and ranges rather than value
   truthiness. Test missing and partial records, mode selection, valid zero,
   and model/BIOS mismatch with fixtures before any frontend integration.
5. Only after complete authoritative coverage exists, implement the confirmed,
   AC/Custom-gated restore using the existing staged batch/rollback path and
   meaningful failure/recovery tests.

The existing `_m1cn48wwHardwareDefaults` display map also needs a provenance
review under this blocker: retain it only with recoverable authoritative evidence,
or stop labeling unverified entries as hardware defaults in a separately
approved production change. This investigation does not authorize that edit.

## Evidence limits

This analysis compares code, retained reports, and pinned upstream source.
Original firmware bytes, actual per-model capability rows, complete defaults
coverage, and restore behavior remain unverified. The historical live-value
captures do not replace an authoritative defaults query.

[upstream-driver]: https://github.com/johnfanv2/LenovoLegionLinux/blob/7f04d9dde1bb4c85cc4136f127ae6fc0296b10e0/kernel_module/legion-laptop.c
[upstream-features]: https://github.com/johnfanv2/LenovoLegionLinux/blob/7f04d9dde1bb4c85cc4136f127ae6fc0296b10e0/doc/FEATURES_AND_TESTING.md
[toolkit-capability]: https://github.com/LenovoLegionToolkit-Team/LenovoLegionToolkit/blob/31d0db273535a6f12e1122e23d397cd840ac9b58/LenovoLegionToolkit.Lib/System/Management/WMI.LenovoCapabilityData01.cs
[toolkit-v3]: https://github.com/LenovoLegionToolkit-Team/LenovoLegionToolkit/blob/31d0db273535a6f12e1122e23d397cd840ac9b58/LenovoLegionToolkit.Lib/Controllers/GodMode/GodModeControllerV3.cs
[toolkit-legacy]: https://github.com/LenovoLegionToolkit-Team/LenovoLegionToolkit/blob/31d0db273535a6f12e1122e23d397cd840ac9b58/LenovoLegionToolkit.Lib/System/Management/WMI.LenovoDefaultValueInDifferentModeData.cs
