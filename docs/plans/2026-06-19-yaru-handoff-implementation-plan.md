# Yaru Handoff Implementation Plan

> **For Codex:** Implement this plan task-by-task. Keep the app Yaru-native, use the design handoff as visual direction, and avoid editing generated handoff runtime files.

**Goal:** Translate `docs/Legion Yaru Redesign.dc.html` into the Flutter frontend as a polished native Linux control centre: telemetry-forward dashboard, power-mode accent system, warmer Legion identity, richer Lighting/Fans/Power pages, and a responsive Yaru shell.

**Design Source:** `docs/Legion Yaru Redesign.dc.html`

**Do Not Edit:** `docs/support.js` is generated DC runtime support. Treat it as read-only unless the design handoff tool regenerates it.

**Current State:** The app already has the March structural redesign foundation: grouped navigation with **separate** top-level Battery, Devices, Display, and Lighting pages, shared sensor infrastructure, `AppControlCard`, `DashboardCard`, Diagnostics, dGPU, and fl_chart. Note: `lib/features/battery_devices/` and `lib/features/display_lighting/` exist on disk as view-less, unwired modules left over from an abandoned "combined pages" attempt — they are **not** the live foundation and are deleted in Phase 0. Do not treat them as the current structure or reuse them as skeletons. The new handoff supersedes the live structure where it differs. This plan is a design-source-of-truth implementation pass across all screens, not a light polish pass.

**Tech Stack:** Flutter, Yaru, flutter_riverpod, riverbloc, fl_chart, existing sysfs/bridge/sensor services.

---

## Recovered Implementation Status (2026-08-29)

This status was reconstructed from the Git history, worktree, and the local
Claude VS Code session log. It is the durable resume point for this plan; do not
use the older `LenovoLegionLinux-okf` frontend-parity epic as the redesign
status. That epic predates this handoff.

### Recovered Session

- Claude session: `29b963b8-3021-43d8-97a4-821d550dc699`, titled
  **Review this plan**.
- The session began by reviewing this plan against the generated design source,
  then implemented the foundation, Dashboard, shell, Lighting, and native
  Spectrum support.
- Current branch: `feat/spectrum-native`.
- The recovered hardware checkpoint began at `568bc5b` (`feat(lighting):
  white-balance the native path so white reads neutral`). Lighting validation
  has since completed as recorded below and in `lllf-cqn.1`.
- `feat/yaru-handoff` at `d67615e` and local `main` at `89d9da3` are ancestors
  of the current branch. The native Spectrum commits continue the handoff's
  Lighting phase rather than forming a separate product direction.

### Phase Status

| Scope | Status | Evidence / Remaining Work |
|---|---|---|
| Phase 0 — Repository hygiene | Complete | Orphaned combined modules deleted; `PrivilegedRepository` extracted. |
| Phase 1 — Shared visual foundation | Mostly complete | Accent tokens, Legion mark, metric widgets, responsive grid, Dashboard application, and shell polish landed. Target navigation migration is intentionally incomplete while controls still need new homes. |
| Phase 2 — Dashboard | Substantially complete | Mode hero, telemetry gauges, quick controls, product information, responsive cards, typography, and power-mode accent behavior landed. |
| Phase 3 — Lighting | Complete | Per-key preview/editor, scopes, software effects, profiles, persistence, native Spectrum HID, power limiting, brightness-aware white balance, static painting, key mapping, and animated frame streaming are implemented and hardware-validated. |
| Phase 4 — Fans | Complete | Curve-first CPU/GPU editor, live temperature/RPM telemetry, prominent preset/max-fan actions, privileged safeguards, Custom dirty state, and compact/wide light/dark coverage landed. All 45 Fans tests and the full 380-test suite pass. |
| Phase 5 — Power | Not yet given the new handoff pass | Existing controls predate this handoff. |
| Phase 6a — Battery & dGPU | Not yet given the new handoff pass | Existing pages predate this handoff; Always-on USB has not been migrated. |
| Phase 6b — Automation, Settings & About | Not yet given the new handoff pass | Existing pages predate this handoff; Diagnostics/Devices/Display absorption remains. |
| Phase 7 — Platform surfaces | Not started | OSD, tray, and notification integration remain. |

### Completed Hardware Validation

The retained `tool/_step.dart` diagnostic produced these verified results:

1. Step 5 displayed the expected static per-key rainbow across all 111 LEDs.
2. Step 6 confirmed function, number, letter, numpad, and remaining-key mapping.
3. Steps 9-11 bracketed dim-white green gain, found `0.93` and `0.95` visually
   equivalent, and validated the `0.94` midpoint across all keys at device
   brightness 3. Production now interpolates from `0.94` at levels 0-3 to the
   full-brightness `0.88` gain at level 9 and repaints after brightness changes.
