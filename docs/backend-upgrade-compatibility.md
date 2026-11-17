# Backend upgrade compatibility

This review compares upstream LenovoLegionLinux `3893e20..9853156` with fork
merge `baafe12ccb4bea628aecccfb0e53309fa9c6be00`. The target laptop is Lenovo
82Y4 (Legion Slim 7 16APH8), BIOS M1CN48WW. Beads `lllf-qaf` holds the detailed
checklist and linked follow-ups.

Source support, fixture tests, and hardware validation are separate evidence.
The upgraded backend has been built, but its module has not been activated as
part of this work.

## Compatibility changes

- Fan tables can contain speed levels without temperatures, ramps, or a second
  independent curve. Read the driver's units and supported fields. A readable
  table does not establish that writes are validated or that the table describes
  the current physical fan state.
- M1CN's old mini-curve and controller-lock bytes are invalid. Hide those
  controls when the backend omits them; keep valid controls on other models.
- Fan presets and curve edits must respect the backend's write qualification.
  Keep live telemetry available when editing is blocked.
- WMI3 power writes can be clamped to firmware bounds. Compare the requested
  value with readback and preserve the requested draft when they differ.
- Generic CLI exit codes 2 and 3 mean unavailable and feature not found.
  Graphics commands use those codes for blocked and pending. Classify them in
  their command context and retain the backend's error details.

Implementation work is tracked in `lllf-o1w` (fans), `lllf-hjj` (power), and
`lllf-qkv` (command outcomes).

Implemented changes also include optional third-fan telemetry (`lllf-9eq`) and
charging-setting readback after success or partial failure (`lllf-i14`). Power
batch failures attempt rollback and verify the restored values. Missing or
clamped readback preserves pending edits and reports the failure.

For level tables, `pwm1_auto_pointN_pwm` still uses the hwmon 0–255 scale.
In `baafe12`, `fancurve_get_speed_pwm` exports `level * 255 / 10`, while the
setter rounds `pwm * 10 / 255` to the nearest level. The frontend must decode
that value before looking up an RPM. `fan1_level_rpm_table` and
`fan2_level_rpm_table` are whitespace-separated arrays whose first entry is
level 1. Level 0 means fan stop. An absent ladder cannot justify a guessed
linear RPM conversion.

The app retains its full-schema editor. In the reviewed backend, all models
with the unvalidated-write guard expose speed-only tables, which this app
displays read-only. This is an app compatibility decision, not a declaration
that every other laptop has passed hardware validation. The kernel remains
responsible for authorizing and validating writes.

## Additional features found in the second pass

These are upstream features across several laptop families, not a list of new
M1CN capabilities. `lllf-3mc` tracks qualification of the controls and alternate
providers below.

| Upstream change | Frontend action and affected sections |
| --- | --- |
| Third fan RPM on Q7CN (`994ba05`) | Add optional `fan3` readings through `LegionSysfsService`, live snapshots, sensor history/CSV, Dashboard, Fans, Analytics, and diagnostics. Track implementation in `lllf-9eq`; hide absent readings rather than inventing a third fan. |
| Validated `fan_unlock`, including Y530 live readback (`39509f6`) | Qualify the readback contract before adding a Fans control, typed selector, and native command mapping. This lifts a firmware fan ceiling on supported models; it is distinct from locking the controller. |
| Instant Boot on AC/USB-PD (`ad22bdd`) | Add separate capability-driven device controls for `instant_boot_ac` and `instant_boot_usb_pd` after tracing their typed write/readback paths. Neither is always-on USB charging. Cover partial support. |
| GameZone ownership by mainline Lenovo drivers | `PowerRepository.loadSnapshot` currently searches Legion roots. Qualify explicit `lenovo-wmi-other` firmware-attribute discovery and writes for supported models; missing Legion attributes do not prove missing hardware capability. |
| Opt-in `legiond` CPU power-limit sync and combined-load targets (`f3440de`, `eab9cea`) | Distinguish WMI settings from enforced MMIO RAPL limits in Power-page details. Qualify daemon configuration and the documented thermald conflict before showing controller status or adding configuration. |
| Charging-mode interaction (`6bffee4`, `a6c3134`) | Refresh both charging settings after writes and partial failures. Verify requested-state readback in BatteryBloc; track in `lllf-i14`. |
| Unsupported panel overdrive hidden (`482dda7`) | Existing Display/Settings nullable support detection hides the control. Add regression coverage for absent attributes and retain unreadable-attribute diagnostics. |
| Fn+R refresh-rate event (`ceea2b0`) | DisplayBloc currently observes changes through polling. Test eventual refresh; do not describe this as immediate input-event handling. |
| Variable fan-table size (`89479da`) | Include active point-count parsing in the fan capability work. The backend's ability to resize a table does not imply that the frontend offers point insertion/removal. |

