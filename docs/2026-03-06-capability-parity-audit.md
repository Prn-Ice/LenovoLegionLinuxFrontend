# Capability Parity Audit — Flutter Frontend vs LLL Backend

**Date:** 2026-03-06
**Bead:** LenovoLegionLinux-okf.16
**Sources verified:**

- `LLT_LLL_knowledge_center.md` (starting point)
- `LenovoLegionToolkit/LenovoLegionToolkit.WPF/CLI/Features/FeatureRegistry.cs` (LLT source)
- `LenovoLegionToolkit/LenovoLegionToolkit.WPF/Controls/Automation/Steps/` (LLT automation steps — 43 files)
- `LenovoLegionToolkit/LenovoLegionToolkit.Lib.Automation/Pipeline/Triggers/` (LLT triggers — 33 files)
- `LenovoLegionLinux/python/legion_linux/legion_linux/legion.py` (LLL backend feature classes)
- `LenovoLegionLinux/python/legion_linux/legion_linux/legion_cli.py` (LLL CLI surface)
- `LenovoLegionLinux/python/legion_linux/legion_linux/legion_gui.py` (LLL GUI wiring)
- `frontend/legion_frontend/lib/` (Flutter frontend code)

---

## Audit Method

Each capability was verified directly against source files, not documentation alone.
Status values used:

| Status | Meaning |
| --- |---|
| `frontend:implemented` | Read and write fully wired end-to-end |
| `frontend:partial` | Wired but with known gaps or limitations |
| `frontend:read-only` | State displayed; writes intentionally blocked or CLI-unsupported |
| `frontend:missing` | Backend exists; no frontend wiring |
| `backend-blocked` | Frontend placeholder exists; backend write not implemented |
| `out-of-scope` | Linux backend does not and likely cannot support this |

---

## Power

| capability_id | lll_backend | cli_surface | frontend_status | page | notes |
| --- |---| --- |---| --- |---|
| power_mode_switching | `PlatformProfileFeature` (legion.py:502) | `set-feature PlatformProfileFeature` | `frontend:implemented` | Power | Reads `platform_profile` + choices via sysfs; writes via bridge. Dashboard also has choice-chip bar. |
| gpu_and_cpu_power_limits | `CPUShorttermPowerLimit`, `CPULongtermPowerLimit`, `CPUPeakPowerLimit`, `CPUCrossLoadingPowerLimit`, `CPUAPUSPPTPowerLimit`, `GPUCTGPPowerLimit`, `GPUPPABPowerLimit` (legion.py:569-610) | `set-feature <FeatureName>` | `frontend:partial` | Power | 7 limits wired in `power_repository.dart`. **Missing: `CPUDefaultPowerLimit` (legion.py:589) and `GPUTemperatureLimit` (legion.py:615)** — both in LLL GUI but absent from Flutter's `allPowerLimits` list. |
| always_on_usb_toggle | `AlwaysOnUSBChargingFeature` (legion.py:487); write path raises `NotImplementedError` | CLI has `always-on-usb-charging-enable/disable` but backend unimplemented | `backend-blocked` | Battery & Devices | Read displayed with "read-only" subtitle; write gated by `_alwaysOnUsbWriteSupported = false`. Unblock once upstream fixes write path. |

---

## Fans

| capability_id | lll_backend | cli_surface | frontend_status | page | notes |
| --- |---| --- |---| --- |---|
| custom_fan_curve_control | `FanCurveIO` (legion.py:736), preset files in hwmon | `fancurve-write-preset-to-hw <name>`, `fancurve-write-file-to-hw <file>` | `frontend:partial` | Fans | Named presets applied. No graphical curve point editor (temp/RPM pairs). Users cannot define custom curves in the UI. |
| fan_curve_all_modes | `FanCurveRepository` (legion.py:1090), 8 context presets | `fancurve-write-current-preset-to-hw` | `frontend:partial` | Fans | All 8 context presets selectable and applicable. No per-profile custom curve editing. |
| mini_fan_curve_toggle | `FanCurveIO.set_minifancuve` via hwmon (legion.py:928) | `minifancurve-enable/disable` | `frontend:implemented` | Fans | |
| lock_fan_controller | `LockFanController` (legion.py:420) | `lockfancontroller-enable/disable` | `frontend:implemented` | Fans | |
| max_fan_speed_toggle | `MaximumFanSpeedFeature` (legion.py:497) | `maximumfanspeed-enable/disable` | `frontend:implemented` | Fans | |

---

## GPU

