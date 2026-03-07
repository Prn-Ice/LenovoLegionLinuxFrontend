# Refresh Rate Switching Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a Refresh Rate section to the Display & Lighting page that queries available rates via xrandr and applies the selected rate to the built-in display.

**Architecture:** xrandr is unprivileged and cannot route through `LegionCliService` (hardcoded to `legion_cli` binary) or `LegionFrontendBridgeService` (routes through `pkexec`). A new `XrandrService` calls `Process.run('xrandr', ...)` directly. The service exposes a static `parseOutput()` method for unit-testable parsing. The feature plugs into the existing `DisplayLighting` BLoC by adding three new state fields (`xrandrOutputName`, `availableRefreshRates`, `currentRefreshRate`) and one new event (`RefreshRateSetRequested`). The UI adds a "Refresh Rate" `AppSectionCard` with `YaruRadioListTile<double>` tiles between Overdrive and Lighting. When xrandr is unavailable (Wayland, no X11), all three state fields are `null` and the section shows an unavailability notice — no crash.

**Tech Stack:** Dart/Flutter, riverbloc (flutter_bloc wrapper), flutter_riverpod, flutter_test, Yaru widgets, `dart:io` `Process.run`.

**Bead:** LenovoLegionLinux-4cq

**IMPORTANT — direnv:** The project uses direnv to activate Flutter via a Nix flake. Always `cd` to the project root (`frontend/legion_frontend` or the repo root) before running Flutter commands so direnv can set `PATH`. Never try to invoke `flutter` without first `cd`-ing into the project.

---

## Layer Map (read this before starting)

The refresh rate feature spans 7 layers:

```
XrandrService (new — Process.run xrandr)
  → DisplayLightingSnapshot (new fields)
    → DisplayLightingState (new fields + _unset sentinel)
      → DisplayLightingEvent (new RefreshRateSetRequested)
        → DisplayLightingRepository (new dep + methods)
          → providers (new xrandrServiceProvider, updated repo provider)
            → DisplayLightingBloc (new handler, _reloadState wiring)
              → DisplayLightingPage (new Refresh Rate section)
```

Tasks map to these layers in order.

---

## Task 1: Write failing state tests for new refresh rate fields

**Files:**
- Create: `test/features/display_lighting/display_lighting_state_test.dart`

### Step 1: Create test directory

```bash
cd /path/to/LenovoLegionLinux/frontend/legion_frontend
mkdir -p test/features/display_lighting
```

### Step 2: Write the failing tests

```dart
// test/features/display_lighting/display_lighting_state_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/display_lighting/bloc/display_lighting_state.dart';

void main() {
  group('DisplayLightingState refresh rate fields', () {
    test('initial state has all refresh rate fields as null', () {
      final state = DisplayLightingState.initial();
      expect(state.xrandrOutputName, isNull);
      expect(state.availableRefreshRates, isNull);
      expect(state.currentRefreshRate, isNull);
    });

    test('copyWith sets xrandrOutputName', () {
      final state = DisplayLightingState.initial().copyWith(
        xrandrOutputName: 'eDP-1',
      );
      expect(state.xrandrOutputName, equals('eDP-1'));
    });

    test('copyWith sets availableRefreshRates', () {
      final rates = [60.0, 120.0, 144.0];
      final state = DisplayLightingState.initial().copyWith(
        availableRefreshRates: rates,
      );
      expect(state.availableRefreshRates, equals(rates));
    });

    test('copyWith sets currentRefreshRate', () {
      final state = DisplayLightingState.initial().copyWith(
        currentRefreshRate: 144.0,
      );
      expect(state.currentRefreshRate, equals(144.0));
    });

    test('copyWith with no refresh rate args preserves existing values', () {
      final rates = [60.0, 120.0];
      final base = DisplayLightingState.initial().copyWith(
        xrandrOutputName: 'eDP-1',
        availableRefreshRates: rates,
        currentRefreshRate: 60.0,
      );
      final updated = base.copyWith(isLoading: false);
      expect(updated.xrandrOutputName, equals('eDP-1'));
      expect(updated.availableRefreshRates, equals(rates));
      expect(updated.currentRefreshRate, equals(60.0));
    });

    test('copyWith can reset refresh rate fields to null', () {
      final base = DisplayLightingState.initial().copyWith(
        xrandrOutputName: 'eDP-1',
        currentRefreshRate: 60.0,
      );
      final reset = base.copyWith(
        xrandrOutputName: null,
        currentRefreshRate: null,
      );
      expect(reset.xrandrOutputName, isNull);
      expect(reset.currentRefreshRate, isNull);
    });

    test('props distinguishes different currentRefreshRate', () {
      final s1 = DisplayLightingState.initial().copyWith(
        currentRefreshRate: 60.0,
      );
      final s2 = DisplayLightingState.initial().copyWith(
        currentRefreshRate: 144.0,
      );
      expect(s1, isNot(equals(s2)));
    });
  });
}
```

