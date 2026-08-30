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
- **Errors use the shared modal dialog.** Pass `errorMessage` to `AppPageBody`;
  never add a snackbar, floating banner, or toast. Routine success is reflected
  by the updated control state rather than a global notice. Follow the
  [Error and Feedback Standard](error-and-feedback-standard.md).

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
- **`TelemetryHistoryCard`**
  ([features/analytics/view/widgets/telemetry_history_card.dart](../lib/features/analytics/view/widgets/telemetry_history_card.dart))
  is the shared time-series surface. Pass the surface's resolved accent into it;
  do not hardcode another chart or selector colour inside the card.
- Keep the standard Material `SegmentedButton` for compact series choices when
  they fit. At constrained widths, use `YaruPopupMenuButton`; selected popup
  checks inherit the same accent through `YaruCheckboxTheme`. Do not replace
  either with a custom segmented control merely to change its colour.
- Every displayed measurement needs a documented unit and meaning. Preserve
  sign conventions and provenance in labels or supporting copy when ambiguity
  is possible. For example, battery `power_now` is signed battery-side
  charge/discharge power, not CPU package power or wall power.
- Missing telemetry stays missing. Render `—` plus a concise explanation when
  useful; do not infer battery temperature, fabricate history, or substitute a
  related measurement without labeling it as such.

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

- Neutral colours are **theme-relative**
  (`scheme.onSurface.withValues(alpha: …)`) so light/dark both work. Named
  semantic and vendor colours are the exception; resolve them once at the
  surface instead of scattering raw hex values through child components.
- Muted hierarchy: **0.7** (label/caption) · **0.56** (subtitle/meta) ·
  **0.5** (micro label) · **0.08** (track/hairline).
- The default page accent comes from
  [`LegionAccent.fromPowerModeValue`](../lib/core/theme/legion_accent.dart)
  (quiet=teal, balanced=green, performance=orange, custom=violet). Thread the
  resolved `Color accent` into cards. A deliberately semantic surface may own a
  stable accent instead, such as Battery green, but it must still have one
  authoritative resolved colour.
- Accent colours describe real state, not page identity. In particular, Custom
  violet belongs to an explicitly custom or dirty value; do not tint a whole
  settings page violet merely because it contains advanced controls.
- Keep one authoritative accent source per surface. Avoid a page-level hardcode
  combined with component-specific overrides that can disagree.
- A nested `ColorScheme.copyWith(primary: …)` does not rebuild Yaru's generated
  component subthemes. When a chip or another generated component needs a
  semantic state colour, set that component's selected properties directly and
  leave its inactive appearance to the Yaru theme.

Keep these colour roles separate:

| Role | Purpose | Example |
|---|---|---|
| Interaction accent | Selected controls, chart series, focus | Current power-mode accent or the surface's explicit semantic accent |
| Semantic status | A proven state or consequence | Active green, warning, destructive error |
| Vendor identity | Hardware manufacturer recognition only | NVIDIA/AMD/Intel mark in a device identity header |

A vendor colour must not tint the page's selectors, switches, chart, or
destructive actions. Likewise, an `Active` badge remains a semantic status even
when the current interaction accent is another colour.

## Icons

Use **`YaruIcons.*`**, not Material `Icons.*`, for generic navigation and action
icons so the app stays Yaru-native. The nav rail already does this via each
section's `yaruIcon`.

Known hardware identity is the exception: show the detected manufacturer's
mark rather than a decorative generic chip glyph. Use a neutral container, keep
the mark in its vendor colour, provide a semantic label, and retain a subdued
generic GPU/device fallback for unknown names. Vendor-aware presentation does
not claim backend support for that vendor; capability remains a separate fact.
See [GPU vendor asset provenance](../assets/gpu_vendors/README.md).

## 6. Capability and state truth

- Discover backend capabilities before designing or enabling controls. Test the
  actual combinations the backend can return, including partial and entirely
  absent support, rather than relying only on fully populated mocks.
- Never invent hardware values or draw a plausible curve when the driver did
  not provide one. Preserve nullable states through the repository, bloc, and
  widget layers.
- Model first load separately from an empty result. Until the first snapshot or
  first failed attempt completes, show a loading state; do not briefly render
  zeros, `—`, or an empty process list as if they were observed hardware state.
- Recommendation, explicit selection, successful application, and confirmed
  hardware-active state are different concepts. Name and render only the state
  the backend can prove; a recommendation must not silently become selected,
  and a successful command must not be presented as persistent hardware state
  without a readback API.
- Hide unsupported secondary controls. For the primary unavailable feature,
  show a compact explanation alongside any truthful telemetry that remains;
  do not leave a large disabled mock interface in place.
- The shell owns the page name and refresh action. Do not duplicate either in
  page content unless the content has a separate, meaningful section identity.
- Prefer native Yaru controls and their established interaction states before
  building custom equivalents.

## 7. Privileged actions

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

- Keep authentication and save-work guidance compact and legible. It supports
  the task; it should not visually outweigh the action being explained.
- Reserve `colorScheme.error` for the destructive control and consequence, not
  the whole card. Destructive controls remain outlined unless there is a clear
  reason to make destruction the primary action.
- Confirmation copy names the exact targets when known (for example PIDs and a
  PCI address), explains likely data loss or interruption, and uses a specific
  action label.
- UI preflight checks are not a security boundary. The privileged backend must
  atomically revalidate mutable targets immediately before acting; disabling a
  button or refreshing a process list only improves the frontend flow.
- A failed privileged action follows the
  [Error and Feedback Standard](error-and-feedback-standard.md): explain what
  failed, whether anything changed, why it failed when classified, and how to
  recover. Keep raw tool output selectable under technical details.

## 8. Shell & platform

- Window is a rounded GNOME/Handy window via **handy_window**
  ([linux/runner/my_application.cc](../linux/runner/my_application.cc) registers
  plugins before showing the view).
- Section title bar: left-aligned (`centerTitle: false`), section-specific
  actions via `_titleBarActions`.

## 9. Tooling & process

- **Flutter is not on PATH** — run via the nix flake:
  `nix develop /home/prnice/Projects/personal/nix_flakes/flutter_flake --command bash -c "cd <repo> && flutter test"`.
- **`dart format` only the files you edited** — never `dart format lib` (the
  flake's formatter churns unrelated files).
- **TDD for logic** (red→green). Declarative styling/config is exempt, but lock
  real invariants (e.g. the mono-font test).
- Treat the visual handoff as the starting authority, then reconcile it with
  established shell behaviour, proven backend capability, and direct review.
  Reuse an app-wide accent or native control rather than preserving an isolated
  mockup detail that makes one page disagree with the rest of the application.
- Verify each change: `flutter analyze` clean + `flutter test` green before
  committing.

## 10. Known data gaps (dev machine)

Fans and power-limit facts are absent because the active NixOS configuration
pins a pre-Kernel-7 `legion_laptop`; this is a known deployment problem rather
than a reason to fabricate UI data. See
[the Kernel 7 fan-controller handoff](architecture/fan-controller-kernel-7-handoff.md).
CPU temp falls back to `acpitz` (no k10temp), while amdgpu telemetry works.
Guard for null and render `—`.
