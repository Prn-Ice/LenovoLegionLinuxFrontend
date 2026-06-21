# Page template (Yaru redesign)

The **Dashboard** ([lib/features/dashboard/](../lib/features/dashboard/)) is the
reference implementation. Every new page (Power, Fans, Battery, Lighting, …)
should follow the patterns below so the app stays consistent and the shared
primitives keep paying off. The design source of truth is
[docs/Legion Yaru Redesign.dc.html](Legion%20Yaru%20Redesign.dc.html) — read the
exact CSS values from it rather than eyeballing.

---

## 1. Page skeleton

A page is a `ConsumerStatefulWidget` (or `ConsumerWidget`) that **composes blocs
at the widget layer** and renders into `AppPageBody`.

```dart
class PowerPage extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state   = ref.watch(powerBlocProvider);
    final sensors = ref.watch(liveSensorBlocProvider);   // compose as needed
    return AppPageBody(
      errorMessage: state.errorMessage,
      noticeMessage: state.noticeMessage,
      children: [ /* cards */ ],
    );
  }
}
```

- **Blocs never listen to other blocs.** If a page needs data from several
  blocs, `ref.watch` each one in the page and pass values down. (See the
  dashboard wiring power + sensors + devices together.)
- **No content title header.** `AppPageBody.title` is optional and the dashboard
  passes none — the page starts at its first card. The section name is shown
  **left-aligned in the window title bar** (`centerTitle: false`), wired in
  [navigation_shell.dart](../lib/features/navigation/view/navigation_shell.dart).
- **Refresh lives in the title bar**, not the content. Add it per-section via
  `_titleBarActions` in the shell (`YaruWindowTitleBar.actions`).

## 2. Cards & layout

- **Always use `SurfaceCard`** ([core/widgets/surface_card.dart](../lib/core/widgets/surface_card.dart))
  for card surfaces — never bare `YaruBorderContainer`, whose default fill is
  transparent (cards come out flat). `SurfaceCard` = radius 13,
  `surfaceContainerHighest` fill, subtle `onSurface @ 6%` border.
- Use **`ResponsiveCardGrid`** ([core/widgets/responsive_card_grid.dart](../lib/core/widgets/responsive_card_grid.dart))
  for grids of equal cards (quick controls, mode cards) so they reflow by width.
- Spacing between stacked cards: `SizedBox(height: 16)`.

## 3. Telemetry widgets

- **`MetricGauge`** ([core/widgets/metric_gauge.dart](../lib/core/widgets/metric_gauge.dart)) —
  radial 270° gauge for a single value (temps, fans). Size 116 on the dashboard.
- **`MetricTile`** ([core/widgets/metric_tile.dart](../lib/core/widgets/metric_tile.dart)) —
  label + tabular value + thin bar for utilisation rows (CPU/GPU/VRAM/power).
- Pure value math (format, fraction, critical) is in
  [metric_format.dart](../lib/core/widgets/metric_format.dart) — kept
  widget-free so it's unit-tested directly.
- Both flip to `colorScheme.error` past their `criticalThreshold`.

## 4. Typography — **the rule**

**Yaru's `TextTheme` is the scale for all text. Mono is the one exception.**
Do NOT build a parallel type scale.

### Sans → nearest Yaru `textTheme` slot

Use the slot directly; override **only** `color` for the muted hierarchy.

| Role | Yaru slot | Muted color |
|---|---|---|
| Device / section name | `titleMedium` | — |
| Card / control title | `titleSmall` | — |
| Accent emphasis (banner) | `titleSmall` | `.copyWith(color: accent)` |
| Caption / gauge / bar label | `bodySmall` | `onSurface @ 0.7` |
| Subtitle / secondary | `bodySmall` | `onSurface @ 0.56` |
| Stat / micro label | `labelSmall` | `onSurface @ 0.5` |

> Yaru's title slots are w400/w500 — lighter than the design's w700. We accept
> Yaru weight by default; re-bold a specific role only on request with
> `.copyWith(fontWeight: FontWeight.w700)`.

### Mono → `metric_text.dart` roles

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
  as an argument instead. A test
  ([test/core/widgets/metric_text_test.dart](../test/core/widgets/metric_text_test.dart))
  locks this invariant.

## 5. Colour & accent

- Colours are **theme-relative** (`scheme.onSurface.withValues(alpha: …)`),
  never hardcoded hex — so light/dark both work.
- Muted hierarchy: **0.7** (label/caption) · **0.56** (subtitle/meta) ·
  **0.5** (micro label) · **0.08** (track/hairline).
- The page accent comes from
  [`LegionAccent.fromPowerModeValue`](../lib/core/theme/legion_accent.dart)
  (quiet=teal, balanced=green, performance=orange, custom=violet). Thread the
  resolved `Color accent` into cards.

## 6. Privileged actions

Toggles/buttons that change hardware go through a confirm + guard pattern (see
`_buildQuickControls` in
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

## 7. Shell & platform

- Window is a rounded GNOME/Handy window via **handy_window**
  ([linux/runner/my_application.cc](../linux/runner/my_application.cc) registers
  plugins before showing the view).
- Section title bar: left-aligned (`centerTitle: false`), section-specific
  actions via `_titleBarActions`.

## 8. Tooling & process

- **Flutter is not on PATH** — run via the nix flake:
  `nix develop /home/prnice/Projects/personal/nix_flakes/flutter_flake --command bash -c "cd <repo> && flutter test"`.
- **`dart format` only the files you edited** — never `dart format lib` (the
  flake's formatter churns unrelated files).
- **TDD for logic** (red→green). Declarative styling/config is exempt, but lock
  real invariants (e.g. the mono-font test).
- Verify each change: `flutter analyze` clean + `flutter test` green before
  committing.

## 9. Known data gaps (dev machine)

Not app bugs — missing kernel data on this host: fans + power-limit facts are
absent (`legion_laptop` loaded but not platform-bound), CPU temp falls back to
`acpitz` (no k10temp). amdgpu telemetry works. Guard for null and render `—`.
