# Yaru-Native UX Polish Design

**Date:** 2026-03-06
**Bead:** LenovoLegionLinux-okf.8 (Responsive UX polish — expanded scope)
**Approach:** A — Shell first, pages follow. Two commits, no PRs.

## Context

The app already applies `YaruTheme` correctly (colors, typography). The gap is structural: the navigation shell and page widgets use plain Material primitives instead of Yaru-native equivalents. This makes the app look themed but not native.

## Commit 1 — Navigation Shell

**File:** `lib/features/navigation/view/navigation_shell.dart`
**File:** `lib/main.dart` (add `YaruWindowTitleBar.ensureInitialized()`)

### Wide layout (≥ `kYaruMasterDetailBreakpoint`)

Replace `Scaffold` + `NavigationRail` with `YaruMasterDetailPage`:

- `paneLayoutDelegate`: `YaruResizablePaneDelegate(initialPaneSize: 280, minPaneSize: 175, minPageSize: kYaruMasterDetailBreakpoint / 2)`
- `tileBuilder`: `YaruMasterTile(leading: Icon(section.yaruIcon), title: Text(section.label))`
- `pageBuilder`: `YaruDetailPage(appBar: YaruWindowTitleBar(title: Text(section.label), border: BorderSide.none), body: _buildPage(section))`
- `appBar`: `YaruWindowTitleBar` on the sidebar pane (no title, holds window controls)

### Compact layout (< `kYaruMasterDetailBreakpoint`)

Replace `Scaffold` + `NavigationBar` with `YaruNavigationPage`:

- Rail style adapts: `labelledExtended` (> 1000px) → `labelled` (> 500px) → `compact`
- `itemBuilder`: `YaruNavigationRailItem(icon: Icon(section.yaruIcon), label: Text(section.label), style: style)`
- `appBar`: `YaruWindowTitleBar` showing current section title

### Icons

Add `yaruIcon` getter to `AppSection` mapping to `YaruIcons.*` equivalents:

| Section | YaruIcon |
|---|---|
| dashboard | `YaruIcons.dashboard` |
| power | `YaruIcons.power` |
| fans | `YaruIcons.fan` |
| battery | `YaruIcons.battery` |
| displayLighting | `YaruIcons.display` |
| automation | `YaruIcons.media_play` |
| settings | `YaruIcons.gear` |
| about | `YaruIcons.information` |

## Commit 2 — Shared Components & Page Widgets

### `lib/core/widgets/app_shell_components.dart`

| Current | Replacement |
|---|---|
| `Card` + manual padding in `AppSectionCard` | `YaruSection(headline: ..., child: Column(...))` |
| `SwitchListTile.adaptive` in `AppSwitchTile` | `YaruSwitchListTile` |
| `24` hardcoded padding in `AppPageBody` | `kYaruPagePadding` |
| `CircularProgressIndicator` in `AppRefreshButton` | `YaruCircularProgressIndicator` |

`AppStatusBanner` and `AppRefreshButton` (FilledButton.icon) stay as-is — no Yaru equivalent, current styling is correct.

### Per-page changes

**`power_page.dart`**
- `RadioListTile` → `YaruRadioListTile`
- `AlertDialog` for power limits: add `YaruDialogTitleBar` as `title`, set `titlePadding: EdgeInsets.zero`

**`dashboard_page.dart`**
- `ChoiceChip` power mode selector (Wrap of chips) → `YaruChoiceChipBar`

**All pages**
- `Center(child: CircularProgressIndicator())` loading states → `YaruCircularProgressIndicator`

### No changes

- BLoC / provider / repository layer — presentation only
- `AppStatusBanner` — custom styled container, no Yaru equivalent
- `AppRefreshButton` outer structure — `FilledButton.icon` is correct

## Success Criteria

- App uses `YaruMasterDetailPage` on wide screens, `YaruNavigationPage` on compact
- `YaruWindowTitleBar` present and shows section title
- No plain `NavigationRail`, `NavigationBar`, `SwitchListTile.adaptive`, or `RadioListTile` remaining
- All section icons from `YaruIcons`
- `kYaruPagePadding` used consistently in page bodies