4. Step 8 confirmed single-key painting: only Escape illuminated red.
5. Step 12 exposed the missing Direct-profile initialization. Native streaming
   now sends the required `0xCB` Aura Sync (`0x0D`) profile configuration after
   entering Direct mode and performs the required `0xCA` set/get profile read.
6. A 30-second, 900-frame rainbow streamed smoothly without flicker, stalls, or
   dropped keys. The complete Lighting suite (83 tests) and analyzer passed.

### Worktree Notes At Recovery

- `tool/_step.dart` is retained as a tracked hardware diagnostic with static,
  mapping, calibration, single-key, and configurable-duration animation steps.
- The shared device model is now `RgbLightingDevice`; OpenRGB naming remains
  only on the parser and CLI adapter where it accurately describes the backend.
- `pubspec.lock` contains incidental transitive test-package updates.
- `docs/Legion Yaru Redesign.dc.html` is the generated visual source and
  `docs/support.js` is generated runtime support. Do not hand-edit either.

### Resume Order

1. Start Phase 5 — Power using the design handoff as the visual source of truth.
2. Continue with Battery/dGPU and Automation/Settings as encoded in
   the Beads dependency graph.
3. Migrate omitted controls before removing Devices, Display, or Diagnostics
   from top-level navigation.

### Beads Tracking

The standalone frontend owns a local Beads database with prefix `lllf`. The
durable redesign backlog is:

| Issue | Scope |
|---|---|
| `lllf-cqn` | Complete Yaru design handoff redesign (epic) |
| `lllf-cqn.1` | Finish Lighting hardware validation and model cleanup |
| `lllf-cqn.2` | Apply Yaru handoff to Fans page |
| `lllf-cqn.3` | Apply Yaru handoff to Power page |
| `lllf-cqn.4` | Apply Yaru handoff to Battery and dGPU pages |
| `lllf-cqn.5` | Apply Yaru handoff to Automation and Settings |
| `lllf-cqn.6` | Complete handoff navigation migration |
| `lllf-cqn.7` | Implement or track Yaru platform surfaces |

Use this epic instead of adding new redesign work to the sibling backend
repository's legacy frontend-parity epic.

---

## Design Intent

The handoff describes a native Yaru master-detail app with "elementary-grade craft":

- **Match the handoff first:** implement the designer's screen structure, visual hierarchy, and moved controls as closely as Flutter/Yaru and current backend capabilities allow.
- **Yaru remains the foundation:** retain Yaru navigation, sections, titlebars, list tiles, switches, banners, and choice chips wherever possible.
- **Telemetry is the hero:** live temperatures, fan RPM, power draw, utilisation, and battery state should be visually prominent, especially on Dashboard and Diagnostics.
- **Accent follows power mode:** Quiet, Balanced, Performance, and Custom each provide an app accent and soft tint.
- **Warmth without gimmickry:** the small Legion sprite/mark gives identity, but it should not override native desktop feel.
- **Adaptive desktop window:** the shell and card grids must behave well from compact rail layout through wide sidebar layout.
- **No silent feature loss:** if a current feature is not represented in the handoff, call it out and either place it in the closest designed home or ask for a design decision before deleting it.

---

## Design Matching Directive

The handoff is the source of truth for the redesign.

- **All designed screens are in scope:** Dashboard, Power, Fans, Lighting, OSD, KDE tray/notifications, Battery, dGPU, Automation, Settings & About, and responsive shell.
- **Move controls when the design moves them:** do not keep an old page layout only because the current app is organized that way.
- **Absorb removed pages:** if the design removes a top-level page, migrate its functionality into the closest designed page rather than dropping it.
- **Preserve backend behavior:** UI movement should reuse existing blocs/repositories where possible.
- **Track exceptions:** any current functionality with no designed home goes into the "Existing Functionality Not Covered by Handoff" ledger below.

### Target Navigation From Handoff

The visual handoff sidebar shows this top-level app navigation:

```text
Dashboard
Power
Fans
Battery
Lighting
dGPU
Automation
Settings
```

Current sections that are not shown as top-level pages should be migrated:

| Current Page | Handoff Treatment | Migration Direction |
|---|---|---|
| Devices | Not a top-level page | Move supported quick controls into Dashboard/Battery/Settings |
| Display | Not a top-level page | Move display controls to Settings or request design home |
| Diagnostics | Not a top-level page | Fold core diagnostics/export into Settings & About; keep deeper view only if still needed |
| Boot Logo | Not shown in Settings & About screen | Keep in Settings until designer gives a replacement or removal decision |

### Designed Control Moves