### Step 3: Run to confirm failure

```bash
cd frontend/legion_frontend
flutter test test/features/display_lighting/display_lighting_state_test.dart
```

Expected: FAIL — `The getter 'xrandrOutputName' isn't defined for the type 'DisplayLightingState'`

---

## Task 2: Add refresh rate fields to snapshot, state, and event

**Files:**
- Modify: `lib/features/display_lighting/models/display_lighting_snapshot.dart`
- Modify: `lib/features/display_lighting/bloc/display_lighting_state.dart`
- Modify: `lib/features/display_lighting/bloc/display_lighting_event.dart`

### Step 1: Update snapshot

In `display_lighting_snapshot.dart`, add three new required constructor parameters and field declarations after `ioPortLightEnabled`/`ioPortLightSupported`:

**Constructor parameters** (add after `required this.ioPortLightSupported,`):
```dart
required this.xrandrOutputName,
required this.availableRefreshRates,
required this.currentRefreshRate,
```

**Field declarations** (add after `final bool ioPortLightSupported;`):
```dart
final String? xrandrOutputName;
final List<double>? availableRefreshRates;
final double? currentRefreshRate;
```

### Step 2: Update state — five locations in `display_lighting_state.dart`

**a) Constructor parameters** — add after `required this.ioPortLightSupported,`:
```dart
required this.xrandrOutputName,
required this.availableRefreshRates,
required this.currentRefreshRate,
```

**b) Field declarations** — add after `final bool ioPortLightSupported;`:
```dart
final String? xrandrOutputName;
final List<double>? availableRefreshRates;
final double? currentRefreshRate;
```

**c) `initial()` factory** — add after `ioPortLightSupported: false,`:
```dart
xrandrOutputName: null,
availableRefreshRates: null,
currentRefreshRate: null,
```

**d) `copyWith` signature** — add after `bool? ioPortLightSupported,`:
```dart
Object? xrandrOutputName = _unset,
Object? availableRefreshRates = _unset,
Object? currentRefreshRate = _unset,
```

**e) `copyWith` body** — add after `ioPortLightSupported: ioPortLightSupported ?? this.ioPortLightSupported,`:
```dart
xrandrOutputName: xrandrOutputName == _unset
    ? this.xrandrOutputName
    : xrandrOutputName as String?,
availableRefreshRates: availableRefreshRates == _unset
    ? this.availableRefreshRates
    : availableRefreshRates as List<double>?,
currentRefreshRate: currentRefreshRate == _unset
    ? this.currentRefreshRate
    : currentRefreshRate as double?,
```

**f) `props` list** — add after `ioPortLightSupported,`:
```dart
xrandrOutputName,
availableRefreshRates,
currentRefreshRate,
```

Do NOT add the new fields to `hasLoaded`. xrandr availability is independent of whether the page has loaded — if xrandr is unavailable (Wayland), those fields stay null but the page still shows.

### Step 3: Add RefreshRateSetRequested event

In `display_lighting_event.dart`, add at the end:

