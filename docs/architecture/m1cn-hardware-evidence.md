# Legion Slim 7 16APH8 hardware evidence

These observations apply to Lenovo `82Y4`, BIOS `M1CN48WW`, and the driver
revisions recorded below. They are not a support claim for other firmware or
models. Retained investigation reports are pinned in Git; temporary
DSDT/MMIO files from those investigations are no longer available.

## Driver binding and fan data

On Kernel 7.2.0, the old driver revision `c05ce26` did not probe because it
matched the physical ACPI EC already owned by `acpi-ec`. Upstream
[PR #423](https://github.com/johnfanv2/LenovoLegionLinux/pull/423) and
[PR #434](https://github.com/johnfanv2/LenovoLegionLinux/pull/434) introduced and
fixed the synthetic `legion` platform device. Leave `PNP0C09:00` bound to
`acpi-ec`; its ownership is not a reason to unbind it.

The corrected module bound successfully and exposed `legion_hwmon`. That did
not establish usable fan curves: the August 30 capture had ten points but
zero temperatures, zero second-fan PWM values, and unusable first-fan values.
The frontend's rejection of incomplete curves is intentional.

The retained DSDT analysis found that M1CN `Fan_Get_Table` returns step indices,
not percentages or temperatures. Before a curve is programmed it can return
the constant `1,2,3,4,5,6,7,8,8,8`. The A7/SFTW WMI data block supplies per-mode
RPM palettes and CPU temperature thresholds. DFAN MMIO at `0xFE0B0F00`
contained live power values but zero curve registers in the clean-boot capture.
Neither a bound module nor plausible-looking step indices prove writable
curve support. The older EC register layout also produced zero readings.

Sources: [binding evidence][binding], [firmware and fan captures][driver].

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
read back 54→53→54 W, including ten-second checks. This proves one round trip,
not safe ranges, other writes, persistence, or factory defaults. See
[power-defaults evidence](../power-defaults-evidence.md) for the unresolved
PPAB discrepancy and incomplete restore coverage.

## Graphics and sleep

The firmware combines `gsync` (an inverted historical Hybrid/MUX name) and
`igpumode`:

| Mode | `gsync` | `igpumode` | Meaning |
| --- | ---: | ---: | --- |
| Hybrid | 1 | 0 | dGPU available |
| Hybrid iGPU-only | 1 | 1 | requests live dGPU ejection |
| Hybrid Auto | 1 | 2 | AC-dependent attach/eject |
| Discrete | 0 | 0 | dGPU/MUX mode; reboot required |

Support values `2` and `3` are capability codes, not choice bitmasks. Mode
selection is distinct from settled PCI topology. Auto's delayed autonomous
ejection was observed and is not safe to expose as an ordinary frontend action.

The retained hardware results establish:

- Guarded internal-panel Plasma Wayland iGPU-only transition, suspend/resume,
  and live Hybrid rollback succeeded on August 31.
- Detached platform-mode hibernation failed during ACPI S4 preparation and
  reattached NVIDIA. Do not reuse that path as a validated configuration.
- Shutdown-mode image restoration, post-resume reconciliation, module cleanup,
  and policy-aware NVIDIA CDI handling succeeded in September. Desktop, audio,
  and Wi-Fi recovery were confirmed for the September 8 direct-hibernate cycle.
- A guarded systemd 261.2 suspend-then-hibernate manual-wake and timer-driven
  cycle passed on September 9. The 262 build/deployment checks on November 3
  did **not** establish equivalent hardware sleep coverage.
- MediaTek `mt7921e` restore timeouts and NVIDIA firmware-query assertions
  remained separate unresolved findings despite functional recovery.
- A detached poweroff stall did not recur after backend hardening; its precise
  cause remains unknown. See [poweroff diagnostics](poweroff-stall-investigation.md).

These results do not establish external-display, X11, BIOS-recovery, or newer
systemd sleep behavior. Use the current [next-boot graphics guide](next-boot-graphics.md)
for the implemented opt-in boot flow, not old live-transition session steps.
The [pinned graphics investigation][graphics] retains firmware selectors,
driver contracts, exact generations, timelines, and validation limits.

[binding]: https://github.com/Prn-Ice/LenovoLegionLinuxFrontend/blob/b83540b6c1ee81e820c479a51b12955ec23a66dc/docs/architecture/fan-controller-kernel-7-handoff.md
[driver]: https://github.com/Prn-Ice/LenovoLegionLinuxFrontend/blob/b83540b6c1ee81e820c479a51b12955ec23a66dc/docs/architecture/legion-driver-issues-handoff.md
[graphics]: https://github.com/Prn-Ice/LenovoLegionLinuxFrontend/blob/b83540b6c1ee81e820c479a51b12955ec23a66dc/docs/architecture/igpu-only-driver-handoff.md