| Current Functionality | Designed Home | Notes |
|---|---|---|
| Fn Lock | Dashboard quick controls | Section 01 shows "Fn lock" |
| Touchpad | Dashboard quick controls | Section 01 shows "Touchpad" |
| Battery conservation/health | Dashboard quick controls + Battery | Sections 01, 02, 08 |
| Rapid charging | Dashboard quick controls + Battery | Sections 01, 02, 08 |
| Always-on USB | Battery | Section 08 shows "Always-on USB" |
| Hybrid/dGPU working mode | dGPU | Section 09 shows GPU working mode |
| About/version/actions | Settings & About | Section 11 |
| Copy diagnostics | Settings & About | Section 11 |
| External/run command automation | Automation rule builder | Section 10 shows "Run command…" |

---

## Existing Functionality Not Covered by Handoff

These features exist in the app today but do not have a clear or complete visual home in the new handoff. Do not remove them without an explicit decision.

| Existing Feature | Current Location | Handoff Coverage | Recommended Handling |
|---|---|---|---|
| Win Key toggle | Devices | Not shown | Move to Settings > Devices/Input or ask designer |
| Camera power toggle | Devices | Not shown | Move to Settings > Devices/Privacy or ask designer |
| Display overdrive | Display | Not shown | Move to Settings > Display or ask designer |
| Refresh-rate switching | Display | Not shown | Move to Settings > Display or ask designer |
| Boot logo customization | Settings/Boot Logo page | Not shown in Section 11 | Keep as Settings card pending design decision |
| Full Diagnostics page | Diagnostics | Only "Copy diagnostics" shown | Fold essentials into Settings & About; keep deep Diagnostics if still required |
| Runtime dependency list | Diagnostics | Not shown | Fold into Settings > Backend or Diagnostics detail |
| Backend capability probes | Diagnostics | Not shown | Fold into Settings > Backend or Diagnostics detail |
| Command history JSON | Diagnostics | Only copy diagnostics action shown | Keep behind Copy diagnostics/detail view |
| System service controls | Settings | Only module/CLI status shown | Map to Settings > Backend if still useful |
| CPU overclock toggle | Power | Not shown | Keep under Power > Custom/Advanced pending decision |
| GPU overclock toggle | Power/dGPU | Partially implied by dGPU performance | Prefer dGPU > Performance |
| White keyboard backlight fallback | Lighting | Handoff focuses per-key RGB | Keep as fallback state for non-RGB devices |
| Y-logo light | Lighting | Not shown; handoff says "no lid logo" for target model | Hide when unsupported; keep if backend reports support |
| IO-port light toggle | Lighting | Rear I/O ports shown | Preserve and redesign under Lighting > Rear ports |
| Automation poll interval/run now | Automation | Not shown directly | Keep as secondary controls or advanced settings |
| Automation conservation/rapid-charge policies | Automation | Not shown directly | Represent as rule actions if possible |

## New Design Functionality Not Yet Fully Present

These are in the handoff and may need new implementation beyond visual rearrangement.

| Designed Feature | Handoff Section | Current Coverage | Implementation Direction |
|---|---|---|---|
| Global mode accent retinting | Sections 01–03, 11 | Partial/manual accent setting | Add accent-follow-power-mode setting and local theme tokens |
| Per-key RGB editor/preview | Section 05 | Current page has simpler toggles | Implement adaptive RGB UI when capability exists |
| OpenRGB handoff | Section 05 | Not clearly implemented | Add detection/action if backend supports it, otherwise show unavailable |
| Battery history/log export | Section 08 | Diagnostics/analytics adjacent only | Reuse analytics infrastructure or add battery-specific history |
| dGPU history chart | Section 09 | Stats/processes exist | Reuse sensor history if available |
| Automation rule builder | Section 10 | Current settings-style automation | Redesign config into rule cards without losing existing actions |
| OSD overlay | Section 06 | Not implemented | Requires platform/window integration |
| KDE tray menu/notifications | Section 07 | Not implemented | Requires StatusNotifierItem/notifications integration |

## Design Tokens

Create a single source of truth for mode accent styling.

### Accent Palette

| Mode | Color | Soft Tint | Label | Handoff Meaning |
|---|---:|---:|---|---|
| Quiet | `#12a4b8` | `rgba(18,164,184,.20)` | Quiet | Cool and silent |
| Balanced | `#3a9d4f` | `rgba(58,157,79,.20)` | Balanced | Smart middle |
| Performance | `#ec5f2a` | `rgba(236,95,42,.20)` | Performance | Full power |
| Custom | `#8056d6` | `rgba(128,86,214,.22)` | Custom | User tuned |

### Files