```dart
final class RefreshRateSetRequested extends DisplayLightingEvent {
  const RefreshRateSetRequested(this.rate);

  final double rate;

  @override
  List<Object?> get props => [rate];
}
```

### Step 4: Run state tests — they should now pass

```bash
cd frontend/legion_frontend
flutter test test/features/display_lighting/display_lighting_state_test.dart
```

Expected: PASS (6 tests)

### Step 5: Analyze display_lighting feature

```bash
cd frontend/legion_frontend
flutter analyze lib/features/display_lighting/
```

Fix any missing constructor arguments in snapshot-related code before continuing.

### Step 6: Commit

```bash
cd frontend/legion_frontend
git add lib/features/display_lighting/models/display_lighting_snapshot.dart \
        lib/features/display_lighting/bloc/display_lighting_state.dart \
        lib/features/display_lighting/bloc/display_lighting_event.dart \
        test/features/display_lighting/display_lighting_state_test.dart
git commit -m "feat(display-lighting): add refresh rate fields to snapshot, state, and event"
```

---

## Task 3: Create XrandrService with unit tests

**Files:**
- Create: `lib/core/services/xrandr_service.dart`
- Create: `test/core/services/xrandr_service_test.dart`

### Step 1: Create the test file first

```dart
// test/core/services/xrandr_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/services/xrandr_service.dart';

// Sample xrandr --query outputs for testing
const _singleEdpOutput = '''
Screen 0: minimum 320 x 200, current 1920 x 1080, maximum 16384 x 16384
eDP-1 connected primary 1920x1080+0+0 (normal left inverted right x axis y axis) 340mm x 190mm
   1920x1080     60.00*+  120.00   144.00
   1280x720      60.00
HDMI-1 disconnected (normal left inverted right x axis y axis)
''';

const _edpAtHighRate = '''
Screen 0: minimum 320 x 200, current 1920 x 1080, maximum 16384 x 16384
eDP-1 connected primary 1920x1080+0+0 (normal left inverted right x axis y axis) 340mm x 190mm
   1920x1080     60.00+   120.00   144.00*
''';

const _noConnectedEdp = '''
Screen 0: minimum 320 x 200, current 1920 x 1080, maximum 16384 x 16384
eDP-1 disconnected (normal left inverted right x axis y axis)
HDMI-1 connected 1920x1080+0+0 (normal left inverted right x axis y axis) 530mm x 300mm
   1920x1080     60.00*+
''';

const _emptyOutput = '';

void main() {
  group('XrandrService.parseOutput', () {
    test('parses eDP-1 with multiple rates and identifies current rate', () {
      final info = XrandrService.parseOutput(_singleEdpOutput);
      expect(info, isNotNull);
      expect(info!.outputName, equals('eDP-1'));
      expect(info.currentRate, equals(60.0));
      expect(info.availableRates, containsAll([60.0, 120.0, 144.0]));
      expect(info.availableRates.length, equals(3));
    });

    test('identifies current rate at higher value', () {
      final info = XrandrService.parseOutput(_edpAtHighRate);
      expect(info, isNotNull);
      expect(info!.currentRate, equals(144.0));
      expect(info.availableRates, containsAll([60.0, 120.0, 144.0]));
    });

    test('returns null when no eDP output is connected', () {
      final info = XrandrService.parseOutput(_noConnectedEdp);
      expect(info, isNull);
    });

    test('returns null for empty output', () {
      final info = XrandrService.parseOutput(_emptyOutput);
      expect(info, isNull);
    });
  });
}
```

### Step 2: Run tests to confirm failure

```bash
cd frontend/legion_frontend
flutter test test/core/services/xrandr_service_test.dart
```

Expected: FAIL — `'xrandr_service.dart' not found`

### Step 3: Create the service

Create `lib/core/services/xrandr_service.dart`:

