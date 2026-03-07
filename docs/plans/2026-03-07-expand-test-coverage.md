# Expand Automated Test Coverage — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add state model, bloc, and model/config test coverage for all implemented feature slices, closing the gaps left by the initial delivery tests.

**Architecture:** Pure Dart tests for state/model layers (no mocks needed). Bloc tests for synchronous event handlers using `mocktail` mock repositories. No widget tests in this pass — they require a running Flutter engine and inflate setup cost without proportionate value at this stage.

**Tech Stack:** `flutter_test`, `mocktail` (new dev dep), `bloc_test` (new dev dep), `riverbloc`

**NOTE:** The project uses direnv to activate Flutter. All `flutter` commands must be run from inside `/home/prnice/Projects/personal/LenovoLegionLinux/frontend/legion_frontend/` (or with `direnv exec . flutter ...` from the repo root).

---

### Task 1: Add mocktail and bloc_test dev dependencies

**Files:**
- Modify: `pubspec.yaml`

**Step 1: Add dev dependencies**

In `pubspec.yaml`, under `dev_dependencies:`, add:

```yaml
  mocktail: ^1.0.4
  bloc_test: ^10.0.0
```

**Step 2: Fetch packages**

```bash
cd frontend/legion_frontend
flutter pub get
```

Expected: resolves without error; `pubspec.lock` updated.

**Step 3: Verify the test suite still passes**

```bash
cd frontend/legion_frontend
flutter test
```

Expected: same count as before (no regressions).

**Step 4: Commit**

```bash
git add frontend/legion_frontend/pubspec.yaml frontend/legion_frontend/pubspec.lock
git commit -m "chore: add mocktail and bloc_test dev dependencies"
```

---

### Task 2: FansState model tests

**Files:**
- Create: `test/features/fans/fans_state_test.dart`

**Step 1: Write the test file**