- Create: `lib/core/theme/legion_accent.dart`
- Test: `test/core/theme/legion_accent_test.dart`

### API Shape

```dart
enum LegionAccentMode { quiet, balanced, performance, custom }

class LegionAccent {
  const LegionAccent({
    required this.mode,
    required this.color,
    required this.label,
    required this.description,
  });

  final LegionAccentMode mode;
  final Color color;
  final String label;
  final String description;

  Color soft(ColorScheme scheme, {double alpha = 0.14});
  Color onSoft(ColorScheme scheme);
}
```

### Mapping Rules

- Map `PowerMode.quiet` → Quiet accent.
- Map `PowerMode.balanced` → Balanced accent.
- Map `PowerMode.performance` → Performance accent.
- Map custom/manual fan or custom power configuration → Custom accent where applicable.
- Fall back to `Theme.of(context).colorScheme.primary` if current mode is unknown.

---

## Shared Visual Primitives

Build small reusable widgets before touching page layouts. This keeps the redesign coherent and avoids copy-paste styling.

### Task 1: Legion Identity Mark

**Goal:** Add the small robot/sprite mark from the handoff as a Flutter-native widget.

**Files:**
- Create: `lib/core/widgets/legion_mark.dart`
- Test if practical: `test/core/widgets/legion_mark_test.dart`

**Implementation Notes:**
- Use `CustomPainter` or simple composed Flutter shapes.
- Accept `Color color`, `double size`, and `bool showAntenna`.
- Avoid SVG dependency unless already present.
- Use it in the shell title/sidebar footer and settings/about card.

**Design geometry** (extracted from the handoff inline SVG, viewBox `0 0 26 26` — the design is the source of truth for the mark):
- Antenna (`showAntenna`): line `(13, 2) → (13, 5.5)`, stroke width `1.7`, round cap; tip circle at `(13, 2)`, r `1.7`.
- Head: rounded rect at `(4, 5)`, size `18×16`, corner radius `5.5` (~21%).
- Eyes: white circles at `(9.6, 12.6)` and `(16.4, 12.6)`, r `2.3`.
- Pupils: accent-colored circles at `(10.1, 13)` and `(16.9, 13)`, r `1`.
- Mouth: white rounded rect at `(10, 16.6)`, size `6×1.7`, radius `0.85`, opacity `0.75`.
- Fill = the `color` param (the power-mode accent); eyes always white, pupils take the fill color. Default custom accent `#8056d6`.

### Task 2: Mode-Aware Card Shell

**Goal:** Make `DashboardCard` and `AppControlCard` capable of matching the handoff’s soft tinted panels without abandoning Yaru.

**Files:**
- Modify: `lib/core/widgets/app_shell_components.dart`

**Implementation Notes:**
- **Already half-built:** `AppControlCard` and `DashboardCard` already accept a `tint` and apply it via `withValues(alpha: 0.06)` (see `app_shell_components.dart`). This task **extends** that existing parameter to be accent-aware; it is not new card scaffolding.
- Keep `YaruSection` inside `AppControlCard`.
- Use subtle `Color.alphaBlend` or `withValues(alpha: 0.06–0.12)` for tints.
- Add optional `accent`/`accentColor` only if it simplifies page code.
- Do not introduce a parallel card system that competes with `YaruSection`.

### Task 3: Telemetry Gauge Widgets

**Goal:** Provide reusable gauges for CPU temp, GPU temp, fan RPM, utilisation, and power draw.

**Files:**
- Create: `lib/core/widgets/metric_gauge.dart`
- Create: `lib/core/widgets/metric_tile.dart`
- Test formatting helpers: `test/core/widgets/metric_format_test.dart`

**Implementation Notes:**
- Prefer custom paint for radial gauges to avoid heavy chart overhead.
- Use `Ubuntu Mono`-friendly tabular text through `FontFeature.tabularFigures()` where useful.
- Support unavailable/null values gracefully.
- Animate changes lightly; avoid constant motion that distracts from native feel.
- `sensor_strip.dart` (Dashboard) should be adapted to render via `MetricTile`, or replaced by a strip built from `MetricTile` — do not leave a second sensor-rendering convention alongside the new gauges.

### Task 4: Responsive Card Grid

**Goal:** Standardize auto-fit card layout across Dashboard, Lighting, Fans, Settings, and Diagnostics.

**Files:**
- Create: `lib/core/widgets/responsive_card_grid.dart`

**Implementation Notes:**
- Use `LayoutBuilder` + `Wrap` or `GridView` with explicit constraints.
- Default min card width: `300–360`.
- Dashboard hero cards may use wider min width: `420–520`.
- Keep all content scrollable and avoid horizontal overflow.

---

## Phase 0 — Repository Hygiene (pre-redesign)

