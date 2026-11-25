# Legion Slim 7 16APH8 hardware evidence

Tested hardware: Lenovo `82Y4`, BIOS `M1CN48WW`, with the driver revisions listed
below. The linked reports are preserved in Git. Their temporary DSDT and MMIO
files are no longer available.

## Driver binding and fan data

On Kernel 7.2.0, the old driver revision `c05ce26` did not probe because it
matched the physical ACPI EC already owned by `acpi-ec`. Upstream
[PR #423](https://github.com/johnfanv2/LenovoLegionLinux/pull/423) and
[PR #434](https://github.com/johnfanv2/LenovoLegionLinux/pull/434) introduced and
fixed the synthetic `legion` platform device. Leave `PNP0C09:00` bound to
`acpi-ec`; its ownership is not a reason to unbind it.

The corrected module exposed `legion_hwmon`, but its fan-curve readings were
unusable: the August 30 capture had ten points but zero temperatures, zero
second-fan PWM values, and unusable first-fan values.
The frontend intentionally rejects incomplete curves.

The retained DSDT analysis found that M1CN `Fan_Get_Table` returns step indices,
not percentages or temperatures. Before a curve is programmed it can return
the constant `1,2,3,4,5,6,7,8,8,8`. The A7/SFTW WMI data block supplies per-mode
RPM palettes and CPU temperature thresholds. DFAN MMIO at `0xFE0B0F00`
contained live power values but zero curve registers in the clean-boot capture.
The older EC register layout also produced zero readings.

Sources: [binding evidence][binding], [firmware and fan captures][driver].

On 2026-11-19, we verified the activated Kernel `7.3.4` NixOS system
(`/nix/store/zgwziy9hdw079hhhccw04v4kr9ik80q0-nixos-system-nixos-26.11.20261117.0490633`)
with `lenovo-legion-module-0.1.8-unstable-2026-11-17` (fork merge
`baafe12ccb4bea628aecccfb0e53309fa9c6be00`, including upstream `9853156`,
`1570dba`, `c52b4f2`, and `5deb227`) and `legion_cli` from
`lenovo-legion-app-0.1.8-unstable-2026-11-17`:

- **Bindings and probe logs**: `PNP0C09:00` stayed bound to `acpi-ec`, and the
  synthetic `legion` platform device bound to `legion` (`legion_laptop`). Kernel
  boot logs confirmed `M1CN`, EC ID `0x5507`, a successful probe, and 10-level
  `0..4700` RPM fan tables for both fans.
- **Speed-only level curve**: `LegionSysfsService.readFanCurve()` returned a
  10-point `speedOnly` / `level` curve (`writeStatus: unsupported`,
  `canEdit: false`). Raw `pwm1_auto_point1..10_pwm` values
  `[25, 51, 76, 102, 127, 153, 178, 204, 204, 204]` decoded to levels
  `1, 2, 3, 4, 5, 6, 7, 8, 8, 8` and mapped to nominal RPMs
  `0, 1800, 1900, 2100, 2400, 2800, 2900, 3600, 3600, 3600` using the `0..4700`
  `fan1_level_rpm_table` and `fan2_level_rpm_table` ladders.
- **Retired and readable fan controls**: `minifancurve` and
  `lockfancontroller` do not exist in sysfs and exit `2` through `legion_cli`.
  `fan_fullspeed` reads `0`.
- **Initializer caveat**: `1,2,3,4,5,6,7,8,8,8` matches the firmware `CFST`
  initializer before any custom curve write. Keep `fancurve_write_unvalidated`
  intact and never enable `allow_unvalidated_fancurve` in tests.

## Power limits

Legacy CPU/GPU WMI getters were stubs on this firmware. Driver revision
`f4849cd` selected WMI3 power access, hid unsupported attributes, and rejected
writes outside Custom mode. The August 30 boot capture repeatedly read:

| Field | Observed value |
| --- | ---: |
| CPU short-term / long-term | 54 / 54 W |
| CPU peak / cross-load | 65 / 45 W |
| CPU temperature limit | 100 °C |
| GPU cTGP / temperature limit | 60 W / 87 °C |
| AC power-target offset | 45 W |

A controlled AC + Custom-mode PL1 write through the authenticated D-Bus path
read back 54→53→54 W, including ten-second checks. We tested only this write
and restore. Safe ranges, other fields, persistence, and factory defaults remain
unverified. See [power-defaults evidence](../power-defaults-evidence.md) for the unresolved
PPAB discrepancy and incomplete restore coverage.

In the 2026-11-19 Kernel `7.3.4` (`baafe12`) read-only check in `low-power` on
battery, all eight previously observed limits matched, `gpu_ppab_powerlimit`
now reported `20` W, `rapidcharge` read `0`, and two per-mode CPU default
attributes appeared:

- `cpu_longterm_powerlimit_defaults`: `low-power:45 balanced:54 performance:75 max-power:80 custom:54`
- `cpu_shortterm_powerlimit_defaults`: `low-power:50 balanced:54 performance:100 max-power:100 custom:54`

Complete factory-default provenance and the historical PPAB discrepancy remain
open in `lllf-dok` and [power-defaults evidence](../power-defaults-evidence.md).

## Graphics and sleep

The firmware combines `gsync` (an inverted historical Hybrid/MUX name) and
`igpumode`:

| Mode | `gsync` | `igpumode` | Meaning |
| --- | ---: | ---: | --- |
| Hybrid | 1 | 0 | dGPU available |
| Hybrid iGPU-only | 1 | 1 | requests live dGPU ejection |
| Hybrid Auto | 1 | 2 | AC-dependent attach/eject |
| Discrete | 0 | 0 | dGPU/MUX mode; reboot required |

Support values `2` and `3` are capability codes, not bitmasks. Check the actual
PCI devices after selecting a mode. Auto triggered delayed autonomous ejection
and is unsafe to expose as an ordinary frontend action.

Hardware test results:

- Guarded internal-panel Plasma Wayland iGPU-only transition, suspend/resume,
  and live Hybrid rollback succeeded on August 31.
- Detached platform-mode hibernation failed during ACPI S4 preparation and
  reattached NVIDIA. Do not reuse that path as a validated configuration.
- Shutdown-mode image restoration, post-resume reconciliation, module cleanup,
  and policy-aware NVIDIA CDI handling succeeded in September. The September 8
  direct-hibernate cycle confirmed desktop, audio, and Wi-Fi recovery.
- A guarded systemd 261.2 suspend-then-hibernate manual-wake and timer-driven
  cycle passed on September 9. We did not repeat controlled sleep tests with
  systemd 262 on November 3.
- MediaTek `mt7921e` restore timeouts and NVIDIA firmware-query assertions
  remained separate unresolved findings despite functional recovery.
- A detached poweroff stall did not recur after backend hardening; its precise
  cause remains unknown. See [poweroff diagnostics](poweroff-stall-investigation.md).

Not tested: external displays, X11, BIOS recovery, and sleep with newer systemd
versions. The [archived boot guide](https://github.com/Prn-Ice/LenovoLegionLinuxFrontend/blob/6171f46/docs/architecture/next-boot-graphics.md) describes the integration used in these tests.
The [pinned graphics investigation][graphics] retains firmware selectors,
driver contracts, exact generations, timelines, and validation limits.

[binding]: https://github.com/Prn-Ice/LenovoLegionLinuxFrontend/blob/b83540b6c1ee81e820c479a51b12955ec23a66dc/docs/architecture/fan-controller-kernel-7-handoff.md
[driver]: https://github.com/Prn-Ice/LenovoLegionLinuxFrontend/blob/b83540b6c1ee81e820c479a51b12955ec23a66dc/docs/architecture/legion-driver-issues-handoff.md
[graphics]: https://github.com/Prn-Ice/LenovoLegionLinuxFrontend/blob/b83540b6c1ee81e820c479a51b12955ec23a66dc/docs/architecture/igpu-only-driver-handoff.md
