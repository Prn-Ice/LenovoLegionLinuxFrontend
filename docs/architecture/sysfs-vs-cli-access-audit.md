# Hardware reads and writes

**Date:** 2026-03-07
**Scope:** `LegionSysfsService` (direct sysfs reads) vs `LegionFrontendBridgeService` (`LegionControl1` writes) across all feature repositories.

---

## Read and write methods

| Direction | Mechanism | Why |
|---|---|---|
| **Reads** | `LegionSysfsService` — direct file I/O | No privilege needed; avoids process spawn overhead |
| **Writes** | `LegionFrontendBridgeService` → typed `LegionControl1` D-Bus methods | Kernel writes require root; both client and service validate a narrow allow-list |

---

## Reads (`LegionSysfsService`)

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
| `cpu_temperature_limit` | `.../legion/cpu_temperature_limit` | Read-only in the frontend until a validated CLI write contract exists |
| `gpu_power_target_offset` | `.../legion/gpu_power_target_offset` | Read-only in the frontend until a validated CLI write contract exists |

---

## Writes (`LegionControl1`)

Repositories call typed `LegionControlClient` methods inside the bridge's
`runControlOperation` queue. The root service validates each request and runs a
fixed backend command. The CLI vocabulary below describes that native backend
mapping, not repository inputs. Fan curves and boot logos are transferred as
bytes; custom fan curves no longer use a shared temporary frontend file.

### Named CLI commands

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

### `set-feature` commands

`set-feature <FeatureName> <value>` is used for features registered in
`Feature.features` in `legion.py` but without dedicated CLI subcommands:

| Feature | `featureName` string | Repository |
|---|---|---|
| `platform_profile` | `PlatformProfileFeature` | power |
| `winkey` | `WinkeyFeature` | battery_devices |
| `overdrive` | `OverdriveFeature` | display_lighting |
| `y_logo_light` | `YLogoLight` | display_lighting |
| `io_port_light` | `IOPortLight` | display_lighting |
| `cpu_overclock` | `CPUOverclock` | power |
| `gpu_overclock` | `GPUOverclock` | power |
| CPU longterm power | `CPULongtermPowerLimit` | power |
| CPU shortterm power | `CPUShorttermPowerLimit` | power |
| CPU peak power | `CPUPeakPowerLimit` | power |
| CPU cross loading | `CPUCrossLoadingPowerLimit` | power |
| CPU APU SPPT | `CPUAPUSPPTPowerLimit` | power |
| GPU CTGP | `GPUCTGPPowerLimit` | power |
| GPU PPAB | `GPUPPABPowerLimit` | power |
| GPU boost clock | `GPUBoostClock` | power |
| GPU temperature limit | `GPUTemperatureLimit` | power |

---

## Read-only features

| Feature | Reason |
|---|---|
| `camera_power` | CLI only exposes `camera-power status`; write not supported by driver on most models |
| `on_power_supply` | Sensor — AC state is not user-settable |
| `cpu_temperature_limit` | WMI3 reports the value, but Python has no writable feature and the plain WMI3 store path is not validated |
| `cpu_default_powerlimit` | Driver declares `DEVICE_ATTR_RO`; retained as a diagnostic reading, excluded from Dart and native write allow-lists |
| `gpu_power_target_offset` | WMI3 reports the value, but Python has no writable feature and the plain WMI3 store path is not validated |
| `white_kbd_backlight` | Not included in the privileged service allow-list until a validated backend contract exists |
| `dgpu` deactivation | Process killing and PCI restart are intentionally outside the privileged service allow-list |

The Power page shows reference defaults only for an exact product and BIOS
match. The current table contains only Lenovo `82Y4` with BIOS `M1CN48WW`. See
the [power-defaults investigation](../power-defaults-evidence.md) for gaps in the
supporting evidence. Other systems show `Hardware default unavailable`.

---

## Unused CLI commands

| Command | What it does | Relevance |
|---|---|---|
| `fancurve-write-hw-to-preset <preset>` | Saves current hardware fan curve to a named preset file | Could enable "Save current curve" feature |
| `fancurve-write-hw-to-file <file>` | Saves current hardware fan curve to a YAML file | Could enable export/backup |
| `monitor [--period N]` | Polls hardware state periodically, outputs JSON | **Directly relevant to `okf.18` reactive refresh** |
| `autocomplete-install` | Installs shell tab completion | Tooling only |

---

## Maintenance notes

1. Feature names passed to `set-feature` must exactly match the Python class
   names in `legion.py`. Link each name to its backend definition.
2. Consider `legion_cli monitor` for detecting changes made by other tools. It
   polls hardware state and returns JSON. Tracked in `okf.18`.
3. Fan curves require 100 sysfs reads per load: 10 points × 10 files each.
4. `CPUDefaultPowerLimit` is read-only in the frontend and rejected by both
   write allow-lists (`lllf-9g8`), matching the driver's `DEVICE_ATTR_RO`.
   See the [backend evidence](../power-defaults-evidence.md#where-to-add-backend-support).

---

## Adding a feature

- For reads, add to `LegionSysfsService`.
- For writes, document accepted values and ranges, payload limits, and backend
  arguments. Add the typed D-Bus method or allow-list entry, then update Dart and
  C++ tests.