Do this before any UI work. It removes abandoned modules and the duplicated
privileged-command plumbing so later phases build on one clean repository layer
instead of forking dead code.

### 0.1 Delete orphaned feature modules

`lib/features/battery_devices/` and `lib/features/display_lighting/` are dead
code from an abandoned "combined pages" refactor. Neither has a view, neither is
imported anywhere outside its own folder, and every method in both is reproduced
verbatim in a live, routed feature:

- `battery_devices/` — a telemetry-less subset of live `battery/` + `devices/`
  (same commands, same `_alwaysOnUsbWriteSupported`/okf.4 guardrail, but missing
  all battery metrics and `setCamera`).
- `display_lighting/` — overdrive + xrandr refresh-rate duplicate live `display/`;
  hybrid mode duplicates live `dgpu/`; keyboard/Y-logo/IO-port duplicate live
  `lighting/`.

**Action:** delete both directories. Do **not** reuse them as skeletons for the
new combined Dashboard/Battery surfaces — build those from the live repos, which
carry the telemetry these stubs lack.

**Keep `lib/features/about/`** — it has no view but its bloc/repo actively powers
the Diagnostics page and is the intended data source for the Phase 6 Settings &
About merge. Do not delete it.

### 0.2 Introduce `PrivilegedRepository` base

Eight repositories (`battery`, `devices`, `fans`, `automation`, `dashboard`,
`dgpu`, `boot_logo`, plus the to-be-deleted `battery_devices`) each carry an
identical private `_runPrivilegedCommand` helper: the same try/catch around
`bridgeService.runPrivilegedCommand`, the same `failurePrefix`/`details` message
assembly, differing only in which feature-specific exception they throw. Lift it
into a shared base.

**Files:**
- Create: `lib/core/data/privileged_repository.dart`
- Create: `test/core/data/privileged_repository_test.dart`
- Modify: the 7 surviving feature repositories to extend it.

**API shape:**

```dart
abstract class PrivilegedRepository {
  const PrivilegedRepository({required this.bridgeService});

  final LegionFrontendBridgeService bridgeService;

  /// Subclass supplies its own feature-specific exception type.
  Exception wrapBridgeError(String message);

  @protected
  Future<void> runPrivilegedCommand(
    List<String> args, {
    required String method,
    required String failurePrefix,
    Duration timeout = const Duration(seconds: 5),
    bool detectUnavailableResponse = true,
  }) async {
    try {
      await bridgeService.runPrivilegedCommand(
        method: method,
        args: args,
        timeout: timeout,
        detectUnavailableResponse: detectUnavailableResponse,
      );
    } on LegionBridgeException catch (error) {
      final details = error.details;
      final message =
          details.isEmpty ? '$failurePrefix.' : '$failurePrefix: $details';
      throw wrapBridgeError(message);
    }
  }
}
```

**Also migrated:** `power`, `lighting`, and `display` issue privileged commands
through a higher-level `_runFeatureToggle` helper that shared the same try/catch
tail. These now extend `PrivilegedRepository` too (10 of 10), with
`_runFeatureToggle` reduced to a thin delegate to `runPrivilegedCommand`. This
**intentionally normalized** their error text: the details-present case is now
`"Failed to set X to on: <details>"` (previously the asymmetric
`"Failed to set X: <details>"`), matching every other repo. In `power`, the two
inline `setPowerMode`/`setPowerLimit` methods also route through the base; their
messages were already symmetric, so those are unchanged.

**Behavior preservation is the whole risk here.** The base defaults
(`timeout: 5s`, `detectUnavailableResponse: true`) deliberately match
`LegionFrontendBridgeService.runPrivilegedCommand`'s own defaults. The private
helpers being removed encoded *different* effective defaults, so three repos must
pass their knobs explicitly at the call sites or behavior changes silently:

| Repo | Must pass explicitly after refactor |
|---|---|
| `battery`, `devices`, `fans`, `automation` | nothing — already match defaults |
| `dashboard` | `detectUnavailableResponse: false` |
| `dgpu` | `detectUnavailableResponse: false`, `timeout: const Duration(seconds: 10)` |
| `boot_logo` | `timeout: const Duration(seconds: 30)` |

There are no existing tests over these repos, so add characterization tests for
the base (`wrapBridgeError` is invoked, message assembly with/without `details`,
defaults forwarded) before refactoring, and grep each repo's call sites against
the table above after.

### 0.3 Consolidate the Always-on USB guardrail

The `_alwaysOnUsbWriteSupported = false` / okf.4 read-only gate is currently
copy-pasted in `devices/` and `battery_devices/`. Deleting `battery_devices/`
(0.1) removes one copy; the canonical copy stays in `devices/`. When Phase 6
moves Always-on USB to the Battery surface, move the guardrail with it rather
than re-forking it — keep exactly one source of truth.