```dart
// test/features/fans/fans_state_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/fans/bloc/fans_state.dart';
import 'package:legion_frontend/features/fans/models/fan_curve.dart';

FanCurve _curve(String name) => FanCurve(
  name: name,
  points: List.generate(
    10,
    (_) => const FanCurvePoint(
      fan1Rpm: 1200,
      fan2Rpm: 1200,
      cpuLowerTemp: 40,
      cpuUpperTemp: 50,
      gpuLowerTemp: 40,
      gpuUpperTemp: 50,
      icLowerTemp: 40,
      icUpperTemp: 50,
      accel: 5,
      decel: 5,
    ),
  ),
);

void main() {
  group('FansState.initial', () {
    test('all nullable fields are null', () {
      final s = FansState.initial();
      expect(s.platformProfile, isNull);
      expect(s.onPowerSupply, isNull);
      expect(s.recommendedPreset, isNull);
      expect(s.selectedPreset, isNull);
      expect(s.miniFanCurveEnabled, isNull);
      expect(s.lockFanControllerEnabled, isNull);
      expect(s.maximumFanSpeedEnabled, isNull);
      expect(s.fanCurve, isNull);
      expect(s.errorMessage, isNull);
      expect(s.noticeMessage, isNull);
    });

    test('availablePresets is empty', () {
      expect(FansState.initial().availablePresets, isEmpty);
    });

    test('fanCurveDirty is false', () {
      expect(FansState.initial().fanCurveDirty, isFalse);
    });

    test('hasLoaded is false', () {
      expect(FansState.initial().hasLoaded, isFalse);
    });
  });

  group('FansState.hasLoaded', () {
    test('true when platformProfile is set', () {
      final s = FansState.initial().copyWith(platformProfile: 'balanced');
      expect(s.hasLoaded, isTrue);
    });

    test('true when miniFanCurveEnabled is set', () {
      final s = FansState.initial().copyWith(miniFanCurveEnabled: false);
      expect(s.hasLoaded, isTrue);
    });

    test('true when fanCurve is set', () {
      final s = FansState.initial().copyWith(fanCurve: _curve('test'));
      expect(s.hasLoaded, isTrue);
    });

    test('true when availablePresets is non-empty', () {
      final s = FansState.initial().copyWith(availablePresets: ['quiet-ac']);
      expect(s.hasLoaded, isTrue);
    });
  });

  group('FansState.copyWith sentinel (_unset)', () {
    test('copyWith with no args returns equal state', () {
      final s = FansState.initial();
      expect(s.copyWith(), equals(s));
    });

    test('copyWith(platformProfile: null) clears field', () {
      final s = FansState.initial()
          .copyWith(platformProfile: 'balanced')
          .copyWith(platformProfile: null);
      expect(s.platformProfile, isNull);
    });

    test('copyWith omitting platformProfile preserves it', () {
      final s = FansState.initial().copyWith(platformProfile: 'quiet');
      final updated = s.copyWith(isLoading: true);
      expect(updated.platformProfile, equals('quiet'));
    });

    test('copyWith(fanCurve: null) clears fanCurve', () {
      final s = FansState.initial()
          .copyWith(fanCurve: _curve('x'))
          .copyWith(fanCurve: null);
      expect(s.fanCurve, isNull);
    });

    test('copyWith omitting fanCurve preserves it', () {
      final curve = _curve('y');
      final s = FansState.initial().copyWith(fanCurve: curve);
      expect(s.copyWith(isLoading: true).fanCurve, equals(curve));
    });

    test('copyWith(errorMessage: null) clears error', () {
      final s = FansState.initial()
          .copyWith(errorMessage: 'oops')
          .copyWith(errorMessage: null);
      expect(s.errorMessage, isNull);
    });
  });

  group('FansState.fanCurveDirty', () {
    test('copyWith(fanCurveDirty: true) sets it', () {
      final s = FansState.initial().copyWith(fanCurveDirty: true);
      expect(s.fanCurveDirty, isTrue);
    });

    test('copyWith omitting fanCurveDirty preserves it', () {
      final s = FansState.initial()
          .copyWith(fanCurveDirty: true)
          .copyWith(isLoading: true);
      expect(s.fanCurveDirty, isTrue);
    });
  });

  group('FansState props', () {
    test('identical states are equal', () {
      expect(FansState.initial(), equals(FansState.initial()));
    });

    test('states differ when fanCurveDirty differs', () {
      final a = FansState.initial();
      final b = a.copyWith(fanCurveDirty: true);
      expect(a, isNot(equals(b)));
    });

    test('states differ when fanCurve differs', () {
      final a = FansState.initial().copyWith(fanCurve: _curve('a'));
      final b = FansState.initial().copyWith(fanCurve: _curve('b'));
      expect(a, isNot(equals(b)));
    });
  });
}
```

**Step 2: Run tests**

```bash
cd frontend/legion_frontend
flutter test test/features/fans/fans_state_test.dart -v
```

Expected: all tests pass (aim for 18+ tests).

**Step 3: Commit**

```bash
git add test/features/fans/fans_state_test.dart
git commit -m "test: add FansState model tests (copyWith sentinel, hasLoaded, fanCurveDirty)"
```

---

### Task 3: PowerState and PowerMode model tests

**Files:**
- Create: `test/features/power/power_state_test.dart`

**Step 1: Write the test file**

