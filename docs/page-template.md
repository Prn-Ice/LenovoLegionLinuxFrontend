# Page template

Use the [Dashboard](../lib/features/dashboard/) as the reference for new pages.
Reuse the shared components and theme values below.

## 1. Page skeleton

Use `ConsumerWidget` or `ConsumerStatefulWidget`. Watch the blocs in the page and
render the content inside `AppPageBody`.

```dart
class PowerPage extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state   = ref.watch(powerBlocProvider);
    final sensors = ref.watch(liveSensorBlocProvider);   // compose as needed
    return AppPageBody(
      errorMessage: state.errorMessage,
      children: [ /* cards */ ],
    );
  }
}
```

- Blocs must not listen to other blocs. Watch each bloc in the page with
  `ref.watch` and pass its values to child widgets.
- Put the page title and refresh action in the window title bar, not the page
  content. Configure them in
  [navigation_shell.dart](../lib/features/navigation/view/navigation_shell.dart).
  Use `centerTitle: false` and `_titleBarActions` (`YaruWindowTitleBar.actions`);
  omit the optional `AppPageBody.title`.
- Pass `errorMessage` to `AppPageBody`. Show routine success through the updated
  control. Follow the [error and feedback standard](error-and-feedback-standard.md).

## 2. Cards & layout

- Use **`SurfaceCard`** ([core/widgets/surface_card.dart](../lib/core/widgets/surface_card.dart))
  for cards: radius 13, `surfaceContainerHighest` fill, `onSurface @ 6%` border.
- Use **`ResponsiveCardGrid`** ([core/widgets/responsive_card_grid.dart](../lib/core/widgets/responsive_card_grid.dart))
  for grids of equal cards (quick controls, mode cards) so they reflow by width.
- Spacing between stacked cards: `SizedBox(height: 16)`.

## 3. Telemetry widgets

- **`MetricGauge`** ([core/widgets/metric_gauge.dart](../lib/core/widgets/metric_gauge.dart)) —
  radial 270° gauge for a single value (temps, fans). Size 116 on the dashboard.
- **`MetricTile`** ([core/widgets/metric_tile.dart](../lib/core/widgets/metric_tile.dart)) —
  label + tabular value + thin bar for utilisation rows (CPU/GPU/VRAM/power).
- Keep formatting, fractions, and threshold calculations in
  [metric_format.dart](../lib/core/widgets/metric_format.dart), where they can be
  tested without widgets.
- Both flip to `colorScheme.error` past their `criticalThreshold`.
- **`TelemetryHistoryCard`**
  ([features/analytics/view/widgets/telemetry_history_card.dart](../lib/features/analytics/view/widgets/telemetry_history_card.dart))
  is the shared time-series surface. Pass it the page or card accent and use that
  accent for its chart and selectors.
- Use `SegmentedButton` when the choices fit. Use `YaruPopupMenuButton` at narrower
  widths. Keep their selected colours consistent with the chart accent; popup
  checks use `YaruCheckboxTheme`.
- Label measurements with their units. Explain the source or sign when it could
  be unclear. Battery `power_now` is signed battery-side charge/discharge power,
  not CPU package power or wall power.
- Show `—` for missing readings. Do not invent values or silently substitute
  another measurement.

## 4. Typography

Use Yaru's `TextTheme` for text and the shared mono styles for telemetry numbers.

### Text styles

Use the slot directly; override **only** `color` for the muted hierarchy.

| Role | Yaru slot | Muted color |
|---|---|---|
| Device / section name | `titleMedium` | — |
| Card / control title | `titleSmall` | — |
| Accent emphasis (banner) | `titleSmall` | `.copyWith(color: accent)` |
| Caption / gauge / bar label | `bodySmall` | `onSurface @ 0.7` |
| Subtitle / secondary | `bodySmall` | `onSurface @ 0.56` |
| Stat / micro label | `labelSmall` | `onSurface @ 0.5` |

> Use Yaru's default title weights (w400/w500); re-bold a specific role only
> when needed with `.copyWith(fontWeight: FontWeight.w700)`.

### Telemetry number styles

Telemetry numbers are Ubuntu Mono. Use the named roles in
[metric_text.dart](../lib/core/widgets/metric_text.dart) directly:
`monoStatValueStyle`, `monoGaugeStyle(size, color)`, `monoBarStyle(color)`,
`monoUnitStyle(scheme)`, `monoMetaStyle(scheme)`, `monoFactStyle(scheme)`.

- The font is **Yaru's bundled `UbuntuMono`** — family `'UbuntuMono'` +
  `package: 'yaru'` (constants `kMonoFontFamily` / `kMonoFontPackage`). It is
  always in the build. Do **not** add an app-bundled font (needs a full rebuild;
  silently falls back to sans on hot reload).
- **Never `.copyWith()` a packaged mono style** — copyWith can drop the package
  and the digits silently fall back to sans. Pass state colors (critical→error)
  as an argument instead. Covered by
  [metric_text_test.dart](../test/core/widgets/metric_text_test.dart).

## 5. Colour & accent

- Use theme colours for neutral backgrounds, borders, and text
  (`scheme.onSurface.withValues(alpha: …)`) so both light and dark themes work.
  Define semantic and vendor colours once per page or card.