| capability_id | llt_source | lll_backend | cli_surface | frontend_status | notes |
| --- |---| --- |---| --- |---|
| gpu_overclock_toggle | `GPUOverclockController.cs`, `OverclockDiscreteGPUAutomationStep.cs` | `GPUOverclock` (legion.py:564); wired in legion_gui.py:668 | `set-feature GPUOverclock 0/1` | `frontend:missing` | Both sides have this. LLL GUI exposes via checkbox. No Flutter page or section. |
| cpu_overclock_toggle | Not in LLT FeatureRegistry | `CPUOverclock` (legion.py:559); wired in legion_gui.py:665 | `set-feature CPUOverclock 0/1` | `frontend:missing` | **Not in knowledge center.** LLL-only feature. LLL GUI exposes it. |
| gpu_boost_clock | Not found in LLT features | `GPUBoostClock` (legion.py:600) | `set-feature GPUBoostClock <value>` | `frontend:missing` | **Not in knowledge center.** LLL backend + GUI exist. IntFileFeature. |
| gpu_temperature_limit | Not in LLT FeatureRegistry directly | `GPUTemperatureLimit` (legion.py:615); GUI spinbox at legion_gui.py:692 | `set-feature GPUTemperatureLimit <value>` | `frontend:missing` | **Not in knowledge center as a separate entry.** LLL GUI exposes as spinbox. Not in Flutter's `allPowerLimits` list. |
| dgpu_runtime_monitoring | `GPUController.cs:60` | `NVIDIAGPUIsRunning` (legion.py:630) | No dedicated CLI | `frontend:missing` | Backend monitoring primitive exists. Display-only; suitable for About/diagnostics. |
| dgpu_deactivate_workflow | `DeactivateGPUAutomationStep.cs` (two modes: KillApps via NVAPI process enumeration + `process.Kill`; RestartGPU via `pnputil /restart-device <PnP-ID>`) | No LLL backend class, but Linux equivalents exist: `nvidia-smi` for process kill, sysfs PCI `/sys/bus/pci/devices/<addr>/remove` + `/sys/bus/pci/rescan` for device restart | `nvidia-smi`, sysfs write (privileged) | `frontend:missing` | Linux workaround is viable. Needs runtime PCI address discovery for the dGPU. Two privileged actions: kill GPU processes, then restart PCI device. |

---

## Display

| capability_id | llt_source | lll_backend | cli_surface | frontend_status | notes |
| --- |---| --- |---| --- |---|
| hybrid_gsync_toggle | `GSyncFeature.cs`, `HybridModeFeature.cs` | `GsyncFeature` (legion.py:482) | `hybrid-mode-enable/disable` | `frontend:implemented` | Display & Lighting. Reboot notice shown. |
| overdrive_toggle | `OverDriveFeature.cs` | `OverdriveFeature` (legion.py:477) | `set-feature OverdriveFeature 0/1` | `frontend:implemented` | Display & Lighting. |
| refresh_rate_switching | `RefreshRateFeature.cs` (uses `WindowsDisplayAPI` to enumerate `GetPossibleSettings()` and call `SetSettingsUsingPathInfo`) | No LLL backend class, but Linux equivalents exist: `xrandr` on X11, `gnome-monitor-config` / `kscreen-doctor` on Wayland | `xrandr --output <name> --rate <hz>` (no root needed) | `frontend:missing` | Reclassified as feasible. Rate query and apply do not require polkit. Main challenge is detecting the built-in display output name cross-environment (X11 vs Wayland). |
| resolution_switching | `ResolutionFeature.cs` | No equivalent | — | `out-of-scope` | Windows-only. |
| hdr_toggle | `HDRFeature.cs` | No equivalent | — | `out-of-scope` | Windows-only. |

---

## Lighting

| capability_id | llt_source | lll_backend | cli_surface | frontend_status | notes |
| --- |---| --- |---| --- |---|
| white_keyboard_backlight | `OneLevelWhiteKeyboardBacklightFeature.cs`, `WhiteKeyboardBacklightFeature.cs` (FeatureRegistry:20,38) | Confirmed in LLL (README:759) | `set-feature` | `frontend:missing` | LLL backend confirmed. No Flutter section. Low-effort toggle. |
| ylogo_ioport_lighting | `PanelLogoBacklightFeature.cs`, `PortsBacklightFeature.cs` | `YLogoLight` (legion.py:620), `IOPortLight` (legion.py:625) | `set-feature YLogoLight 0/1`, `set-feature IOPortLight 0/1` | `frontend:missing` | Both backend classes confirmed directly in source. No Flutter section. Low-effort. |
| spectrum_per_key_rgb_builtin | LLT Spectrum RGB | No in-tree LLL support | — | `out-of-scope` | LLL delegates to external `L5P-Keyboard-RGB`. |
| four_zone_rgb_builtin | LLT 4-zone | No in-tree LLL support | — | `out-of-scope` | Same: external project. |
| openrgb_integration | N/A (LLT-specific Spectrum/4-zone) | No LLL backend; OpenRGB is a separate open-source tool | `openrgb --device <n> --mode static --color RRGGBB`, `openrgb --list-devices` (no root needed) | `frontend:missing` | OpenRGB supports per-device RGB control via CLI or SDK socket (port 6742). Feasible as an optional integration: detect if installed, list devices, send color/mode commands. Not part of legion_cli — treated as optional external tool. |