```dart
import 'dart:io';

class XrandrServiceException implements Exception {
  const XrandrServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

class XrandrDisplayInfo {
  const XrandrDisplayInfo({
    required this.outputName,
    required this.availableRates,
    required this.currentRate,
  });

  final String outputName;
  final List<double> availableRates;
  final double currentRate;
}

class XrandrService {
  /// Queries xrandr and returns display info for the built-in eDP output.
  /// Returns null if xrandr is unavailable (e.g. Wayland) or no eDP output
  /// is connected.
  Future<XrandrDisplayInfo?> queryBuiltInDisplay() async {
    try {
      final result = await Process.run('xrandr', ['--query']);
      if (result.exitCode != 0) {
        return null;
      }
      return parseOutput(result.stdout as String);
    } catch (_) {
      return null;
    }
  }

  /// Sets the refresh rate on [outputName] to [rate] Hz.
  /// Throws [XrandrServiceException] if xrandr exits non-zero.
  Future<void> setRefreshRate(String outputName, double rate) async {
    final rateStr = rate.toStringAsFixed(2);
    final result = await Process.run(
      'xrandr',
      ['--output', outputName, '--rate', rateStr],
    );
    if (result.exitCode != 0) {
      throw XrandrServiceException(
        'xrandr failed: ${result.stderr}'.trim(),
      );
    }
  }

  /// Parses `xrandr --query` output and returns display info for the first
  /// connected eDP output that has an active mode (marked with `*`).
  ///
  /// Visible for testing.
  static XrandrDisplayInfo? parseOutput(String output) {
    final lines = output.split('\n');
    final edpPattern = RegExp(r'^(eDP[-\w]+)\s+connected');
    // Mode lines: leading whitespace, then resolution (e.g. "   1920x1080")
    final modeLinePattern = RegExp(r'^\s+(\d+x\d+)\s+(.+)$');
    final ratePattern = RegExp(r'([\d.]+)([*+]*)');

    String? outputName;
    bool inEdpBlock = false;

    for (final line in lines) {
      if (!inEdpBlock) {
        final match = edpPattern.firstMatch(line);
        if (match != null) {
          outputName = match.group(1);
          inEdpBlock = true;
        }
        continue;
      }

      // Inside the eDP mode block
      final modeMatch = modeLinePattern.firstMatch(line);
      if (modeMatch == null) {
        // Hit a non-mode line (next output or blank) — exit block
        break;
      }

      if (!line.contains('*')) {
        continue; // Not the active mode line
      }

      // Parse rates from the portion after the resolution
      final ratePart = modeMatch.group(2)!;
      final rates = <double>[];
      double? currentRate;

      for (final m in ratePattern.allMatches(ratePart)) {
        final rate = double.tryParse(m.group(1)!);
        if (rate == null) continue;
        rates.add(rate);
        if (m.group(2)!.contains('*')) {
          currentRate = rate;
        }
      }

      if (currentRate != null && outputName != null && rates.isNotEmpty) {
        return XrandrDisplayInfo(
          outputName: outputName,
          availableRates: rates,
          currentRate: currentRate,
        );
      }

      break; // Found active mode line but couldn't parse — stop
    }

    return null;
  }
}
```

### Step 4: Run tests — they should pass

```bash
cd frontend/legion_frontend
flutter test test/core/services/xrandr_service_test.dart
```

Expected: PASS (4 tests)

### Step 5: Analyze

```bash
cd frontend/legion_frontend
flutter analyze lib/core/services/xrandr_service.dart
```

Expected: no issues

### Step 6: Commit

```bash
cd frontend/legion_frontend
git add lib/core/services/xrandr_service.dart \
        test/core/services/xrandr_service_test.dart
git commit -m "feat(xrandr): add XrandrService — xrandr output parser and rate setter"
```

---

## Task 4: Wire XrandrService into providers and repository

**Files:**
- Modify: `lib/core/providers/system_services_provider.dart`
- Modify: `lib/features/display_lighting/repository/display_lighting_repository.dart`
- Modify: `lib/features/display_lighting/providers/display_lighting_provider.dart`

### Step 1: Add xrandrServiceProvider to system_services_provider.dart

Add the import at the top:
```dart
import '../services/xrandr_service.dart';
```