### Acceptance Criteria

- `battery_devices/` and `display_lighting/` no longer exist; `about/` retained.
- No repository defines a private `_runPrivilegedCommand`; all 10 privileged
  repos extend `PrivilegedRepository`. `power`/`lighting`/`display` keep
  `_runFeatureToggle` only as a thin delegate to the base.
- Per-repo effective `timeout`/`detectUnavailableResponse` values are unchanged
  (verified against the table above).
- `dart format`, `flutter test`, and `flutter analyze` pass.

---

## Phase 1 — Foundation Slice

This is the first coding slice. It should be small, reviewable, and safe.

### Scope

- Add `LegionAccent`.
- Add `LegionMark`.
- Add `MetricGauge`/`MetricTile`.
- Add `ResponsiveCardGrid`.
- Lightly adapt `AppControlCard`/`DashboardCard`.
- Align top-level navigation with the handoff target list, using temporary hidden/overflow access only for unmigrated functionality.
- Apply only to `DashboardPage` and the shell title/sidebar/footer.

### Files Likely Touched

- `lib/core/theme/legion_accent.dart`
- `lib/core/widgets/app_shell_components.dart`
- `lib/core/widgets/legion_mark.dart`
- `lib/core/widgets/metric_gauge.dart`
- `lib/core/widgets/metric_tile.dart`
- `lib/core/widgets/responsive_card_grid.dart`
- `lib/features/dashboard/view/dashboard_page.dart`
- `lib/features/dashboard/widgets/sensor_strip.dart`
- `lib/features/navigation/models/app_section.dart`
- `lib/features/navigation/models/nav_entry.dart`
- `lib/features/navigation/view/navigation_shell.dart`
- Tests under `test/core/` and `test/features/dashboard/` if adjacent patterns exist.

### Acceptance Criteria

- Dashboard uses the shared accent from current power mode when available.
- Shell includes the Legion mark without breaking Yaru titlebar/nav behavior.
- Dashboard telemetry feels closer to the handoff without changing backend behavior.
- Null/unavailable sensor values render cleanly.
- `dart format`, `flutter test`, and `flutter analyze` pass.

---

## Phase 2 — Dashboard Polish

### Goal

Make Dashboard the visual center of the app: status, telemetry, and common controls should be immediately readable.

### Work Items

1. **Mode Hero**
   - Show current power mode with accent color, mode description, battery/AC state, and quick mode selector.
   - Use `YaruChoiceChipBar` for mode selection.

2. **Telemetry Hero**
   - Promote CPU temp, GPU temp, CPU fan RPM, GPU fan RPM into prominent gauges.
   - Add compact utilisation bars for CPU/GPU/RAM if data exists.
   - Keep existing `LiveSensorBloc`/repository; no duplicate polling.

3. **Power Draw Card**
   - Use existing sensor fields where available.
   - If historical sparkline data is not available, show current W values only and leave chart/history for Diagnostics.

4. **Quick Controls**
   - Rapid charge, conservation/battery health, Fn lock, touchpad, max fans, fan preset.
   - Use existing blocs/repositories where already implemented.
   - Disable controls with explanatory copy when unsupported.

5. **Quick-Control Hub**
   - Match the handoff's quick-control layout: battery health, keyboard light, rapid charge, rapid cooling, telemetry, and automation status.
   - Do not add shortcuts to removed top-level pages unless the design shows them.
   - Use moved Devices controls here when the handoff explicitly places them here.

### Acceptance Criteria

- Dashboard is useful at a glance in both light and dark themes.
- The layout stacks cleanly below 600px and uses two-column cards when wide.
- No backend/service changes are required unless a value is already available but not exposed.

---

## Phase 3 — Lighting Page

### Goal

Translate the "Keyboard & RGB Lighting" handoff into the existing Lighting feature.

### Work Items

1. **Lighting Hero**
   - Add a top card with keyboard/backlight status, brightness, and active profile/effect.
   - Use pink/magenta lighting accent locally without overriding global power accent.

2. **Brightness Control**
   - Keep Yaru-native slider/list-tile structure.
   - Add clear disabled/unavailable states.

3. **Effect/Profile Cards**
   - Present profiles as compact visual tiles.
   - Prefer existing repository data; avoid inventing unsupported effects.

4. **Keyboard Preview**
   - Add a lightweight stylized keyboard preview only if it can be built without high maintenance.
   - If keyboard zones are not reliably known, use a generic preview and label it accordingly.

### Acceptance Criteria

