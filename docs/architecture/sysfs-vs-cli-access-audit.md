# Hardware reads and writes

**Original audit:** 2026-03-07. **Reviewed against code:** 2026-11-11.
**Scope:** Representative sysfs reads and privileged backend commands used by
feature repositories. This is not a complete sensor or D-Bus API inventory.

---

## Read and write methods

| Direction | Mechanism | Why |
|---|---|---|
| **Reads** | `LegionSysfsService` — direct file I/O | No privilege needed; avoids process spawn overhead |
| **Writes** | Typed `LegionControlClient` methods, usually queued through `LegionFrontendBridgeService` | The service authorizes requests and validates an allow-list before privileged backend commands |

---

## Reads (`LegionSysfsService`)

| Feature | Sysfs path | Notes |
|---|---|---|
| `platform_profile` | `/sys/firmware/acpi/platform_profile` | Current power profile |
| `platform_profile_choices` | `/sys/firmware/acpi/platform_profile_choices` | Available profiles |
| `hybrid_mode` | `.../PNP0C09:00/gsync` | null means no usable reading, not proof of unsupported hardware |
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
| `on_power_supply` | Discovered Mains-type supply's `online`; fallback to `ADP0/online` or `AC/online` | Read-only sensor |
| `lock_fan_controller` | `.../PNP0C09:00/lockfancontroller` | |
| `maximum_fan_speed` | `.../PNP0C09:00/fan_fullspeed` | |
| `mini_fan_curve` | `.../PNP0C09:00/hwmon/hwmon*/minifancurve` | Dynamic hwmon dir scan |
| `fan_curve` (10 points) | `.../hwmon/hwmon*/pwm{1,2,3}_auto_point{1-10}_{pwm,temp,temp_hyst,accel,decel}` | 100 point-file reads plus two fan maximums for a complete curve; invalid data ends the read early |
| `cpu_overclock` | `.../PNP0C09:00/cpu_oc` | |
| `gpu_overclock` | `.../PNP0C09:00/gpu_oc` | |
| `cpu_temperature_limit` | `.../legion/cpu_temperature_limit` | Read-only in the frontend until a validated CLI write contract exists |
| `gpu_power_target_offset` | `.../legion/gpu_power_target_offset` | Read-only in the frontend until a validated CLI write contract exists |

---

## Writes (`LegionControl1`)

Most repositories call typed `LegionControlClient` methods inside the bridge's
`runControlOperation` queue; Settings calls the client directly for services.
The root service validates each request and runs a
fixed backend command. The CLI vocabulary below describes that native backend
mapping, not repository inputs. The service transfers fan curves and boot logos as
bytes; custom fan curves no longer use a shared temporary frontend file.

### Named CLI commands

Used for features that have dedicated `enable/disable` subcommands in legion_cli:

| Feature | CLI args | Repository |
|---|---|---|
| `hybrid_mode` | `hybrid-mode-enable` / `hybrid-mode-disable` | dashboard |
| `battery_conservation` | `batteryconservation-enable/disable` | battery (shared with Dashboard) |
| `rapid_charging` | `rapid-charging-enable/disable` | battery (shared with Dashboard and Power) |
| `always_on_usb` | `always-on-usb-charging-enable/disable` | battery |
| `touchpad` | `touchpad-enable/disable` | devices |
| `fn_lock` | `fnlock-enable/disable` | devices |
| `mini_fan_curve` | `minifancurve-enable/disable` | fans |
| `lock_fan_controller` | `lockfancontroller-enable/disable` | fans |
| `maximum_fan_speed` | `maximumfanspeed-enable/disable` | fans |
| `fan_preset` | `fancurve-write-preset-to-hw <preset>` | fans |
| `fan_curve` (custom) | `fancurve-write-file-to-hw <path>` | fans |
| `fan_preset` (context) | `fancurve-write-current-preset-to-hw` | fans, dashboard |
| `boot_logo` | `boot-logo enable <path>` / `boot-logo restore` | boot_logo |

### `set-feature` commands

`set-feature <FeatureName> <value>` is used for features registered in
`Feature.features` in `legion.py` but without dedicated CLI subcommands:

| Feature | `featureName` string | Repository |
|---|---|---|
| `platform_profile` | `PlatformProfileFeature` | power, dashboard |
| `winkey` | `WinkeyFeature` | devices |
| `overdrive` | `OverdriveFeature` | display, dashboard |
| `y_logo_light` | `YLogoLight` | lighting |
| `io_port_light` | `IOPortLight` | lighting |
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
| `camera_power` | The frontend reads status only; its write allow-list has no camera control |
| `on_power_supply` | Sensor — AC state is not user-settable |
| `cpu_temperature_limit` | WMI3 reports the value, but Python has no writable feature and the plain WMI3 store path is not validated |
| `cpu_default_powerlimit` | Driver declares `DEVICE_ATTR_RO`; retained as a diagnostic reading, excluded from Dart and native write allow-lists |
| `gpu_power_target_offset` | WMI3 reports the value, but Python has no writable feature and the plain WMI3 store path is not validated |
| `white_kbd_backlight` | Not included in the privileged service allow-list until a validated backend contract exists |
| `dgpu` deactivation | Process killing and PCI restart are intentionally outside the privileged service allow-list |

The Power page shows recorded reference values only for an exact product and BIOS
match. The current table contains only Lenovo `82Y4` with BIOS `M1CN48WW`. See
the [power-defaults investigation](../power-defaults-evidence.md) for gaps in the
supporting evidence. The values are not verified factory defaults. Other systems
show `Reference` with `Unavailable`.

Graphics policy operations use the typed client from `dgpu`; service changes use
it from `settings`. Next-boot graphics requires installed integration. See
[graphics setup](next-boot-graphics.md) and [transport modes](portable-control.md)
for those contracts and their limits.

---

## Unused CLI commands

| Command | What it does | Relevance |
|---|---|---|
| `fancurve-write-hw-to-preset <preset>` | Saves current hardware fan curve to a named preset file | Could enable "Save current curve" feature |
| `fancurve-write-hw-to-file <file>` | Saves current hardware fan curve to a YAML file | Could enable export/backup |
| `monitor [--period N]` | Polls hardware state periodically, outputs JSON | Alternative polling source; the frontend currently refreshes through its own readers |
| `autocomplete-install` | Installs shell tab completion | Tooling only |
| `custom-conservation-mode-apply <lower> <upper>` | Sets custom charge thresholds | The typed API retains it, but no feature repository currently calls it |

---

## Maintenance notes

1. Feature names passed to `set-feature` must exactly match the Python class
   names in `legion.py`. Link each name to its backend definition.
2. The frontend refreshes through its own readers. A move to `legion_cli monitor`
   would need a separate behavior and performance review.
3. A complete fan curve reads two fan maximums and 100 point files
   (10 points × 10 files), in addition to provider discovery. Invalid data can
   end the read early.
4. `CPUDefaultPowerLimit` is read-only in the frontend and rejected by both
   write allow-lists (`lllf-9g8`), matching the driver's `DEVICE_ATTR_RO`.
   See the [backend evidence](../power-defaults-evidence.md#where-to-add-backend-support).

---

## Adding a feature

- For reads, add to `LegionSysfsService`.
- For writes, document accepted values and ranges, payload limits, and backend
  arguments. Add the typed D-Bus method or allow-list entry, then update Dart and
  C++ tests.