```dart
// test/features/power/power_state_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/power/bloc/power_state.dart';
import 'package:legion_frontend/features/power/models/power_mode.dart';
import 'package:legion_frontend/features/power/models/power_limit.dart';

void main() {
  group('PowerMode', () {
    test('fromRaw strips brackets', () {
      final mode = PowerMode.fromRaw('[balanced]');
      expect(mode.value, equals('balanced'));
    });

    test('fromRaw handles value without brackets', () {
      final mode = PowerMode.fromRaw('quiet');
      expect(mode.value, equals('quiet'));
    });

    test('label returns human-readable string for known values', () {
      expect(PowerMode('quiet').label, equals('Quiet'));
      expect(PowerMode('balanced').label, equals('Balanced'));
      expect(PowerMode('performance').label, equals('Performance'));
      expect(PowerMode('balanced-performance').label, equals('Custom'));
    });

    test('label returns raw value for unknown modes', () {
      expect(PowerMode('ultra').label, equals('ultra'));
    });

    test('equality based on value', () {
      expect(PowerMode('quiet'), equals(PowerMode('quiet')));
      expect(PowerMode('quiet'), isNot(equals(PowerMode('balanced'))));
    });
  });

  group('PowerState.initial', () {
    test('currentMode is null', () {
      expect(PowerState.initial().currentMode, isNull);
    });

    test('availableModes and powerLimits are empty', () {
      expect(PowerState.initial().availableModes, isEmpty);
      expect(PowerState.initial().powerLimits, isEmpty);
    });

    test('hasLoaded is false', () {
      expect(PowerState.initial().hasLoaded, isFalse);
    });
  });

  group('PowerState.hasLoaded', () {
    test('true when currentMode is set', () {
      final s = PowerState.initial().copyWith(
        currentMode: const PowerMode('balanced'),
      );
      expect(s.hasLoaded, isTrue);
    });

    test('true when availableModes is non-empty', () {
      final s = PowerState.initial().copyWith(
        availableModes: [const PowerMode('quiet')],
      );
      expect(s.hasLoaded, isTrue);
    });

    test('true when cpuOverclockEnabled is set', () {
      final s = PowerState.initial().copyWith(cpuOverclockEnabled: false);
      expect(s.hasLoaded, isTrue);
    });
  });

  group('PowerState.copyWith sentinel', () {
    test('copyWith with no args returns equal state', () {
      expect(PowerState.initial().copyWith(), equals(PowerState.initial()));
    });

    test('copyWith(currentMode: null) clears mode', () {
      final s = PowerState.initial()
          .copyWith(currentMode: const PowerMode('quiet'))
          .copyWith(currentMode: null);
      expect(s.currentMode, isNull);
    });

    test('copyWith omitting currentMode preserves it', () {
      final mode = const PowerMode('performance');
      final s = PowerState.initial()
          .copyWith(currentMode: mode)
          .copyWith(isLoading: true);
      expect(s.currentMode, equals(mode));
    });

    test('copyWith(errorMessage: null) clears it', () {
      final s = PowerState.initial()
          .copyWith(errorMessage: 'err')
          .copyWith(errorMessage: null);
      expect(s.errorMessage, isNull);
    });
  });

  group('PowerState props', () {
    test('identical initial states are equal', () {
      expect(PowerState.initial(), equals(PowerState.initial()));
    });

    test('differ by currentMode', () {
      final a = PowerState.initial().copyWith(
        currentMode: const PowerMode('quiet'),
      );
      final b = PowerState.initial().copyWith(
        currentMode: const PowerMode('balanced'),
      );
      expect(a, isNot(equals(b)));
    });
  });
}
```

**Step 2: Run tests**

```bash
cd frontend/legion_frontend
flutter test test/features/power/power_state_test.dart -v
```

Expected: all tests pass.

**Step 3: Commit**

```bash
git add test/features/power/power_state_test.dart
git commit -m "test: add PowerState and PowerMode model tests"
```

---

### Task 4: AutomationConfig and AutomationState tests

**Files:**
- Create: `test/features/automation/automation_config_test.dart`
- Create: `test/features/automation/automation_state_test.dart`

**Step 1: Write automation_config_test.dart**

