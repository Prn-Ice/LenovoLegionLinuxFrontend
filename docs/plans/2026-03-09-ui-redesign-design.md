# UI Redesign Design Document

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:writing-plans to create the implementation plan from this design.

**Goal:** Transform the app from a flat settings-panel aesthetic into a living control centre — richer dashboard, grouped navigation, control-card feature pages — while remaining 100% Yaru-native.

**Approach:** Phase 1 — navigation restructure + dashboard redesign (tightly coupled). Phase 2 — feature page visual refresh (independently shippable per page).

**Tech Stack:** Flutter, Yaru, flutter_riverpod, riverbloc, existing sysfs/bridge services.

---

## 1. Navigation Structure

### Page count: 11 (restructured from 11)

| Old | New | Change |
|-----|-----|--------|
| Dashboard | Dashboard | Unchanged |
| Power | Power | Content redesign |
| Fans | Fans | Content redesign |
| Battery & Devices | Battery | Split — battery only |
| *(from Battery & Devices)* | Devices | Split — input/USB toggles |
| Discrete GPU | Discrete GPU | Expanded with sensor data |
| Display & Lighting | Display | Split — screen only |
| *(from Display & Lighting)* | Lighting | Split — LEDs only |
| Boot Logo | *(absorbed into Settings)* | Removed as top-level page |
| Analytics + About | Diagnostics | Merged |
| Automation | Automation | Visual redesign |
| Settings | Settings | + Boot Logo section + theme options |

### Sidebar groups

```
Dashboard
─── PERFORMANCE ───
Power
Fans
─── HARDWARE ───
Battery
Devices
Discrete GPU
─── DISPLAY ───
Display
Lighting
─── SYSTEM ───
Automation
Settings
Diagnostics
```

### Implementation

`NavigationShell` currently uses a flat `List<AppSection>`. Replace with a `sealed class NavEntry`:

```dart
sealed class NavEntry {}
class NavHeader extends NavEntry { final String title; }
class NavPage extends NavEntry { final AppSection section; }
```

The full `_entries` list contains both headers and pages. `YaruMasterDetailPage.tileBuilder` returns a `YaruMasterTile` for pages and a `Padding(child: Text(..., style: labelSmall.copyWith(color: muted)))` for headers. The `YaruPageController` length equals the total entry count; `onSelected` ignores header indices by re-selecting the previous valid page. Headers are omitted in the narrow `YaruNavigationPage` rail layout (icons only).