Enabling conservation first disables rapid charging when the backend can read
that it is enabled. A failed disable aborts conservation; an unreadable rapid
state does not. Enabling rapid charging clears conservation in firmware.
Disabling conservation leaves rapid charging alone. Frontend tests should read
these outcomes rather than simulate them by issuing a second hardware command.

The second pass found no further proven duplicate fork implementation.

## Local fixes retained or retired

| Local change | Result of the upstream comparison |
| --- | --- |
| `159e376`: GPU-temperature WMI3 routing | Upstream provides the equivalent route. The merge already removed the duplicate branch. |
| Logging portion of `dd09704` | Upstream removes the raw-value log. The merge already omitted the obsolete local log change. |
| Initial WMI event guard in `13dd1bf` | Partly overlaps upstream. Retain the local early return and post-delay lifetime check, along with graphics transactions. |
| Remaining M1CN power access and Custom-only guard | Still required; upstream does not replace them. |
| WMI setter return-buffer handling | Still distinct. Allocating a result buffer does not prove that firmware applied a write. |
| Lazy CLI diagnostic logging | Still distinct; upstream eagerly reads `dmesg`. |
| Graphics state, reconciliation, and detach lifecycle | Still distinct. Other models' GPU selectors do not replace this laptop's checked transaction contract. |

Retire duplicate implementations, not entire historical commits that also
contain needed behavior. The full seven-commit matrix remains in `lllf-qaf`.

## Hardware and firmware blockers

- `lllf-5kk`: activate the upgraded system separately and verify probe, sensors,
  controls, graphics, and sleep behavior on the laptop.
- `lllf-dok`: establish complete firmware-default provenance and resolve the
  M1CN PPAB discrepancy. New per-mode CPU PL1/PL2 defaults are partial evidence,
  not a complete factory-restore contract.
- `lllf-cqn.8`: qualify the fan table against actual hardware state. Historical
  captures can contain firmware initializer data rather than the programmed
  curve. Preserve the kernel's unvalidated-write guard.
- `lllf-70v`: fix upstream package license metadata and source-GUI interpreter
  compatibility through the normal packaging workflow.

Keep the recorded Power-page reference readings labelled as references. Do not
use another model's defaults, fabricate missing fan data, or enable a kernel
safety override to make an integration test pass.

## Verification

The implementation passed these hardware-free checks:

- `flutter analyze --no-pub`: no issues.
- `flutter test --no-pub`: 911 passed; 28 opt-in tests skipped.
- `flutter build linux --release --no-pub`: release bundle built.
- Native CTest suite: nine passed.
- Nix `control-lifecycle` check: disposable VM passed, including command-scoped
  exits and authorization/lifetime checks.
- `tool/test_linux_journeys.sh` under Xvfb: 18 app journeys plus both restart
  stages passed. The fan journeys cover full-curve preset readback and blocked
  writes for a speed-only table.
- Fans/Power visual fixture run: eight passed. Light/dark captures at 1280×900
  and 420×500 were inspected, including scroll-end views and Power references.
  Narrow fan tables scroll horizontally to reach the final RPM column.

Fixtures exercise frontend behavior without changing hardware. They do not
establish firmware acceptance, live RPM accuracy, or factory defaults. Preset
content equality and broader write confirmation remain in `lllf-6p0`; the new
fan save check compares the edited full curve with readback.