- Lighting page looks intentionally designed, not just a settings list.
- Existing lighting controls keep working.
- Unsupported devices get friendly empty states.

---

## Phase 4 — Fans Page

### Goal

Make fan control feel like a proper tuning surface while preserving safety and clarity.

### Work Items

1. **Action Row**
   - Prominent max fan speed toggle.
   - Apply preset button/dialog with recommended preset highlight.

2. **Fan Curve Editor**
   - Keep existing fl_chart curve editor.
   - Apply handoff styling: cleaner card, accent points, better axis labels, clearer dirty state.

3. **Fan Telemetry**
   - Show current fan RPM gauges.
   - Show CPU/GPU temperatures next to fan state.

4. **Safety Copy**
   - Keep explanations for mini fan curve and lock fan controller.
   - Ensure dangerous/privileged actions are visually distinct.

### Acceptance Criteria

- Preset and max-fan actions are easy to find.
- Fan curve remains usable with keyboard/mouse and does not overflow.
- No change to underlying fan curve serialization unless required by bugs.

---

## Phase 5 — Power Page

### Goal

Make power mode and custom tuning reflect the handoff’s interactive "Power & Custom Mode" screen.

### Work Items

1. **Power Mode Selector**
   - Large `YaruChoiceChipBar` with icon + label.
   - Show mode description from `LegionAccent`.

2. **Mode-Aware Accent**
   - Tint page cards according to selected/current mode.
   - Do not permanently override the app theme unless "accent follows power mode" exists in settings.

3. **Power Limits**
   - Keep advanced controls in `YaruExpandable` by default.
   - Improve labels, units, and warnings.

4. **Overclock/Custom**
   - Use custom purple accent for manual/custom tuning sections.
   - Keep warnings close to toggles.

### Acceptance Criteria

- Common mode switching is visually simple.
- Advanced controls are discoverable but not noisy.
- Existing power repository and bloc behavior stays unchanged.

---

## Phase 6a — Battery & dGPU

### Battery

- Add a prominent battery status header.
- Group health, live usage, and controls.
- Reuse metric tiles for Wh, cycles, temperature, and discharge rate.
- Keep conservation and rapid charge controls native and clear.
- Move Always-on USB here from Devices, matching Section 08.
- Add history/logging/export UI by reusing the existing `lib/features/analytics/` bloc/repository (already present); only add a small new storage slice if analytics cannot supply battery-specific history.

### dGPU

- Make identity/stats card telemetry-forward.
- Keep process list readable and scrollable.
- Destructive actions stay outlined/destructive with warning copy.
- Hybrid mode belongs here if the current app already routes it that way.
- Match Section 09: active/P-state, power state, temp, draw, VRAM, usage chart, processes, deactivate actions, and working mode.

---

## Phase 6b — Automation, Settings & About

### Automation

- Redesign the current settings-style Automation page into the Section 10 rule-builder vocabulary.
- Preserve current automation capabilities by representing them as triggers/actions where possible.
- Keep `Run now`, poll interval, and last-run status as secondary/advanced controls if still needed.
- External command maps to the designed "Run command…" action.

### Settings

- Add Appearance group:
  - Theme mode.
  - Accent follows power mode.
  - OSD/notification preferences if implemented.
- Add Backend group:
  - module status.
  - CLI path/status.
  - restart/check actions where supported.
- Add About card with `LegionMark`, version, device identity, GitHub/report/copy diagnostics actions.
- Source About/Backend/diagnostics data from the existing `lib/features/about/` bloc/repository — it already powers the current Diagnostics page (hardware model, kernel, module/CLI version, CLI health, capability probes, command history), so this is view-layer reuse, not new backend work. (`about/` is the module Phase 0 explicitly retains.)
- Absorb current Diagnostics essentials into Settings & About unless a deeper diagnostics page remains explicitly justified.
- Keep Boot Logo customization as a Settings card pending a design decision.

### Absorbed Devices and Display Functionality

- Move Fn Lock and Touchpad to Dashboard quick controls.
- Move Always-on USB to Battery.
- Move Win Key, Camera, Overdrive, and Refresh Rate to Settings subgroups or request a design decision before implementation.
- Remove Devices and Display from top-level navigation once their functionality has a designed home.

---

## Phase 7 — Platform Surfaces

The handoff includes OSD overlays, KDE tray menu, and notifications. They are part of the full design match, but they require platform integration beyond normal Flutter page composition.

### OSD

- Requires desktop overlay/window behavior.
- Should use accent-aware compact widgets.
- Trigger on power mode, keyboard brightness, fan boost, and automation changes.
- If native overlay support is not ready, build the reusable OSD widget and document the integration blocker.

### Tray

