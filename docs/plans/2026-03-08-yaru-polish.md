# Yaru Component Polish Pass — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace custom/Material widgets with Yaru primitives across all pages so every interaction feels native Ubuntu.

**Architecture:** UI-only refactor. No BLoC, state, or service changes. Each task targets one page (or shared components) and can be reviewed independently.

**Tech Stack:** `yaru: 9.0.1` (already installed)

---

## Audit Summary

| Page | Current | Yaru Upgrade Targets |
|---|---|---|
| **Shared** (`app_shell_components.dart`) | Custom `AppStatusBanner` | → `YaruBanner` |
| **Dashboard** | `_SectionGroupCard` with `Wrap` of `OutlinedButton` | → `YaruExpandable` |
| **Power** | `ListTile` for power limits | → `YaruTile` with action trailing |
| **Fans** | Raw `DataTable` in grey box | → `YaruBorderContainer` wrapper |
| **Battery** | `AppSwitchTile`, raw Material | → `YaruTile` subtitled status |
| **Display & Lighting** | `AppSwitchTile`, `Slider` | → `YaruTile`, grouped sections |
| **About** | Custom `_StatusLine` diagnostic rows | → `YaruTile` + `YaruInfoBadge` status dots |
| **About** | `_CommandHistoryTile` with `ExpansionTile` | → `YaruExpandable` |
| **Settings** | Minimal, already clean | → `YaruTile` for service rows |
| **Analytics** | Raw `Card`→`ListTile` sensor tiles | → `YaruBorderContainer` + `YaruTile` |
| **Automation** | Placeholder page | → Add `YaruBanner` empty-state |
| **Boot Logo** | Placeholder page | → Add `YaruBanner` empty-state |

---

### Task 1: Shared — Replace AppStatusBanner with YaruBanner

**Files:**
- Modify: `lib/core/widgets/app_shell_components.dart`

**Step 1: Replace `AppStatusBanner` implementation**

Replace the custom `Container` with `YaruBanner`, using `YaruBannerStyle.error` / `YaruBannerStyle.info`:

```dart
class AppStatusBanner extends StatelessWidget {
  // ...
  @override
  Widget build(BuildContext context) {
    return YaruBanner(
      name: Text(message),
      icon: Icon(tone == AppStatusTone.error ? Icons.error_outline : Icons.info_outline),
      watermark: true,
    );
  }
}
```

**Step 2: Run tests, then commit**

```bash
flutter test && flutter analyze --no-fatal-infos
git commit -am "refactor(ui): replace AppStatusBanner with YaruBanner"
```

---

### Task 2: Dashboard — YaruExpandable nav groups

**Files:**
- Modify: `lib/features/dashboard/view/dashboard_page.dart`

Replace `_SectionGroupCard` (`YaruSection` + `Wrap<OutlinedButton>`) with `YaruExpandable`:

```dart
YaruExpandable(
  header: Text(group.title, style: textTheme.titleMedium),
  expandButtonPosition: YaruExpandableButtonPosition.end,
  isExpanded: true,
  child: Column(
    children: group.sections.map((s) => YaruTile(
      title: Text(s.label),
      leading: Icon(s.icon),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => onSectionTap(s),
    )).toList(),
  ),
)
```

**Step 2: Commit**

---

### Task 3: Power — YaruTile for power limits

**Files:**
- Modify: `lib/features/power/view/power_page.dart`

Replace raw `ListTile` (line 153) for each power limit with `YaruTile`:

```dart
YaruTile(
  title: Text(reading.spec.label),
  subtitle: Text('Current: ${reading.value} | Range: ${reading.spec.min}–${reading.spec.max}'),
  trailing: OutlinedButton(/*...*/),
)
```

**Step 2: Commit**

---

### Task 4: Fans — YaruBorderContainer around DataTable

**Files:**
- Modify: `lib/features/fans/view/fans_page.dart`

Wrap existing `DataTable` in `YaruBorderContainer` with semantic label:

```dart
YaruBorderContainer(
  child: SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: DataTable(/*existing*/),
  ),
)
```

**Step 2: Commit**

---

### Task 5: About — YaruTile + YaruInfoBadge diagnostics

**Files:**
- Modify: `lib/features/about/view/about_page.dart`

**5a:** Replace `_StatusLine` with `YaruTile` + leading `YaruInfoBadge`:

```dart
YaruTile(
  leading: YaruInfoBadge(color: statusColor),
  title: Text(item.label),
  subtitle: Text(item.secondaryLabel ?? ''),
)
```

**5b:** Replace `_CommandHistoryTile` `ExpansionTile` with `YaruExpandable`:

```dart
YaruExpandable(
  header: ListTile(title: Text(record.commandDisplay), subtitle: Text(_formatTime(record.timestamp))),
  child: /* existing content */,
)
```

**Step 3: Commit**

---

### Task 6: Analytics — YaruBorderContainer + YaruTile

**Files:**
- Modify: `lib/features/analytics/view/analytics_page.dart`

Replace `_SensorTile` `Card`→`ListTile` with `YaruTile`:

```dart
YaruTile(
  leading: Icon(icon),
  title: Text(label),
  trailing: Text(value, style: TextStyle(fontWeight: FontWeight.bold)),
)
```

Wrap each chart in `YaruBorderContainer`.

**Step 2: Commit**

---

### Task 7: Placeholder pages — YaruBanner empty states

**Files:**
- Modify: `lib/features/automation/view/automation_page.dart`
- Modify: `lib/features/boot_logo/view/boot_logo_page.dart`

Add a `YaruBanner` describing the upcoming feature:

```dart
YaruBanner(
  name: Text('Feature coming soon'),
  subtitle: Text('Automation rules will be available in a future release.'),
  icon: Icon(YaruIcons.gear_dots),
)
```

**Step 2: Commit**

---

### Task 8: Final verification

```bash
flutter test --reporter=expanded
flutter analyze --no-fatal-infos
bd close okf.20
```

---

## Verification Plan

### Automated Tests
- `flutter test` — all existing tests must pass (no BLoC or logic changes)
- `flutter analyze --no-fatal-infos` — zero errors/warnings

### Manual Verification
- Visual smoke test of each page to confirm Yaru widgets render correctly