Add the provider (after `legionBridgeServiceProvider`):
```dart
final xrandrServiceProvider = Provider<XrandrService>(
  (ref) => XrandrService(),
);
```

### Step 2: Update DisplayLightingRepository

In `display_lighting_repository.dart`:

**a) Add import** at the top:
```dart
import '../../../core/services/xrandr_service.dart';
```

**b) Add constructor parameter** (after `LegionFrontendBridgeService bridgeService`):
```dart
required XrandrService xrandrService,
```

And in the initializer list:
```dart
_xrandrService = xrandrService;
```

**c) Add field declaration** (after `final LegionFrontendBridgeService _bridgeService;`):
```dart
final XrandrService _xrandrService;
```

**d) Update `loadSnapshot()`** — add xrandr query after the existing sysfs reads:
```dart
final displayInfo = await _xrandrService.queryBuiltInDisplay();
```

Then in the `DisplayLightingSnapshot(...)` constructor call, add after `ioPortLightSupported:`:
```dart
xrandrOutputName: displayInfo?.outputName,
availableRefreshRates: displayInfo?.availableRates,
currentRefreshRate: displayInfo?.currentRate,
```

**e) Add `setRefreshRate` method** (after `setIoPortLight`):
```dart
Future<void> setRefreshRate(String outputName, double rate) async {
  try {
    await _xrandrService.setRefreshRate(outputName, rate);
  } on XrandrServiceException catch (error) {
    throw DisplayLightingRepositoryException('$error');
  }
}
```

### Step 3: Update displayLightingRepositoryProvider

In `display_lighting_provider.dart`:

**a) Add import**:
```dart
import '../../../core/providers/system_services_provider.dart';
```
(Check — it may already be imported via `system_services_provider.dart`.)

**b) Update the provider body** to pass `xrandrService`:
```dart
final displayLightingRepositoryProvider = Provider<DisplayLightingRepository>((
  ref,
) {
  final sysfsService = ref.watch(legionSysfsServiceProvider);
  final bridgeService = ref.watch(legionBridgeServiceProvider);
  final xrandrService = ref.watch(xrandrServiceProvider);

  return DisplayLightingRepository(
    sysfsService: sysfsService,
    bridgeService: bridgeService,
    xrandrService: xrandrService,
  );
});
```

You'll need to add an import for `xrandrServiceProvider`:
```dart
import '../../../core/providers/system_services_provider.dart';
```

### Step 4: Analyze

```bash
cd frontend/legion_frontend
flutter analyze lib/features/display_lighting/ lib/core/providers/ lib/core/services/
```

Expected: no issues

### Step 5: Commit

```bash
cd frontend/legion_frontend
git add lib/core/providers/system_services_provider.dart \
        lib/features/display_lighting/repository/display_lighting_repository.dart \
        lib/features/display_lighting/providers/display_lighting_provider.dart
git commit -m "feat(display-lighting): wire XrandrService into repository and providers"
```

---

## Task 5: Add RefreshRateSetRequested handler in bloc

**Files:**
- Modify: `lib/features/display_lighting/bloc/display_lighting_bloc.dart`

### Step 1: Register the handler in the constructor

After `on<IoPortLightSetRequested>(_onIoPortLightSetRequested);`, add:

```dart
on<RefreshRateSetRequested>(_onRefreshRateSetRequested);
```

### Step 2: Add handler method

After `_onIoPortLightSetRequested(...)`, add:

```dart
Future<void> _onRefreshRateSetRequested(
  RefreshRateSetRequested event,
  Emitter<DisplayLightingState> emit,
) async {
  final outputName = state.xrandrOutputName;
  if (state.isApplying || outputName == null) {
    return;
  }

  emit(
    state.copyWith(isApplying: true, errorMessage: null, noticeMessage: null),
  );

  try {
    await _repository.setRefreshRate(outputName, event.rate);
    await _reloadState(emit, showLoading: false);
    emit(
      state.copyWith(
        isApplying: false,
        noticeMessage: 'Refresh rate set to ${event.rate.round()} Hz.',
      ),
    );
  } catch (error) {
    emit(state.copyWith(isApplying: false, errorMessage: '$error'));
  }
}
```