---

## Input

| capability_id | llt_source | lll_backend | cli_surface | frontend_status | notes |
| --- |---| --- |---| --- |---|
| fn_lock | `FnLockFeature.cs`, FeatureRegistry:15, `FnLockControl` (Dashboard) | `FnLockFeature` (legion.py:456); wired in legion_gui.py:626; tray at legion_gui.py:770 | `fn-lock-enable/disable` | `frontend:missing` | **Not in knowledge center.** Both sides confirmed. LLL CLI surface exists. Low-effort toggle addition to Battery & Devices input section. |
| winkey_toggle | `WinKeyFeature.cs` (FeatureRegistry:37) | `WinkeyFeature` (legion.py:461) | `set-feature WinkeyFeature 0/1` | `frontend:implemented` | Battery & Devices. |
| touchpad_toggle | `TouchpadLockFeature.cs` (FeatureRegistry:36) | `TouchpadFeature` (legion.py:466) | `touchpad-enable/disable` | `frontend:implemented` | Battery & Devices. |
| camera_power_control | Notification-only in LLT | `CameraPowerFeature` (legion.py:472) | CLI read-only — `CameraPowerFeatureCommand` has `command_status` only, no `command_enable`/`command_disable` | `frontend:read-only` | Status displayed. Write correctly blocked: CLI does not expose a write path for this feature. |

---

## Audio

| capability_id | llt_source | lll_backend | frontend_status | notes |
| --- |---| --- |---| --- |
| microphone_speaker_toggle | `MicrophoneFeature.cs`, `SpeakerFeature.cs` | No equivalent | `out-of-scope` | No LLL integrated audio controls. |
| speaker_volume_automation | `SpeakerVolumeAutomationStep.cs` | No equivalent | `out-of-scope` | |

---

## Automation

| capability_id | llt_source | lll_backend | frontend_status | notes |
| --- |---| --- |---| --- |
| automation_engine_rich_triggers | 19 concrete trigger types + And/Or compound triggers (33 trigger files total): AC connect/disconnect, device connect/disconnect, display on/off, external display, games running/stop, GodMode preset changed, HDR on/off, hybrid mode, lid open/close, low-wattage AC, on-resume, on-startup, periodic, power mode, processes running/stop, session lock/unlock, time, user inactivity, WiFi connect/disconnect | `legiond` daemon: power/profile events + timer/socket | `frontend:partial` | Automation page exposes profile-change + power-source-change triggers only. LLT has 19+ trigger types. |
| run_external_program_step | `RunAutomationStep.cs` | `legiond.ini` config hooks | `frontend:missing` | Automation runner handles fan/battery/charging policies but has no "run shell command" action type. |
| persistent_background_service | Intentionally no background service | `LenovoLegionLaptopSupportService` (legion.py:731) | `frontend:implemented` | Settings page manages systemd service via polkit. |

---

## System

| capability_id | lll_backend | frontend_status | notes |
| --- |---| --- |---|
| boot_logo_customization | `legion_cli.py:434`, `legion.py:1530` | `frontend:missing` | CLI surface confirmed. No Flutter UI. High effort (file picker, validation, preflight). |
| boot_logo_preflight_validation | `legion.py:1497,1536` | `frontend:missing` | Blocked by above. |
| os_standard_interfaces | sysfs/hwmon/debugfs via kernel module | `frontend:implemented` (implicit) | The sysfs service reads from the kernel module interface directly. |
| update_and_warranty_checks | No LLL equivalent | `out-of-scope` | LLT-specific online flow. |

---

## LLT-Only Features (confirmed out of scope for Linux)

The following appear in LLT source but have no LLL backend equivalent:

`flip_to_start` (UEFI boot feature), `battery_night_charge` (Windows battery mgmt), `instant_boot` (UEFI), `dpi_scale` (Windows DPI), `its_mode` (WMI Intelligent Thermal Solution), `turn_off_monitors_step`, `resolution_switching`, `hdr_toggle`, `microphone_speaker_toggle`, `speaker_volume_automation`, `spectrum_per_key_rgb_builtin`, `four_zone_rgb_builtin`, `update_and_warranty_checks`, `vendor_software_disabler`, `macro_step`, `floating_gadget`, `play_sound_step`.

Note: `refresh_rate_switching` and `dgpu_deactivate_workflow` were previously listed here but are reclassified as feasible via Linux workarounds — see Display and GPU tables above.

---

## Knowledge Center Gaps Found

The following were found in source but are absent from or inaccurate in `LLT_LLL_knowledge_center.md`:

| gap | finding |
| --- |---|
| `fn_lock` entirely missing from KC | Both LLT (FeatureRegistry:15) and LLL (legion.py:456, legion_gui.py:626, legion_cli.py fn-lock subcommand) implement fn-lock. Not in KC at all. |
| `cpu_overclock_toggle` missing from KC | LLL has `CPUOverclock` (legion.py:559) and GUI wiring. No LLT FeatureRegistry entry. Not in KC. |
| `gpu_boost_clock` missing from KC | LLL has `GPUBoostClock` (legion.py:600) and GUI. Not in KC. |
| `GPUTemperatureLimit` not split from power limits in KC | LLL GUI exposes it as a distinct spinbox (legion_gui.py:692). Flutter's `allPowerLimits` omits it. |
| `CPUDefaultPowerLimit` missing from Flutter | `CPUDefaultPowerLimit` (legion.py:589) is absent from `power_repository.dart:allPowerLimits`. |
| LLT trigger count understated | KC lists ~7 trigger families. LLT source has 33 trigger files including And/Or compound triggers. |
| LLT automation step count understated | KC references a handful of steps. LLT source has 43 automation step control files. |
| camera-power CLI write confirmed absent | KC says LLL has "feature class + GUI wiring" (correct) but `CameraPowerFeatureCommand` only has `command_status`, no enable/disable. Frontend read-only treatment is accurate. |

---

## Recommended Next Steps (Priority Order)

### P0 — Low effort, direct backend support, established pattern

1. **fn_lock toggle** — `Battery & Devices → Input Devices`. CLI: `fn-lock-enable/disable`. Sysfs: `IDEAPAD_SYS_BASEPATH/fn_lock`. — **bead: LenovoLegionLinux-p03**
1. **Lighting controls** — Add "Lighting" section to Display & Lighting: white keyboard backlight toggle + Y-logo + IO-port light toggles. All use `set-feature`. — **bead: LenovoLegionLinux-9cn**
1. **Missing power limits** — Add `CPUDefaultPowerLimit` (legion.py:589) and `GPUTemperatureLimit` (legion.py:615) to `power_repository.dart:allPowerLimits`. Two-line addition following existing spec pattern. — **bead: LenovoLegionLinux-abl**

### P1 — Medium effort, meaningful parity

1. **GPU/CPU overclocking section** — New section covering `GPUOverclock`, `CPUOverclock` (bool toggles), `GPUBoostClock`, and `GPUTemperatureLimit` as grouped integer controls. All use `set-feature`. Requires sysfs path discovery for read state. — **bead: LenovoLegionLinux-5fr**
1. **Refresh rate switching** — Query available rates via `xrandr --query` (or Wayland equivalent); apply via `xrandr --output <name> --rate <hz>`. No polkit needed. Main challenge: detect built-in display output name across X11/Wayland. — **bead: LenovoLegionLinux-4cq**
1. **Fan curve editor** — Custom temp/RPM point editor widget. Largest UX gap vs LLT. Requires a new graphical curve widget and CLI surface for writing custom curve files. — **bead: LenovoLegionLinux-s21**

### P2 — Lower priority

1. **OpenRGB integration** — Optional external tool integration. Detect if OpenRGB is installed, list devices, send color/mode commands via CLI (`openrgb --list-devices`, `openrgb --device <n> --mode static --color RRGGBB`). No root required. Graceful fallback if not installed. — **bead: LenovoLegionLinux-80r**
1. **dGPU deactivate workflow** — Two privileged actions via Linux equivalents: (a) kill GPU processes via `nvidia-smi` query + kill; (b) restart PCI device via sysfs `remove`/`rescan`. Requires runtime PCI address discovery for the dGPU. — **bead: LenovoLegionLinux-6ad**
1. **dGPU runtime monitoring** — Display NVIDIA GPU active state (processes using GPU, performance state). Read-only; suitable for About/diagnostics page. Uses `NVIDIAGPUIsRunning` sysfs or `nvidia-smi` query. — **bead: LenovoLegionLinux-wkz**
1. **Run external program automation step** — New action type in automation runner: execute a user-defined shell command. Requires input UI + security notice. — **bead: LenovoLegionLinux-hka**
1. **Boot logo customization** — File picker + dimension/format validation + preflight checks + privileged apply. High effort; niche feature. — **bead: LenovoLegionLinux-m75**

### Deferred — Backend work required first

- **always_on_usb_toggle write**: Remove `_alwaysOnUsbWriteSupported = false` guard once upstream `NotImplementedError` is fixed.
- **automation trigger expansion**: Lid, WiFi, time, process triggers require daemon events not yet in `legiond`.
- **camera_power write**: Only possible if `legion_cli` adds `camera-power-enable/disable` subcommands.
