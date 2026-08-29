# Fan controller on Kernel 7

## Status

The missing fan curve on the development machine has a confirmed backend root
cause. The machine is running a pre-Kernel-7 LenovoLegionLinux module on Kernel
7.2.0. The frontend must continue to render unavailable values until a corrected
module is deployed and its hwmon data can be read back.

Do not unbind `PNP0C09:00` from `acpi-ec`, write directly to EC/sysfs nodes, or
force-load another model configuration to work around this problem.

## Observed host

Captured on 2026-08-29:

| Item | Value |
|---|---|
| Product | Lenovo `82Y4`, Legion Slim 7 16APH8 |
| BIOS | `M1CN48WW` |
| Kernel | NixOS `7.2.0` |
| Module | `/run/booted-system/kernel-modules/lib/modules/7.2.0/kernel/drivers/platform/x86/legion-laptop.ko` |
| Module behavior | Logs only `legion_laptop: Loading legion_laptop`; no probe or loaded-device message |
| Module alias | Still exports `acpi*:PNP0C09:*` |
| EC owner | `/sys/bus/platform/devices/PNP0C09:00/driver` resolves to `acpi-ec` |
| Legion driver | No bound child under `/sys/module/legion_laptop/drivers/platform:legion/` |
| Other fan provider | `yogafan` exposes only `fan1_input`, observed as `0` |
| Missing controller data | No `fan1_max`, curve-point PWM/temperature files, or writable Legion controller hwmon |

`/sys/module/legion_laptop/refcnt` was `0`, but refcount is not a success test:
working versions can also report zero. A bound platform child, probe logs, and a
`legion_hwmon` provider are the useful criteria.

## Root cause

The active NixOS overlay at
`/home/prnice/Dotfiles/nixos-flaky-tests/hosts/nixos/hardware/legion_slim.nix`
fetches `Prn-Ice/LenovoLegionLinux` branch `read_file_fix`. That branch resolves
to `c05ce2676c6a457694cc1437b53356ee1e301969` from 2026-02-28.

Its driver still matches the physical `PNP0C09` ACPI EC. Kernel 7 binds that
device to the standard `acpi-ec` driver, so the old Legion platform driver's
probe is never called. This matches upstream issue
[#422](https://github.com/johnfanv2/LenovoLegionLinux/issues/422).

Upstream fixed this after the pinned revision:

- [PR #423](https://github.com/johnfanv2/LenovoLegionLinux/pull/423), merge
  `1570dba2c8c3079115439f43e50d2891813c38d9`, adapts the driver to Kernel 7.
- [PR #434](https://github.com/johnfanv2/LenovoLegionLinux/pull/434), merge
  `c52b4f293c4e8c00acf6bfba2bbd06b862cdf4a1`, restores ACPI access for the
  Kernel 7 virtual platform device.

The corrected driver leaves `PNP0C09:00` with `acpi-ec` and registers a private
synthetic platform device named `legion`. Its sysfs root is:

```text
/sys/module/legion_laptop/drivers/platform:legion/legion
```

The old root remains relevant on kernels before 7:

```text
/sys/module/legion_laptop/drivers/platform:legion/PNP0C09:00
```

The Flutter frontend runtime-discovers both roots, preferring the Kernel 7
layout. Current upstream Python chooses the same Kernel 7 root.

## Safe deployment work

The active NixOS worktree already contains user changes, including changes to
`legion_slim.nix`. Preserve and review those changes rather than replacing the
file wholesale.

1. Update the `Prn-Ice/LenovoLegionLinux` deployment revision to a tested fork
   commit that contains both upstream merge commits above and preserves any
   still-needed `read_file_fix` work.
2. Change the overlay from the mutable branch name to that immutable commit and
   update the `fetchFromGitHub` hash. Using `lib.fakeHash` for one evaluation is
   a safe way to obtain Nix's expected source hash.
3. Build a new NixOS generation. Do not test by stealing the live EC device from
   `acpi-ec`; boot the generation normally so module ordering and dependencies
   match production.
4. Reboot and perform the read-only checks below before exercising any write
   command from the frontend or `legion_cli`.

Pinning current official upstream directly is another option, but it must first
be checked against the fork's custom commits and the machine's existing NixOS
changes. At the time of diagnosis, official `main` was
`3893e203332d60effea688a3043abd86046997ad`.

## Reboot verification

Expected kernel log lines include a probe and successful device load, not only
the module-level `Loading legion_laptop` line:

```bash
journalctl -k -b --no-pager | rg -i 'legion|acpi.*ec'
```

Verify the synthetic platform child and hwmon provider exist:

```bash
ls -la /sys/module/legion_laptop/drivers/platform:legion/legion
ls -la /sys/module/legion_laptop/drivers/platform:legion/legion/hwmon
sensors
```

Read-only success criteria:

- `PNP0C09:00` remains bound to `acpi-ec`.
- The Legion driver has a child named `legion`.
- The log contains `legion_laptop platform driver probing` and
  `legion_laptop loaded for this device`.
- A `legion_hwmon` provider exposes nonzero `fan1_max`/`fan2_max` and the curve
  point files appropriate to M1CN's WMI3 implementation.
- The Flutter Fans page shows the controller-provided curve and any supported
  secondary controls without falling back to fabricated values.

Only after these checks pass should privileged preset or curve writes be tested.
If the module probes but M1CN data is still missing, capture the complete Legion
kernel log, `sensors`, the synthetic sysfs tree, and the readable debugfs fan
curve before changing model flags or ACPI paths.
