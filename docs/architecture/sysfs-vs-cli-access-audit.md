# sysfs vs legion_cli Access Audit

**Date:** 2026-03-07
**Scope:** `LegionSysfsService` (direct sysfs reads) vs `LegionFrontendBridgeService` (pkexec → legion_cli writes) across all feature repositories.

---

## Access Strategy

The frontend uses a consistent, principled split:

| Direction | Mechanism | Why |
|---|---|---|
| **Reads** | `LegionSysfsService` — direct file I/O | No privilege needed; avoids process spawn overhead |
| **Writes** | `LegionFrontendBridgeService` → `pkexec legion_cli` | Kernel module writes require root; CLI handles all validation |

This is correct and should be maintained.

---

## Read Surface (`LegionSysfsService`)

| Feature | Sysfs path | Notes |
|---|---|---|
| `platform_profile` | `/sys/firmware/acpi/platform_profile` | Current power profile |
| `platform_profile_choices` | `/sys/firmware/acpi/platform_profile_choices` | Available profiles |
| `hybrid_mode` | `.../PNP0C09:00/gsync` | null = not supported on this model |
| `overdrive` | `.../PNP0C09:00/overdrive` | Display overdrive |
| `battery_conservation` | `.../ideapad_acpi/VPC2004:00/conservation_mode` | ideapad driver |
| `rapid_charging` | `.../PNP0C09:00/rapidcharge` | |
| `always_on_usb` | `.../ideapad_acpi/VPC2004:00/usb_charging` | |
| `touchpad` | `.../ideapad_acpi/.../touchpad` or `.../PNP0C09:00/touchpad` | First non-null wins |
| `winkey` | `.../PNP0C09:00/winkey` | |
| `camera_power` | `.../ideapad_acpi/VPC2004:00/camera_power` | Read-only — see below |
| `fn_lock` | `.../ideapad_acpi/VPC2004:00/fn_lock` | |
| `white_kbd_backlight` | `/sys/class/leds/platform::kbd_backlight/brightness` | `> 0` → enabled |
| `y_logo_light` | `/sys/class/leds/platform::ylogo/brightness` | |
| `io_port_light` | `/sys/class/leds/platform::ioport/brightness` | |
| `on_power_supply` | `/sys/class/power_supply/ADP0/online` or `AC/online` | Read-only sensor |
| `lock_fan_controller` | `.../PNP0C09:00/lockfancontroller` | |
| `maximum_fan_speed` | `.../PNP0C09:00/fan_fullspeed` | |
| `mini_fan_curve` | `.../PNP0C09:00/hwmon/hwmon*/minifancurve` | Dynamic hwmon dir scan |
| `fan_curve` (10 points) | `.../hwmon/hwmon*/pwm{1,2,3}_auto_point{1-10}_{pwm,temp,temp_hyst,accel,decel}` | 100 reads per load |
| `cpu_overclock` | `.../PNP0C09:00/cpu_oc` | |
| `gpu_overclock` | `.../PNP0C09:00/gpu_oc` | |

---

## Write Surface (`pkexec legion_cli`)

Two strategies are in use. Both are correct — which to use depends on CLI surface.

### Strategy A: Named subcommands

Used for features that have dedicated `enable/disable` subcommands in legion_cli:

| Feature | CLI args | Repository |
|---|---|---|
| `hybrid_mode` | `hybrid-mode-enable` / `hybrid-mode-disable` | display_lighting |
| `battery_conservation` | `batteryconservation-enable/disable` | battery_devices, dashboard |
| `rapid_charging` | `rapid-charging-enable/disable` | battery_devices, dashboard, automation |
| `always_on_usb` | `always-on-usb-charging-enable/disable` | battery_devices |
| `touchpad` | `touchpad-enable/disable` | battery_devices |
| `fn_lock` | `fnlock-enable/disable` | battery_devices |
| `mini_fan_curve` | `minifancurve-enable/disable` | fans |
| `lock_fan_controller` | `lockfancontroller-enable/disable` | fans |
| `maximum_fan_speed` | `maximumfanspeed-enable/disable` | fans |
| `fan_preset` | `fancurve-write-preset-to-hw <preset>` | fans |
| `fan_curve` (custom) | `fancurve-write-file-to-hw <path>` | fans |
| `fan_preset` (context) | `fancurve-write-current-preset-to-hw` | fans, automation, dashboard |
| `conservation` (custom) | `custom-conservation-mode-apply <lower> <upper>` | automation |
| `boot_logo` | `boot-logo enable <path>` / `boot-logo restore` | boot_logo |