```dart
// test/features/automation/automation_config_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/automation/models/automation_config.dart';

void main() {
  group('AutomationConfig.defaults', () {
    test('runnerEnabled is false', () {
      expect(AutomationConfig.defaults().runnerEnabled, isFalse);
    });

    test('pollIntervalSeconds is 10', () {
      expect(AutomationConfig.defaults().pollIntervalSeconds, equals(10));
    });

    test('conservationLowerLimit is 60, upperLimit is 80', () {
      final d = AutomationConfig.defaults();
      expect(d.conservationLowerLimit, equals(60));
      expect(d.conservationUpperLimit, equals(80));
    });

    test('hasValidConservationRange is true', () {
      expect(AutomationConfig.defaults().hasValidConservationRange, isTrue);
    });
  });

  group('AutomationConfig.fromJson', () {
    test('uses defaults for missing keys', () {
      final c = AutomationConfig.fromJson({});
      expect(c.runnerEnabled, equals(AutomationConfig.defaults().runnerEnabled));
      expect(
        c.pollIntervalSeconds,
        equals(AutomationConfig.defaults().pollIntervalSeconds),
      );
    });

    test('reads runnerEnabled from bool', () {
      final c = AutomationConfig.fromJson({'runnerEnabled': true});
      expect(c.runnerEnabled, isTrue);
    });

    test('ignores non-bool value for runnerEnabled', () {
      final c = AutomationConfig.fromJson({'runnerEnabled': 'yes'});
      expect(c.runnerEnabled, equals(AutomationConfig.defaults().runnerEnabled));
    });

    test('reads pollIntervalSeconds from int', () {
      final c = AutomationConfig.fromJson({'pollIntervalSeconds': 30});
      expect(c.pollIntervalSeconds, equals(30));
    });

    test('reads pollIntervalSeconds from numeric string', () {
      final c = AutomationConfig.fromJson({'pollIntervalSeconds': '60'});
      expect(c.pollIntervalSeconds, equals(60));
    });

    test('clamps pollIntervalSeconds below minimum to 2', () {
      final c = AutomationConfig.fromJson({'pollIntervalSeconds': 1});
      expect(c.pollIntervalSeconds, equals(2));
    });

    test('clamps pollIntervalSeconds above maximum to 300', () {
      final c = AutomationConfig.fromJson({'pollIntervalSeconds': 9999});
      expect(c.pollIntervalSeconds, equals(300));
    });

    test('clamps conservationLowerLimit to [0, 100]', () {
      final low = AutomationConfig.fromJson({'conservationLowerLimit': -5});
      expect(low.conservationLowerLimit, equals(0));
      final high = AutomationConfig.fromJson({'conservationLowerLimit': 200});
      expect(high.conservationLowerLimit, equals(100));
    });

    test('reads all boolean fields correctly', () {
      final c = AutomationConfig.fromJson({
        'applyFanPresetOnContextChange': false,
        'triggerOnProfileChange': false,
        'triggerOnPowerSourceChange': true,
        'applyCustomConservation': true,
        'applyRapidChargingPolicy': true,
        'rapidChargingOnAc': false,
        'rapidChargingOnBattery': true,
      });
      expect(c.applyFanPresetOnContextChange, isFalse);
      expect(c.triggerOnProfileChange, isFalse);
      expect(c.triggerOnPowerSourceChange, isTrue);
      expect(c.applyCustomConservation, isTrue);
      expect(c.applyRapidChargingPolicy, isTrue);
      expect(c.rapidChargingOnAc, isFalse);
      expect(c.rapidChargingOnBattery, isTrue);
    });
  });

  group('AutomationConfig.copyWith', () {
    test('copyWith(pollIntervalSeconds: 1) clamps to 2', () {
      final c = AutomationConfig.defaults().copyWith(pollIntervalSeconds: 1);
      expect(c.pollIntervalSeconds, equals(2));
    });

    test('copyWith preserves unchanged fields', () {
      final c = AutomationConfig.defaults().copyWith(runnerEnabled: true);
      expect(c.pollIntervalSeconds, equals(10));
    });
  });

  group('AutomationConfig.hasValidConservationRange', () {
    test('true when lower <= upper', () {
      final c = AutomationConfig.defaults().copyWith(
        conservationLowerLimit: 60,
        conservationUpperLimit: 80,
      );
      expect(c.hasValidConservationRange, isTrue);
    });

    test('true when lower == upper', () {
      final c = AutomationConfig.defaults().copyWith(
        conservationLowerLimit: 70,
        conservationUpperLimit: 70,
      );
      expect(c.hasValidConservationRange, isTrue);
    });

    test('false when lower > upper', () {
      final c = AutomationConfig.defaults().copyWith(
        conservationLowerLimit: 90,
        conservationUpperLimit: 60,
      );
      expect(c.hasValidConservationRange, isFalse);
    });
  });
}
```