- Requires StatusNotifierItem/AppIndicator integration decision.
- Should expose quick power mode, fan boost, battery health, keyboard light, open app, quit.
- Should honor desktop conventions: Plasma/Breeze actions remain desktop-colored, not forced Yaru.
- If tray support is not ready, keep the tray menu design documented and create an integration issue.

### Notifications

- Use `org.freedesktop.Notifications`.
- App accent can appear in icon/artwork, but desktop notification chrome should remain native.
- If notifications are not ready, keep in-app events structured so they can emit notifications later.

### Acceptance Criteria

- **OSD:** the reusable OSD widget renders in isolation (widget test or demo route) with accent-aware styling and null-safe values. If native overlay triggering is not wired, the blocker is filed as a tracked issue, not silently skipped.
- **Tray:** either a working StatusNotifierItem exposing the quick actions, or a documented tray-menu design plus a created integration issue — not an empty stub.
- **Notifications:** either events emit via `org.freedesktop.Notifications`, or in-app events are structured to emit later with the gap documented.
- Phase 7 may ship "widget built + blocker documented"; it may **not** ship "nothing, untracked".

---

## Validation Plan

Run validation after each phase, starting targeted and widening.

### Formatting

```bash
dart format lib test
```

### Tests

```bash
flutter test
```

### Analysis

```bash
flutter analyze
```

### Manual QA

- Light theme and dark theme.
- Wide window: ≥1000px.
- Medium window: 600–999px.
- Compact window: <600px.
- Target handoff navigation: Dashboard, Power, Fans, Battery, Lighting, dGPU, Automation, Settings.
- Removed top-level pages have no orphaned controls.
- Moved controls appear in their designed homes.
- Missing sensor values.
- Unsupported lighting/fan/battery capabilities.
- AC and battery states.
- Quiet, Balanced, Performance, and Custom modes.

---

## Rollout Strategy

Use small commits or review chunks.

Phase 0 (repository hygiene) lands first:

- `chore(cleanup): delete orphaned battery_devices and display_lighting modules`
- `refactor(core): extract PrivilegedRepository base from feature repositories`

Then the redesign commits:

1. `feat(theme): add legion accent tokens`
2. `feat(ui): add legion mark and metric widgets`
3. `refactor(ui): add responsive card grid`
4. `feat(nav): match handoff navigation structure`
5. `feat(dashboard): apply handoff telemetry layout`
6. `feat(lighting): match keyboard rgb handoff`
7. `feat(fans): match fan curve editor handoff`
8. `feat(power): match power custom mode handoff`
9. `feat(battery): match energy screen handoff`
10. `feat(dgpu): match monitor deactivate handoff`
11. `feat(automation): match rule builder handoff`
12. `feat(settings): merge settings about diagnostics`
13. `feat(platform): add osd tray notification surfaces`

---

## Risks and Guardrails

- **Risk:** Over-customizing until the app stops feeling Yaru-native.
  - **Guardrail:** use Yaru primitives first; custom paint only for gauges/mark.

- **Risk:** Duplicating sensor polling.
  - **Guardrail:** all live sensor UI consumes existing shared sensor provider/bloc.

- **Risk:** Designing unsupported controls.
  - **Guardrail:** every control must map to an existing repository capability or clearly show unavailable state.

- **Risk:** Losing existing functionality because the new handoff omits it.
  - **Guardrail:** use the "Existing Functionality Not Covered by Handoff" ledger; migrate omitted features or ask for a design decision before removal.

- **Risk:** Removing `AppSection` values (Devices, Display, Diagnostics) breaks navigation routing, persisted nav state, and any tests/fixtures referencing them.
  - **Guardrail:** migrate each page's controls to their designed home first; then remove the route dispatch in `navigation_shell.dart`, then the `AppSection` enum member, then the feature directory — in that order. Audit `navigation_shell.dart` and nav tests before deleting any enum value.

- **Risk:** Global accent changes become surprising.
  - **Guardrail:** start with local card/selection tinting; only add global theme mutation behind a Settings toggle.

- **Risk:** The generated handoff changes.
  - **Guardrail:** never hand-edit `docs/support.js`; compare against `docs/Legion Yaru Redesign.dc.html` for design intent.

---

## First Task Checklist

1. Create `LegionAccent` model and tests.
2. Create `LegionMark`.
3. Create `MetricGauge` and `MetricTile`.
4. Create `ResponsiveCardGrid`.
5. Adapt `DashboardCard` tint behavior if needed.
6. Update navigation target list to match the handoff, with temporary routes only for unmigrated functionality.
7. Apply the primitives to Dashboard only.
8. Add shell identity polish only after Dashboard compiles.
9. Run `dart format`, `flutter test`, and `flutter analyze`.