### Strategy B: Generic `set-feature <FeatureName> <value>`

Used for features registered in `Feature.features` in `legion.py` but without dedicated CLI subcommands:

| Feature | `featureName` string | Repository |
|---|---|---|
| `platform_profile` | `PlatformProfileFeature` | power |
| `winkey` | `WinkeyFeature` | battery_devices |
| `overdrive` | `OverdriveFeature` | display_lighting |
| `white_kbd_backlight` | `WhiteKeyboardBacklightFeature` | display_lighting |
| `y_logo_light` | `YLogoLight` | display_lighting |
| `io_port_light` | `IOPortLight` | display_lighting |
| `cpu_overclock` | `CPUOverclock` | power |
| `gpu_overclock` | `GPUOverclock` | power |
| CPU longterm power | `CPULongtermPowerLimit` | power |
| CPU shortterm power | `CPUShorttermPowerLimit` | power |
| CPU peak power | `CPUPeakPowerLimit` | power |
| CPU cross loading | `CPUCrossLoadingPowerLimit` | power |
| CPU APU SPPT | `CPUAPUSPPTPowerLimit` | power |
| CPU default | `CPUDefaultPowerLimit` | power |
| GPU CTGP | `GPUCTGPPowerLimit` | power |
| GPU PPAB | `GPUPPABPowerLimit` | power |
| GPU boost clock | `GPUBoostClock` | power |
| GPU temperature limit | `GPUTemperatureLimit` | power |

---

## Read-Only Features (no write path — by design)

| Feature | Reason |
|---|---|
| `camera_power` | CLI only exposes `camera-power status`; write not supported by driver on most models |
| `on_power_supply` | Sensor — AC state is not user-settable |

---

## CLI Commands Available But Unused by Frontend

| Command | What it does | Relevance |
|---|---|---|
| `fancurve-write-hw-to-preset <preset>` | Saves current hardware fan curve to a named preset file | Could enable "Save current curve" feature |
| `fancurve-write-hw-to-file <file>` | Saves current hardware fan curve to a YAML file | Could enable export/backup |
| `monitor [--period N]` | Polls hardware state periodically, outputs JSON | **Directly relevant to `okf.18` reactive refresh** |
| `autocomplete-install` | Installs shell tab completion | Tooling only |

---

## Findings

### ✅ What's working well

1. **Read/write separation is clean and consistent.** Every read is sysfs-direct; every write is pkexec-gated. No reads go through pkexec, no writes go through sysfs. This is the right design.

2. **Dual write strategy is intentional, not accidental.** Named subcommands exist for the features most commonly toggled. `set-feature` is the generic escape hatch for the full Feature registry. Both routes are stable.

3. **Fan curve read goes direct to sysfs** (not via `fancurve-write-hw-to-file`). This avoids spawning a privileged process just to read state, and is the correct approach.

4. **No coverage gaps in features that are exposed in the UI.** Every UI control has a matching sysfs read path and a CLI write path.

### ⚠️ Items to note

1. **`set-feature` `featureName` strings are magic constants.** They must match Python `Feature` subclass names in `legion.py` exactly. They are hardcoded in the Dart repositories (e.g. `'CPULongtermPowerLimit'`). If a Python feature is renamed, the Dart side silently breaks. Consider adding a comment linking to the Python source for each.

2. **`monitor` command is a significant unused capability.** The CLI's `monitor` command polls all hardware state on a configurable interval and outputs structured JSON. This is the natural backend for `okf.18` (reactive refresh for external state changes) — e.g. detecting when another tool changes the power profile externally. Worth investigating as part of that task.

3. **Fan curve: 100 sysfs reads per load cycle.** 10 points × 10 files each. This is fine in practice (sysfs reads are fast) but worth noting. The CLI's `fancurve-write-hw-to-file` + read could reduce this to one process call if latency ever becomes an issue.

---

## Recommendation: Access Strategy Going Forward

**No changes to the existing strategy are needed.** Continue with:

- **New read-only features:** Add to `LegionSysfsService`.
- **New writable features with a named CLI subcommand:** Use named subcommand form in the repository.
- **New writable features without a named subcommand:** Use `set-feature <FeatureName> <value>` and document the Python class name in a comment.
- **Reactive state changes (okf.18):** Investigate `monitor` command as the notification source.