- Muted hierarchy: **0.7** (label/caption) · **0.56** (subtitle/meta) ·
  **0.5** (micro label) · **0.08** (track/hairline).
- The app resolves the observed power mode once in `appearanceThemes`
  (quiet=blue, balanced=white, performance=red, custom=violet), generating both
  Yaru themes and their component subthemes. Every page and the navigation shell
  uses `Theme.of(context).colorScheme.primary` for its interaction accent.
  Balanced uses dark gray for light-theme interactions so controls remain visible,
  and near-white in dark mode to avoid Yaru's pure-white high-contrast styling.
  The mode colors are approximations based on a laptop's power-button photos.
  Pages must not resolve their own mode or assign a page colour, including Battery
  and Automation. The HTML reference's page-specific accents are not authoritative.
- Mode choices may show the colour of the mode they represent. Status colours,
  GPU logos and selected keyboard RGB colours retain their own meaning. An unsaved
  fan curve does not change the page accent.
- A nested `ColorScheme.copyWith(primary: …)` does not rebuild Yaru's generated
  component subthemes. When a chip or another generated component needs a
  semantic state colour, set that component's selected properties directly and
  leave its inactive appearance to the Yaru theme.

Keep these colour roles separate:

| Role | Purpose | Example |
|---|---|---|
| Interaction accent | Selected controls, chart series, focus | App-wide power-mode accent |
| Semantic status | A proven state or consequence | Active green, warning, destructive error |
| Vendor identity | Hardware manufacturer recognition only | NVIDIA/AMD/Intel mark in a device identity header |

A vendor colour must not tint the page's selectors, switches, chart, or
destructive actions. Likewise, an `Active` badge remains a semantic status even
when the current interaction accent is another colour.

## Icons

Use **`YaruIcons.*`**, not Material `Icons.*`, for generic navigation and action
icons so the app stays Yaru-native. The nav rail already does this via each
section's `icon`. The Fans tab uses the shared `FanIcon` because Yaru has no fan
glyph. Dashboard uses a grid, Power a power symbol, Battery a battery, Lighting
a keyboard, Discrete GPU a chip, Automation a play symbol, and Settings a gear.

For detected hardware, use the manufacturer's logo in its vendor colour, with a
neutral background and accessible label. Use a generic device icon when the
manufacturer is unknown.
See [GPU vendor asset provenance](../assets/gpu_vendors/README.md).

## 6. Supported features and loading states

- Enable controls only for supported features. Test partial support and no
  support, not just fully populated data.
- Keep missing values as `null` through the repository, bloc, and widgets.
- Show a loading state until the first read finishes or fails. Do not show zeros,
  `—`, or an empty process list before then.
- Keep recommendations, selections, completed commands, and confirmed hardware
  state separate. Show a setting as active only after reading it back.
- Hide unsupported secondary controls. If the page's main feature is unavailable,
  explain why and show any readings that still work.
- Prefer native Yaru controls and their established interaction states before
  building custom equivalents.

## 7. Privileged actions

Use `guard` to disable unsupported or busy controls and confirm hardware changes
before applying them (see `_buildQuickControls` in
[dashboard_page.dart](../lib/features/dashboard/view/dashboard_page.dart)):

```dart
onChanged: guard(
  supported: state.fooSupported,
  applying:  state.isApplying,
  title:     'Set foo',
  apply:     (v) => bloc.add(FooSetRequested(v)),
),
```

`guard` returns `null` (disabled) when unsupported or applying, else shows
`confirmPrivilegedAction(...)` before dispatching. Repos that run privileged
commands extend
[`PrivilegedRepository`](../lib/core/data/privileged_repository.dart).

- Keep authentication and save-work guidance brief and legible.
- Use `colorScheme.error` for destructive actions and their consequences, not the
  whole card. Use outlined destructive buttons by default.
- Name the affected processes or devices (PIDs and PCI address when known), explain
  any likely interruption or data loss, and use a specific action label.
- UI preflight checks are not a security boundary. The privileged backend must
  atomically revalidate mutable targets immediately before acting.
- Handle failures using the
  [error and feedback standard](error-and-feedback-standard.md).

## 8. Shell & platform

- Window is a rounded GNOME/Handy window via **handy_window**
  ([linux/runner/my_application.cc](../linux/runner/my_application.cc) registers
  plugins before showing the view).

## 9. Tooling & process

- If you use the optional Nix setup, `.envrc` loads `LLLF_DEV_FLAKE`. Use
  `direnv exec . flutter test` when your terminal has not loaded that environment.
  See [contributor setup](../CONTRIBUTING.md#set-up) and
  [dependency notes](dependencies.md).
- **`dart format` only the files you edited** — never `dart format lib` (the
  formatter can change unrelated files).
- **TDD for logic** (red→green). Declarative styling/config is exempt, but lock
  real invariants (e.g. the mono-font test).
- Verify each change: `flutter analyze` clean + `flutter test` green before
  committing.

## Related guides

- [Model support](model-support.md)
- [M1CN evidence](architecture/m1cn-hardware-evidence.md)