**Step 2: Write automation_state_test.dart**

```dart
// test/features/automation/automation_state_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/automation/bloc/automation_state.dart';
import 'package:legion_frontend/features/automation/models/automation_config.dart';

void main() {
  group('AutomationState.initial', () {
    test('isLoading and isExecuting are false', () {
      final s = AutomationState.initial();
      expect(s.isLoading, isFalse);
      expect(s.isExecuting, isFalse);
    });

    test('currentSnapshot and lastRunAt are null', () {
      final s = AutomationState.initial();
      expect(s.currentSnapshot, isNull);
      expect(s.lastRunAt, isNull);
    });

    test('config is defaults', () {
      expect(
        AutomationState.initial().config,
        equals(AutomationConfig.defaults()),
      );
    });
  });

  group('AutomationState.isRunnerActive', () {
    test('false when config.runnerEnabled is false', () {
      expect(AutomationState.initial().isRunnerActive, isFalse);
    });

    test('true when config.runnerEnabled is true', () {
      final s = AutomationState.initial().copyWith(
        config: AutomationConfig.defaults().copyWith(runnerEnabled: true),
      );
      expect(s.isRunnerActive, isTrue);
    });
  });

  group('AutomationState.copyWith sentinel', () {
    test('copyWith with no args returns equal state', () {
      expect(
        AutomationState.initial().copyWith(),
        equals(AutomationState.initial()),
      );
    });

    test('copyWith(errorMessage: null) clears it', () {
      final s = AutomationState.initial()
          .copyWith(errorMessage: 'bad')
          .copyWith(errorMessage: null);
      expect(s.errorMessage, isNull);
    });

    test('copyWith omitting errorMessage preserves it', () {
      final s = AutomationState.initial()
          .copyWith(errorMessage: 'err')
          .copyWith(isLoading: true);
      expect(s.errorMessage, equals('err'));
    });

    test('copyWith(lastRunAt: null) clears DateTime', () {
      final now = DateTime.now();
      final s = AutomationState.initial()
          .copyWith(lastRunAt: now)
          .copyWith(lastRunAt: null);
      expect(s.lastRunAt, isNull);
    });
  });

  group('AutomationState props', () {
    test('identical initial states are equal', () {
      expect(AutomationState.initial(), equals(AutomationState.initial()));
    });

    test('differ when isExecuting differs', () {
      final a = AutomationState.initial();
      final b = a.copyWith(isExecuting: true);
      expect(a, isNot(equals(b)));
    });
  });
}
```

**Step 3: Run tests**

```bash
cd frontend/legion_frontend
flutter test test/features/automation/ -v
```

Expected: all tests pass.

**Step 4: Commit**

```bash
git add test/features/automation/automation_config_test.dart test/features/automation/automation_state_test.dart
git commit -m "test: add AutomationConfig.fromJson and AutomationState model tests"
```

---

### Task 5: SettingsState and DashboardState tests

**Files:**
- Create: `test/features/settings/settings_state_test.dart`
- Create: `test/features/dashboard/dashboard_state_test.dart`

**Step 1: Write settings_state_test.dart**

Read `lib/features/settings/models/service_control.dart` first to understand the `ServiceControl` type, then write:

```dart
// test/features/settings/settings_state_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/settings/bloc/settings_state.dart';
import 'package:legion_frontend/features/settings/models/service_control.dart';

void main() {
  // Build a minimal ServiceControl from whatever constructor it exposes.
  // Read lib/features/settings/models/service_control.dart to get the fields.

  group('SettingsState.initial', () {
    test('services is empty', () {
      expect(SettingsState.initial().services, isEmpty);
    });

    test('hasLoaded is false', () {
      expect(SettingsState.initial().hasLoaded, isFalse);
    });

    test('errorMessage and noticeMessage are null', () {
      final s = SettingsState.initial();
      expect(s.errorMessage, isNull);
      expect(s.noticeMessage, isNull);
    });
  });

  group('SettingsState.hasLoaded', () {
    // hasLoaded = services.isNotEmpty
    test('true when services list is non-empty', () {
      // Use a real ServiceControl — check the model for constructor args.
      // The test will depend on what ServiceControl looks like; fill in below.
      // Example (adjust fields to match actual model):
      // final s = SettingsState.initial().copyWith(services: [ServiceControl(...)]);
      // expect(s.hasLoaded, isTrue);
    });
  });

  group('SettingsState.copyWith sentinel', () {
    test('copyWith with no args returns equal state', () {
      expect(
        SettingsState.initial().copyWith(),
        equals(SettingsState.initial()),
      );
    });

    test('copyWith(errorMessage: null) clears it', () {
      final s = SettingsState.initial()
          .copyWith(errorMessage: 'err')
          .copyWith(errorMessage: null);
      expect(s.errorMessage, isNull);
    });

    test('copyWith omitting errorMessage preserves it', () {
      final s = SettingsState.initial()
          .copyWith(errorMessage: 'msg')
          .copyWith(isLoading: true);
      expect(s.errorMessage, equals('msg'));
    });

    test('copyWith(noticeMessage: null) clears it', () {
      final s = SettingsState.initial()
          .copyWith(noticeMessage: 'done')
          .copyWith(noticeMessage: null);
      expect(s.noticeMessage, isNull);
    });
  });

  group('SettingsState props', () {
    test('identical states are equal', () {
      expect(SettingsState.initial(), equals(SettingsState.initial()));
    });

    test('differ when isApplying differs', () {
      final a = SettingsState.initial();
      final b = a.copyWith(isApplying: true);
      expect(a, isNot(equals(b)));
    });
  });
}
```

**Step 2: Write dashboard_state_test.dart**

Read `lib/features/dashboard/models/dashboard_snapshot.dart` to see what `DashboardSnapshot.initial()` returns, then:

```dart
// test/features/dashboard/dashboard_state_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/dashboard/bloc/dashboard_state.dart';
import 'package:legion_frontend/features/dashboard/models/dashboard_snapshot.dart';

void main() {
  group('DashboardState.initial', () {
    test('hasInitialized is false', () {
      expect(DashboardState.initial().hasInitialized, isFalse);
    });

    test('isLoading and isApplying are false', () {
      final s = DashboardState.initial();
      expect(s.isLoading, isFalse);
      expect(s.isApplying, isFalse);
    });

    test('errorMessage and noticeMessage are null', () {
      final s = DashboardState.initial();
      expect(s.errorMessage, isNull);
      expect(s.noticeMessage, isNull);
    });
  });

  group('DashboardState.copyWith sentinel', () {
    test('copyWith with no args returns equal state', () {
      expect(
        DashboardState.initial().copyWith(),
        equals(DashboardState.initial()),
      );
    });

    test('copyWith(errorMessage: null) clears it', () {
      final s = DashboardState.initial()
          .copyWith(errorMessage: 'fail')
          .copyWith(errorMessage: null);
      expect(s.errorMessage, isNull);
    });

    test('copyWith omitting errorMessage preserves it', () {
      final s = DashboardState.initial()
          .copyWith(errorMessage: 'x')
          .copyWith(isLoading: true);
      expect(s.errorMessage, equals('x'));
    });

    test('copyWith(hasInitialized: true) sets it', () {
      final s = DashboardState.initial().copyWith(hasInitialized: true);
      expect(s.hasInitialized, isTrue);
    });
  });

  group('DashboardState props', () {
    test('identical initial states are equal', () {
      expect(DashboardState.initial(), equals(DashboardState.initial()));
    });

    test('differ when hasInitialized differs', () {
      final a = DashboardState.initial();
      final b = a.copyWith(hasInitialized: true);
      expect(a, isNot(equals(b)));
    });
  });
}
```