`AppSection` enum gains: `devices`, `diagnostics`. Removes: nothing (Boot Logo stays as enum value but no longer appears in nav — it's rendered inside Settings page).

---

## 2. Dashboard

### Zone 1 — Device Identity (static, full width)

Fetched once at startup from DMI sysfs:

| Field | Source |
|-------|--------|
| Display name | `/sys/class/dmi/id/product_family` + `product_name` → `"Legion Slim 7 16APH8"` |
| Serial | `/sys/class/dmi/id/product_serial` |
| Product code | `/sys/class/dmi/id/product_name` |
| BIOS version | `/sys/class/dmi/id/bios_version` |

Rendered as a `YaruSection` (or `AppControlCard`) with the device name in `headlineMedium` and the three metadata items as a muted `bodySmall` row.

### Zone 2 — Live Sensor Strip (polls every 2 s)

Two-column layout (CPU left, active GPU right). GPU column shows dGPU stats when the discrete GPU is active; falls back to iGPU stats when dGPU is idle/off. Column header = chip name.

**CPU column** (from `/proc/cpuinfo`, `/sys/class/hwmon`, `/proc/stat`, Intel RAPL):
- Name (e.g. `AMD Ryzen 7 7745HX`)
- Utilisation %
- Core clock (average across cores, GHz)
- Temperature °C
- Fan RPM
- Power draw W (shown only if RAPL readable)

**GPU column** (dGPU via `nvidia-smi` or sysfs hwmon; iGPU via sysfs):
- Name (e.g. `NVIDIA GeForce RTX 4060`)
- Utilisation %
- Core clock GHz
- Temperature °C
- Fan RPM
- VRAM used / total GB
- Power draw W (shown only if readable)

**Secondary row** (compact, below the two columns):
```
Motherboard  38°C   ·   Battery  78%  Charging  −18W   ·   Disk  42°C
```
Each item hidden gracefully if not readable on hardware.

**Architecture:** A new `SensorBloc` (or shared Riverpod `sensorProvider`) polls at 2 s. Both the dashboard strip and the Diagnostics page watch the same provider — no double-polling. `SensorSnapshot` model holds all fields as nullable (absent = not available on this hardware).

### Zone 3 — Status line

Rendered directly below the page title as `Text` in `bodySmall`:
```
Quiet Mode  ·  Hybrid GPU  ·  61°C  ·  AC
```

### Zone 4 — Control Cards (2-column `Wrap`, ~520 px min item width)

| Card | Data | Controls |
|------|------|----------|
| **Power Mode** | current mode, available modes, description per mode | `YaruChoiceChipBar` with icon+label per mode; mode descriptions shown below selection |
| **Graphics Mode** | hybrid enabled, current GPU label | Hybrid mode `YaruSwitchListTile`; current GPU label |
| **Battery** | level %, charging state, conservation, rapid charging | Level + state prominent; two `YaruSwitchListTile` |
| **Quick Actions** | max fan state, recommended preset | `[Max Fan Speed]  [Apply Fan Preset]` — outlined + filled `FilledButton` pair |

**`DashboardCard` widget** — used only on the dashboard. Wraps `YaruSection` with:
- `leading` icon in the header row
- Optional `color` tint on the container background (subtle, ~8% opacity)
- Colour tint logic: Power Mode card tints orange when Performance, blue-grey when Quiet; Temperature tints amber when CPU > 80°C

### Zone 5 — Section Navigation Strip

Four tappable shortcut cards in a `Row` at the bottom: Power · Fans · Battery · Display. Each is an `InkWell`-wrapped `YaruTile` with icon + label + subtitle + chevron.

---

## 3. Feature Pages

All feature pages use a new `AppControlCard` widget replacing `AppSectionCard`. `AppControlCard` wraps `YaruSection` and adds:
- Required `IconData icon` displayed in the section headline row
- Optional `Color? tint` for subtle background colouring
- API otherwise identical to `AppSectionCard`

`AppSectionCard` is kept (used in About/Diagnostics and Automation which are not getting the card treatment).

### Power

- **Mode selector**: large `YaruChoiceChipBar` with icon+label per mode. Each mode card shows a one-line description below the chip bar (Quiet: "Low noise · Battery friendly", Balanced: "Everyday performance", Performance: "Maximum power · Gaming").
- **Power limits**: shown in a collapsed `YaruExpandable` by default ("Advanced: Power Limits"). Each limit is a `YaruSliderListTile` or text-field row. Collapsing reduces visual noise for most users.
- **CPU/GPU overclock**: `AppControlCard` with toggle + warning text.

### Fans

- **Action row** (top of page, outside cards): two side-by-side buttons —
  - `OutlinedButton.icon` "Max Fan Speed" — stateful, reflects current on/off with filled/outlined state
  - `FilledButton.icon` "Apply Preset" — opens `YaruDialog` listing available presets. Dialog shows preset name + inferred description (e.g. `quiet-ac` → "Quiet · On AC power"). Recommended preset highlighted. Confirm button applies.
- **Fan Curve card**: `AppControlCard` with a line chart (fl_chart or similar). X-axis: temperature 0–100°C. Y-axis: RPM 0–max. 10 draggable data points. Save button below chart. Dirty-state warning if unsaved changes exist.
- **Controls card**: Mini Fan Curve toggle ("`AppControlCard`" with explanation: "Uses a simplified 3-point curve to reduce noise at idle") + Lock Fan Controller toggle ("Prevents the OS from overriding fan settings").

### Battery

Full-page `AppControlCard` layout inspired by LLT battery view:

**Status header** (prominent): battery icon + `"78%"` in `headlineLarge` + state label ("Charging" / "Discharging" / "Full").

**Health card**:
- Current capacity / Full charge capacity / Design capacity (Wh)
- Battery health %
- Cycle count
- Battery temperature °C

**Live card** (polls every 5 s):
- Discharge rate W (current)
- Min / max discharge rate W
- On battery since (duration, if available)

**Controls card**:
- Battery Conservation `YaruSwitchListTile` + description
- Rapid Charging `YaruSwitchListTile` + description

All health/live values read from `/sys/class/power_supply/BAT0/`.

### Devices

Single `AppControlCard` per logical group:

- **Input**: Touchpad toggle, Win Key toggle, Fn Lock toggle
- **Power**: Always-on USB Charging toggle (with mode selector if applicable)
- **Camera**: Camera power toggle

### Discrete GPU

Replaces the current minimal page. Sections:

**Identity & Stats card** (live, polls every 2 s — shares `SensorBloc`):
- GPU name, driver version
- Utilisation %, Core clock, Memory clock
- Temperature °C, Fan RPM
- VRAM used / total
- Power draw W

**Processes card**: scrollable list of processes using the GPU (PID, name, VRAM). "Kill all GPU processes" destructive `OutlinedButton` at bottom.

**PCI card**: "Restart PCI device" button with warning description.

**Performance card**: GPU Overclock toggle with warning.

**Hybrid Mode card** (moved from Display): Hybrid mode toggle + "Reboot required" notice + current GPU label. Placed here because it is a GPU routing decision.

### Display

Two `AppControlCard` items only:
- Refresh Rate: `YaruChoiceChipBar` or dropdown of available rates
- Overdrive: `YaruSwitchListTile` + description ("Reduces display response time")

### Lighting

`AppControlCard` items:
- **Keyboard Backlight**: On/Off toggle. Placeholder `YaruSection` with muted "OpenRGB integration coming soon" notice for per-key colour control.
- **Y-Logo Light**: On/Off toggle
- **IO Port Light**: On/Off toggle

### Automation

Visual redesign matching LLT's pattern, using Yaru components:

- **Enable toggle** at top: `AppControlCard` with `YaruSwitchListTile`
- **Rules list**: each rule is a `YaruExpandable`. Collapsed: trigger label + step count. Expanded: list of steps, each a `YaruTile` with icon + name + description + action control. Action row per rule: `[Run now]  [Add step]  [Delete]` + "Exclusive" checkbox + "Run on startup" checkbox.
- **Quick Actions section**: same expandable pattern, separate header.
- `[Add new]` `FilledButton` at bottom of each section.

### Settings

Existing settings plus:
- **Appearance card** (new, top): Theme mode selector (`YaruChoiceChipBar`: System / Light / Dark) + Yaru accent colour picker (`YaruColorDisk` grid of `YaruVariant` values)
- **Boot Logo card** (moved from old BootLogoPage): image picker + upload button

### Diagnostics

Merged Analytics + About:

**Top half — Live Sensors** (existing analytics graphs, unchanged logic):
- Line charts for CPU temp, GPU temp, fan RPMs over time

**Bottom half — System Info**:
- Environment card: Kernel, Hardware model, Module version, CLI version (from existing About implementation)
- Command history card: last 20 bridge commands (from existing About implementation)
- Copy JSON export button

---

## 4. Shared Components

| Component | Description |
|-----------|-------------|
| `AppControlCard` | Replaces `AppSectionCard` on feature pages. Adds required `icon`, optional `tint`. |
| `DashboardCard` | Dashboard-only card with icon, tint, used in the 2-column grid. |
| `SensorBloc` / `sensorProvider` | Polls hardware sensors at 2 s. Shared between Dashboard and Diagnostics. |
| `NavEntry` sealed class | `NavHeader` \| `NavPage` — drives the new grouped sidebar. |

---

## 5. Data Changes

### New sysfs reads (added to `LegionSysfsService` or new `SensorService`)

- CPU: utilisation (`/proc/stat`), core clocks (`/sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq`), package temp + fan RPM (hwmon), power draw (Intel RAPL / `/sys/class/powercap/`)
- GPU: all via `nvidia-smi --query-gpu` (utilisation, clocks, temp, fan, VRAM, power) or AMD sysfs equivalent; CPU name from `/proc/cpuinfo`; GPU name from `lspci` or nvidia-smi
- Motherboard temp: hwmon
- Disk temps: hwmon or `smartctl -A`
- Battery full details: `/sys/class/power_supply/BAT0/*` (cycle_count, charge_full, charge_full_design, temp, current_now, voltage_now)
- Device name: `/sys/class/dmi/id/product_family`, `product_name`, `product_serial`, `bios_version` (already partially done in About — move to shared service)

### New models

- `SensorSnapshot` — all live sensor fields, all nullable
- `BatteryDetailSnapshot` — health fields
- `DeviceIdentitySnapshot` — DMI fields (static)

### Existing models unchanged

`DashboardSnapshot`, `FansSnapshot`, `PowerSnapshot`, etc. retain existing fields. The dashboard sensor strip is fed by `SensorBloc`, not `DashboardBloc`.

---

## 6. Out of Scope (future features)

- OpenRGB per-key colour control
- GPU performance overlay
- Fan curve import/export
- Automation rule drag-to-reorder
