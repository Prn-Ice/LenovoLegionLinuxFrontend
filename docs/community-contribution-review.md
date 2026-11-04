# Community contribution review

Source review, 4 November 2026. Tracking issue: `lllf-5at`.

## Summary

The project has useful foundations: feature-based directories, injectable services,
hardware-free fan fixtures, and a narrow privileged control API. Most UI labels
are already plain. The main barriers to community contributions are scattered
hardware assumptions, maintainer-specific setup, stale documentation, and error
handling that loses useful information.

Writing style cannot establish whether code was AI-generated. The useful question
is whether an owner can understand a failure and make a small, verifiable change.

## Priorities

### 1. Make the project straightforward to build and contribute to

- No project-level license was found in tracked files. The tracked skill license
  does not license the application. Confirm the intended license and attribution
  for imported code, including the OpenRGB-derived map in
  `lib/features/lighting/services/spectrum_led_map.dart:1`. (`lllf-0ev`)
- `.envrc:1` and `CONTRIBUTING.md:13` use the maintainer's private shared-flake
  path. Provide a portable development setup and explain the native dependencies
  and service installation for other Linux distributions. (`lllf-2re`)
- Separate building/testing from installing the driver and changing hardware.
  Document GitHub issues and pull requests as the public contribution route;
  contributors should not need agent tools to report a model or submit a fix.
- Add a short “support my Legion” guide and a tested-model table. Record model,
  BIOS, kernel/module/backend versions, tested features, and known gaps. A model
  name alone is not evidence that every feature works.

### 2. Make hardware discovery explainable and testable

`lib/core/services/legion_sysfs_service.dart` already discovers batteries by type
and accepts some test roots. Extend that approach:

- Discover platform and LED devices instead of relying on the exact paths at
  lines 10–13 and 47–62.
- Identify a fan provider before using its readings. The fallback at lines
  677–699 currently accepts the first readable `fanN_input` from any provider.
- Preserve the difference between absent, unreadable, malformed, and unsupported.
  `_readTrimmedFile` at line 810 turns file errors into null; feature repositories
  such as `devices_repository.dart:26` infer support from a non-null value.
- Distinguish readable state from writable capability. A sysfs value does not
  prove the installed control service/backend can change it.
- Extend the existing Diagnostics export with BIOS, selected source paths,
  capability results and failure reasons. Its current payload at
  `lib/features/diagnostics/view/diagnostics_page.dart:255` lacks those details.

Use small sanitized sysfs/proc fixtures so another contributor can reproduce the
same discovery result without owning the laptop. Track this in `lllf-j3e`.

### 3. Put genuine model differences in small data definitions

The power repository embeds defaults for exactly `82Y4` / `M1CN48WW` at
`lib/features/power/repository/power_repository.dart:148` and 343. Keep that exact
evidence boundary, but move the data out of feature behavior as variants grow.
Existing power-default work remains in `lllf-dok` and `lllf-zfg`.

Native RGB defaults to USB ID `048d:c987` in `spectrum_hid_service.dart:25`.
Its LED map, physical layout and brightness calibration live separately in
`spectrum_led_map.dart`, `view/keyboard_layout.dart` and
`repository/spectrum_rgb_repository.dart:11`. Group each verified keyboard's
identity, protocol, layout and calibration into an explicit definition.

Prefer runtime discovery. Use model/BIOS matches for real quirks, and keep unknown
hardware unknown. A general plugin framework would add more work than it saves
here. Track the data extraction in `lllf-5x6`.

Changes to firmware access, backend commands or driver support belong in the
appropriate backend/upstream project. A frontend profile cannot supply missing
kernel support. Privileged operations should retain their typed API and server
validation.

## Code that needs simplification

**Error translation is the clearest unnecessary complexity.** Repositories build
CLI-shaped arguments, the bridge passes them to `LegionControlClient.runCommand`,
and that client converts them to typed D-Bus calls. Failures then become feature
exception strings in `lib/core/data/privileged_repository.dart:43`. The UI
reconstructs error types by matching English sentences in
`lib/core/widgets/app_shell_components.dart:337`. Editing copy can therefore
change recovery behavior. Use typed operations and preserve structured failures
through to the UI; retain useful queue/history behavior. (`lllf-ifw`)

**Repeated polling code has inconsistent completion semantics.** In
`lib/features/devices/bloc/devices_bloc.dart:115`, an action awaits `_reloadState`
and records success. That helper can return without reading at line 127 or catch
a read failure at line 156. Display has the same pattern. Initialization also
starts a timer after an awaited read, while close only cancels an existing timer.
Prove these cases with controlled-completion tests and adopt a small consistent
pattern. A generic base Bloc is unnecessary. (`lllf-o80`)

**Some UI implementation is duplicated.** Settings and the standalone boot-logo
page each contain `_StatusRow`, `_FilePickerRow`, and pick/apply/restore handlers.
Share the boot-logo section. Lighting's 1,163-line page mixes editor composition,
effect-engine coordination and many controls; separate cohesive responsibilities
as they are maintained. File length alone is not a defect. (`lllf-1fv`)

**Some tests provide little evidence.**
`test/core/services/legion_sysfs_service_extended_test.dart:68` and subsequent
smoke checks read the host and accept null or the method's declared return type.
They cannot establish correct readings on another model. The temporary trees in
`legion_sysfs_service_fan_discovery_test.dart` are a better example. CI also
installs an always-successful CLI stub and omits the native test suite. Replace
host-dependent checks with fixtures and add native CI. (`lllf-m6m`)

## Copy and documentation

There is more repetitive technical explanation than marketing fluff. Keep short
labels such as “Power”, “Fans”, “Apply curve” and “Copy details”. Examples to trim:

| Current | Suggested |
| --- | --- |
| “Writing the complete custom fan curve requires privileged access and may prompt for authentication.” | “Apply this fan curve? You may be asked to authenticate.” |
| “Enable or disable Linux service dependencies used by Legion tooling.” | “Manage Legion services.” |
| “Backend Capability Probes” | “Hardware support checks” |
| “legion-control is a narrowly scoped system service that applies supported hardware changes after Polkit authorizes this app.” | “legion-control applies hardware settings after authentication.” |

Keep consequences such as lost work, increased heat, or a required reboot. Put
installation details behind an appropriate help/details section. Update the
feedback standard with any agreed presentation changes, and fix string-based
error classification before changing its recognition text. (`lllf-1fv`)

The architecture guide needs factual cleanup: `docs/architecture/overview.md:9`
says there is no hardware code despite the native HID implementation; its file
map names old feature directories; line 312 says there are no widget tests.
Its mandatory six-layer description also conflicts with the newer guidance to
add only useful layers. One short, accurate guide is better than overlapping
instructions. (`lllf-2re`)

## A useful contribution workflow

1. Export diagnostics and identify whether the missing support is in the driver,
   CLI/control service, frontend discovery, or keyboard mapping.
2. Add a small fixture from the affected machine and reproduce the mismatch.
3. Change the discovery rule or verified model data at that boundary.
4. Run the affected tests and confirm the result on the owner's hardware.
5. Submit the fixture, fix and tested-model entry together.

## Verification

Reviewed source, contributor documentation, CI configuration and representative
tests. Follow-ups are linked to `lllf-5at`. This was a source review: no application
behavior changed, and no tests, rendered UI review or real-hardware checks were
run. The polling findings need the reproduction tests described in `lllf-o80`.