### Step 3: Wire xrandr fields in `_reloadState`

In the `state.copyWith(...)` call inside `_reloadState`, add after `ioPortLightSupported: snapshot.ioPortLightSupported,`:

```dart
xrandrOutputName: snapshot.xrandrOutputName,
availableRefreshRates: snapshot.availableRefreshRates,
currentRefreshRate: snapshot.currentRefreshRate,
```

### Step 4: Analyze

```bash
cd frontend/legion_frontend
flutter analyze lib/features/display_lighting/bloc/display_lighting_bloc.dart
```

Expected: no issues

### Step 5: Commit

```bash
cd frontend/legion_frontend
git add lib/features/display_lighting/bloc/display_lighting_bloc.dart
git commit -m "feat(display-lighting): add RefreshRateSetRequested handler in DisplayLightingBloc"
```

---

## Task 6: Add Refresh Rate section to the UI

**Files:**
- Modify: `lib/features/display_lighting/view/display_lighting_page.dart`

### Step 1: Add yaru import if not already present

The file already has `import 'package:yaru/yaru.dart';` — no change needed.

### Step 2: Add the Refresh Rate section

Insert a new `AppSectionCard` between the Overdrive section and the Lighting section (after the `const SizedBox(height: 16),` that follows the Overdrive card, before the Lighting `AppSectionCard`).

The complete section to insert:

```dart
const SizedBox(height: 16),
AppSectionCard(
  title: 'Refresh Rate',
  description: 'Built-in display refresh rate (requires X11/xrandr).',
  children: [
    if (state.availableRefreshRates == null ||
        state.availableRefreshRates!.isEmpty)
      const ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text('Refresh rate switching'),
        subtitle: Text('Unavailable — xrandr not accessible on this session.'),
      )
    else
      ...state.availableRefreshRates!.map(
        (rate) => YaruRadioListTile<double>(
          contentPadding: EdgeInsets.zero,
          value: rate,
          groupValue: state.currentRefreshRate,
          onChanged: state.isApplying
              ? null
              : (_) => _setRefreshRate(bloc, rate),
          title: Text('${rate.round()} Hz'),
        ),
      ),
  ],
),
```

### Step 3: Add helper method

At the bottom of the class (after `_setIoPortLight`), add:

```dart
void _setRefreshRate(DisplayLightingBloc bloc, double rate) {
  bloc.add(RefreshRateSetRequested(rate));
}
```

### Step 4: Run all tests

```bash
cd frontend/legion_frontend
flutter test
```

Expected: PASS — all tests including the 6 new state tests and 4 xrandr service tests.

### Step 5: Run full analyze

```bash
cd frontend/legion_frontend
flutter analyze
```

Expected: no issues

### Step 6: Commit

```bash
cd frontend/legion_frontend
git add lib/features/display_lighting/view/display_lighting_page.dart
git commit -m "feat(display-lighting): add Refresh Rate section to Display & Lighting page

Closes LenovoLegionLinux-4cq"
```

---

## Verification Checklist

Before declaring done:

- [ ] `flutter test` — all tests pass (≥10 new tests across 2 new test files)
- [ ] `flutter analyze` — zero issues
- [ ] `XrandrService.parseOutput()` parses eDP output name, all available rates, and current rate correctly
- [ ] `DisplayLightingState.initial()` has `xrandrOutputName: null`, `availableRefreshRates: null`, `currentRefreshRate: null`
- [ ] `copyWith` with no xrandr args preserves existing values (sentinel pattern)
- [ ] `copyWith` with explicit `null` resets fields to null
- [ ] When xrandr returns `null` (Wayland), the UI shows an unavailability notice instead of crashing
- [ ] Rate tiles are disabled while `state.isApplying` is true
- [ ] No privilege dialog — xrandr is unprivileged and applies immediately on tap
- [ ] `RefreshRateSetRequested` handler returns early if `state.xrandrOutputName` is null