**NOTE for SettingsState.hasLoaded test:** Read `lib/features/settings/models/service_control.dart` to find the constructor and fill in a real `ServiceControl` instance.

**Step 3: Run tests**

```bash
cd frontend/legion_frontend
flutter test test/features/settings/ test/features/dashboard/ -v
```

Expected: all tests pass (skip any placeholder test bodies that remain empty).

**Step 4: Commit**

```bash
git add test/features/settings/settings_state_test.dart test/features/dashboard/dashboard_state_test.dart
git commit -m "test: add SettingsState and DashboardState model tests"
```

---

### Task 6: FansBloc synchronous event handler tests

**Files:**
- Create: `test/features/fans/fans_bloc_test.dart`

These tests cover the two **synchronous** handlers in `FansBloc` that never call the repository:
- `_onPresetSelectionChanged` — updates `selectedPreset`, clears `errorMessage`
- `_onFanCurvePointUpdated` — updates a single curve point, sets `fanCurveDirty: true`

Both handlers run without any async repository call, so the mock repository's methods never need to be stubbed.

**Step 1: Create test helpers directory and fake repository**

Create `test/helpers/fake_fans_repository.dart`:

```dart
// test/helpers/fake_fans_repository.dart
import 'package:mocktail/mocktail.dart';
import 'package:legion_frontend/features/fans/repository/fans_repository.dart';

class FakeFansRepository extends Mock implements FansRepository {}
```

Note: `mocktail` can mock concrete classes. `FakeFansRepository` will return `null`/default for any unstubbed call, which is fine for the synchronous-only tests in this file.

**Step 2: Write the test file**

```dart
// test/features/fans/fans_bloc_test.dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/fans/bloc/fans_bloc.dart';
import 'package:legion_frontend/features/fans/bloc/fans_event.dart';
import 'package:legion_frontend/features/fans/bloc/fans_state.dart';
import 'package:legion_frontend/features/fans/models/fan_curve.dart';

import '../../helpers/fake_fans_repository.dart';

FanCurve _tenPointCurve() => FanCurve(
  name: 'test',
  points: List.generate(
    10,
    (_) => const FanCurvePoint(
      fan1Rpm: 1200,
      fan2Rpm: 1200,
      cpuLowerTemp: 40,
      cpuUpperTemp: 50,
      gpuLowerTemp: 40,
      gpuUpperTemp: 50,
      icLowerTemp: 40,
      icUpperTemp: 50,
      accel: 5,
      decel: 5,
    ),
  ),
);

void main() {
  group('FansBloc.FansPresetSelectionChanged', () {
    late FakeFansRepository repo;

    setUp(() {
      repo = FakeFansRepository();
    });

    blocTest<FansBloc, FansState>(
      'updates selectedPreset to the new value',
      build: () => FansBloc(repository: repo),
      act: (bloc) => bloc.add(const FansPresetSelectionChanged('quiet-ac')),
      expect: () => [
        isA<FansState>().having(
          (s) => s.selectedPreset,
          'selectedPreset',
          equals('quiet-ac'),
        ),
      ],
    );

    blocTest<FansBloc, FansState>(
      'clears errorMessage when preset changes',
      build: () => FansBloc(repository: repo),
      seed: () => FansState.initial().copyWith(errorMessage: 'old error'),
      act: (bloc) =>
          bloc.add(const FansPresetSelectionChanged('balanced-ac')),
      expect: () => [
        isA<FansState>()
            .having((s) => s.selectedPreset, 'selectedPreset', 'balanced-ac')
            .having((s) => s.errorMessage, 'errorMessage', isNull),
      ],
    );

    blocTest<FansBloc, FansState>(
      'subsequent selections each emit a new state',
      build: () => FansBloc(repository: repo),
      act: (bloc) {
        bloc.add(const FansPresetSelectionChanged('quiet-ac'));
        bloc.add(const FansPresetSelectionChanged('performance-ac'));
      },
      expect: () => [
        isA<FansState>().having(
          (s) => s.selectedPreset,
          'selectedPreset',
          'quiet-ac',
        ),
        isA<FansState>().having(
          (s) => s.selectedPreset,
          'selectedPreset',
          'performance-ac',
        ),
      ],
    );
  });

  group('FansBloc.FanCurvePointUpdated', () {
    late FakeFansRepository repo;

    setUp(() {
      repo = FakeFansRepository();
    });

    blocTest<FansBloc, FansState>(
      'emits state with updated curve point and fanCurveDirty: true',
      build: () => FansBloc(repository: repo),
      seed: () => FansState.initial().copyWith(fanCurve: _tenPointCurve()),
      act: (bloc) => bloc.add(
        FanCurvePointUpdated(
          index: 0,
          point: const FanCurvePoint(
            fan1Rpm: 2000,
            fan2Rpm: 2000,
            cpuLowerTemp: 50,
            cpuUpperTemp: 60,
            gpuLowerTemp: 50,
            gpuUpperTemp: 60,
            icLowerTemp: 50,
            icUpperTemp: 60,
            accel: 5,
            decel: 5,
          ),
        ),
      ),
      expect: () => [
        isA<FansState>()
            .having((s) => s.fanCurveDirty, 'fanCurveDirty', isTrue)
            .having(
              (s) => s.fanCurve?.points[0].fan1Rpm,
              'fan1Rpm at index 0',
              equals(2000),
            ),
      ],
    );

    blocTest<FansBloc, FansState>(
      'does nothing when fanCurve is null',
      build: () => FansBloc(repository: repo),
      // seed defaults to initial() where fanCurve is null
      act: (bloc) => bloc.add(
        FanCurvePointUpdated(
          index: 0,
          point: const FanCurvePoint(
            fan1Rpm: 9999,
            fan2Rpm: 9999,
            cpuLowerTemp: 99,
            cpuUpperTemp: 99,
            gpuLowerTemp: 99,
            gpuUpperTemp: 99,
            icLowerTemp: 99,
            icUpperTemp: 99,
            accel: 5,
            decel: 5,
          ),
        ),
      ),
      expect: () => [],
    );

    blocTest<FansBloc, FansState>(
      'does nothing when index is out of bounds',
      build: () => FansBloc(repository: repo),
      seed: () => FansState.initial().copyWith(fanCurve: _tenPointCurve()),
      act: (bloc) => bloc.add(
        FanCurvePointUpdated(
          index: 10,
          point: const FanCurvePoint(
            fan1Rpm: 1,
            fan2Rpm: 1,
            cpuLowerTemp: 1,
            cpuUpperTemp: 1,
            gpuLowerTemp: 1,
            gpuUpperTemp: 1,
            icLowerTemp: 1,
            icUpperTemp: 1,
            accel: 1,
            decel: 1,
          ),
        ),
      ),
      expect: () => [],
    );
  });
}
```

**Step 3: Run tests**

```bash
cd frontend/legion_frontend
flutter test test/features/fans/fans_bloc_test.dart -v
```

Expected: all bloc tests pass.

**Step 4: Run full suite to confirm no regressions**

```bash
cd frontend/legion_frontend
flutter test
```

Expected: all tests pass including the new ones.

**Step 5: Commit**

```bash
git add test/features/fans/fans_bloc_test.dart test/helpers/fake_fans_repository.dart
git commit -m "test: add FansBloc synchronous event handler tests using mocktail"
```

---

### Task 7: Final verification

**Step 1: Run full test suite**

```bash
cd frontend/legion_frontend
flutter test --reporter=expanded
```

Expected: 40+ tests passing, 0 failures.

**Step 2: Run analyzer**

```bash
cd frontend/legion_frontend
flutter analyze
```

Expected: No issues.

**Step 3: Commit (if any cleanup was needed)**

If analyzer flagged anything: fix and commit with `fix: resolve analyzer warnings in test files`.

Otherwise just confirm the run passed and report done.
