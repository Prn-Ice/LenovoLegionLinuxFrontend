# Diagnostics Export v2 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Extend the About/Diagnostics page with richer environment metadata (kernel version, hardware model, module version, CLI version) and a redacted ring buffer of recent bridge commands, then include both in the existing "Copy diagnostics JSON" export.

**Architecture:** A `BridgeCommandRecord` value object is recorded by the bridge service at each public method boundary (one entry per user action, using `finally` to catch both success and failure). The `AboutRepository` reads the history from the bridge service and also collects environment metadata via sysfs reads and `Process.run`. All new data flows through the existing `AboutSnapshot → AboutState → AboutPage` stack with no new BLoC events or providers required.

**Tech Stack:** Dart `dart:collection.ListQueue` for the capped ring buffer; `dart:io.Process.run` for `uname -r` and `legion_cli --version`; `LegionSysfsService._readTrimmedFile` pattern for DMI sysfs reads; `Equatable` for all value objects; `flutter_test` + `mocktail` for unit tests.

---

### Task 1: BridgeCommandRecord model

**Files:**
- Create: `lib/core/models/bridge_command_record.dart`
- Create: `test/core/models/bridge_command_record_test.dart`

**Step 1: Write the failing test**

```dart
// test/core/models/bridge_command_record_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/models/bridge_command_record.dart';

void main() {
  final _ts = DateTime(2026, 3, 8, 12, 0, 0);

  group('BridgeCommandRecord constructor', () {
    test('stores all fields', () {
      final r = BridgeCommandRecord(
        timestamp: _ts,
        method: 'power.set_mode',
        args: const ['set-feature', 'PlatformProfile', 'quiet'],
        isPrivileged: true,
        succeeded: true,
        durationMs: 234,
      );
      expect(r.timestamp, _ts);
      expect(r.method, 'power.set_mode');
      expect(r.args, ['set-feature', 'PlatformProfile', 'quiet']);
      expect(r.isPrivileged, isTrue);
      expect(r.succeeded, isTrue);
      expect(r.durationMs, 234);
    });
  });

  group('BridgeCommandRecord.redactedArgs', () {
    test('keeps args without slashes unchanged', () {
      final r = BridgeCommandRecord(
        timestamp: _ts,
        method: 'm',
        args: const ['set-feature', 'PlatformProfile', 'quiet'],
        isPrivileged: true,
        succeeded: true,
        durationMs: 0,
      );
      expect(r.redactedArgs, ['set-feature', 'PlatformProfile', 'quiet']);
    });

    test('redacts args that contain a slash', () {
      final r = BridgeCommandRecord(
        timestamp: _ts,
        method: 'm',
        args: const ['boot-logo', 'enable', '/home/user/boot.bmp'],
        isPrivileged: true,
        succeeded: true,
        durationMs: 0,
      );
      expect(r.redactedArgs, ['boot-logo', 'enable', '<path>']);
    });

    test('unprivileged commands: args left unchanged even with slashes', () {
      // Unprivileged reads do not need redaction — they carry no user data.
      // redactedArgs only redacts path-shaped args regardless of privilege level.
      final r = BridgeCommandRecord(
        timestamp: _ts,
        method: 'diagnostics.cli_health',
        args: const ['--help'],
        isPrivileged: false,
        succeeded: true,
        durationMs: 0,
      );
      // '--help' has no slash, so no redaction.
      expect(r.redactedArgs, ['--help']);
    });
  });

  group('BridgeCommandRecord Equatable', () {
    test('equal when all fields match', () {
      final a = BridgeCommandRecord(
        timestamp: _ts,
        method: 'm',
        args: const ['a'],
        isPrivileged: false,
        succeeded: true,
        durationMs: 1,
      );
      final b = BridgeCommandRecord(
        timestamp: _ts,
        method: 'm',
        args: const ['a'],
        isPrivileged: false,
        succeeded: true,
        durationMs: 1,
      );
      expect(a, equals(b));
    });

    test('not equal when succeeded differs', () {
      final a = BridgeCommandRecord(
        timestamp: _ts,
        method: 'm',
        args: const [],
        isPrivileged: false,
        succeeded: true,
        durationMs: 0,
      );
      final b = a.copyWith(succeeded: false);
      expect(a, isNot(equals(b)));
    });
  });
}
```

**Step 2: Run test to verify it fails**

```bash
cd /home/prnice/Projects/personal/LenovoLegionLinuxFrontend
flutter test test/core/models/bridge_command_record_test.dart
```

Expected: FAIL — `bridge_command_record.dart` does not exist.

**Step 3: Implement the model**

```dart
// lib/core/models/bridge_command_record.dart
import 'package:equatable/equatable.dart';

class BridgeCommandRecord extends Equatable {
  const BridgeCommandRecord({
    required this.timestamp,
    required this.method,
    required this.args,
    required this.isPrivileged,
    required this.succeeded,
    required this.durationMs,
  });

  final DateTime timestamp;
  final String method;
  final List<String> args;
  final bool isPrivileged;
  final bool succeeded;
  final int durationMs;

  /// Returns [args] with any arg containing a `/` replaced by `<path>`.
  /// This prevents file-system paths (e.g. boot logo paths) from leaking
  /// personal directory names into exported diagnostics reports.
  List<String> get redactedArgs =>
      args.map((a) => a.contains('/') ? '<path>' : a).toList(growable: false);

  BridgeCommandRecord copyWith({
    DateTime? timestamp,
    String? method,
    List<String>? args,
    bool? isPrivileged,
    bool? succeeded,
    int? durationMs,
  }) {
    return BridgeCommandRecord(
      timestamp: timestamp ?? this.timestamp,
      method: method ?? this.method,
      args: args ?? this.args,
      isPrivileged: isPrivileged ?? this.isPrivileged,
      succeeded: succeeded ?? this.succeeded,
      durationMs: durationMs ?? this.durationMs,
    );
  }

  @override
  List<Object?> get props =>
      [timestamp, method, args, isPrivileged, succeeded, durationMs];
}
```

**Step 4: Run test to verify it passes**

```bash
flutter test test/core/models/bridge_command_record_test.dart
```

Expected: All tests PASS.

**Step 5: Commit**

```bash
git add lib/core/models/bridge_command_record.dart \
        test/core/models/bridge_command_record_test.dart
git commit -m "feat(about): add BridgeCommandRecord model with path redaction"
```

---

### Task 2: Command history ring buffer in LegionFrontendBridgeService

**Files:**
- Modify: `lib/core/services/legion_frontend_bridge_service.dart`

No new tests for the ring buffer itself — it's an internal implementation detail. The getter `commandHistory` is a pure read; correctness is validated end-to-end when `AboutRepository` tests read from it.

**Step 1: Add imports and ring buffer field**

At the top of `legion_frontend_bridge_service.dart`, add `dart:collection` import and two constants:

```dart
import 'dart:async';
import 'dart:collection';   // ← add this

import 'legion_cli_service.dart';
import '../models/bridge_command_record.dart';   // ← add this
```

Inside `LegionFrontendBridgeService`, add after `_privilegedQueue`:

```dart
static const int _historyCapacity = 20;
final ListQueue<BridgeCommandRecord> _history =
    ListQueue<BridgeCommandRecord>(_historyCapacity);

/// The last [_historyCapacity] bridge commands in chronological order.
List<BridgeCommandRecord> get commandHistory =>
    List.unmodifiable(_history);
```

**Step 2: Add `_recordHistory` helper method**

At the bottom of `LegionFrontendBridgeService` (before the closing `}`):

```dart
void _recordHistory({
  required String method,
  required List<String> args,
  required bool isPrivileged,
  required bool succeeded,
  required DateTime start,
}) {
  final record = BridgeCommandRecord(
    timestamp: start,
    method: method,
    args: args,
    isPrivileged: isPrivileged,
    succeeded: succeeded,
    durationMs: DateTime.now().difference(start).inMilliseconds,
  );
  if (_history.length >= _historyCapacity) {
    _history.removeFirst();
  }
  _history.addLast(record);
}
```

**Step 3: Record in `runPrivilegedCommand`**

Wrap the `await completion.future` call at the end of `runPrivilegedCommand` with timing and recording:

```dart
Future<void> runPrivilegedCommand({
  required String method,
  required List<String> args,
  Duration timeout = const Duration(seconds: 5),
  int retries = 1,
  bool detectUnavailableResponse = true,
}) async {
  final actionKey = _buildActionKey(method: method, args: args);
  if (_pendingActionKeys.contains(actionKey)) {
    throw LegionBridgeException(
      code: LegionBridgeErrorCode.busy,
      method: method,
      message: 'Action is already pending for $method.',
    );
  }

  _pendingActionKeys.add(actionKey);
  final completion = Completer<void>();

  _privilegedQueue = _privilegedQueue.catchError((_) {}).then((_) async {
    try {
      await _runCommand(
        method: method,
        args: args,
        timeout: timeout,
        retries: retries,
        privileged: true,
        detectUnavailableResponse: detectUnavailableResponse,
      );
      completion.complete();
    } catch (error, stackTrace) {
      completion.completeError(error, stackTrace);
    } finally {
      _pendingActionKeys.remove(actionKey);
    }
  });

  final start = DateTime.now();   // ← add
  var succeeded = false;           // ← add
  try {
    await completion.future;
    succeeded = true;              // ← add
  } finally {
    _recordHistory(               // ← add
      method: method,
      args: args,
      isPrivileged: true,
      succeeded: succeeded,
      start: start,
    );
  }
}
```

**Step 4: Record in `runCommand`**

Replace the `runCommand` body with a timed wrapper:

```dart
Future<LegionCliResult> runCommand({
  required String method,
  required List<String> args,
  Duration timeout = const Duration(seconds: 5),
  int retries = 0,
  bool privileged = false,
  bool detectUnavailableResponse = false,
}) async {
  final start = DateTime.now();
  var succeeded = false;
  try {
    final result = await _runCommand(
      method: method,
      args: args,
      timeout: timeout,
      retries: retries,
      privileged: privileged,
      detectUnavailableResponse: detectUnavailableResponse,
    );
    succeeded = true;
    return result;
  } finally {
    _recordHistory(
      method: method,
      args: args,
      isPrivileged: privileged,
      succeeded: succeeded,
      start: start,
    );
  }
}
```

**Step 5: Run existing tests to check nothing is broken**

```bash
flutter test
```

Expected: All existing tests PASS.

**Step 6: Commit**

```bash
git add lib/core/services/legion_frontend_bridge_service.dart \
        lib/core/models/bridge_command_record.dart
git commit -m "feat(about): add command history ring buffer to bridge service"
```

---

### Task 3: AboutSnapshot new environment fields + tests

**Files:**
- Modify: `lib/features/about/models/about_snapshot.dart`
- Create: `test/features/about/about_snapshot_test.dart`

**Step 1: Write failing tests**

```dart
// test/features/about/about_snapshot_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/models/bridge_command_record.dart';
import 'package:legion_frontend/features/about/models/about_diagnostic_item.dart';
import 'package:legion_frontend/features/about/models/about_snapshot.dart';

final _ts = DateTime(2026, 3, 8, 12, 0);
const _item = AboutDiagnosticItem(
  id: 'a',
  label: 'A',
  status: AboutDiagnosticStatus.ok,
  value: 'v',
);

AboutSnapshot _minimal() => AboutSnapshot(
      updatedAt: _ts,
      cliPath: '/usr/bin/legion_cli',
      cliPathExists: true,
      pythonAvailable: true,
      pkexecAvailable: true,
      systemctlAvailable: true,
      cliHealthy: true,
      cliHealthSummary: 'Healthy',
      diagnostics: const [],
      kernelVersion: null,
      hardwareModel: null,
      moduleVersion: null,
      cliVersion: null,
      commandHistory: const [],
    );

void main() {
  group('AboutSnapshot new fields default to null / empty', () {
    test('kernelVersion is null when not provided', () {
      expect(_minimal().kernelVersion, isNull);
    });

    test('hardwareModel is null when not provided', () {
      expect(_minimal().hardwareModel, isNull);
    });

    test('moduleVersion is null when not provided', () {
      expect(_minimal().moduleVersion, isNull);
    });

    test('cliVersion is null when not provided', () {
      expect(_minimal().cliVersion, isNull);
    });

    test('commandHistory is empty by default', () {
      expect(_minimal().commandHistory, isEmpty);
    });
  });

  group('AboutSnapshot Equatable', () {
    test('equal when all fields match', () {
      expect(_minimal(), equals(_minimal()));
    });

    test('not equal when kernelVersion differs', () {
      final a = _minimal();
      final b = AboutSnapshot(
        updatedAt: _ts,
        cliPath: '/usr/bin/legion_cli',
        cliPathExists: true,
        pythonAvailable: true,
        pkexecAvailable: true,
        systemctlAvailable: true,
        cliHealthy: true,
        cliHealthSummary: 'Healthy',
        diagnostics: const [],
        kernelVersion: '6.8.0',
        hardwareModel: null,
        moduleVersion: null,
        cliVersion: null,
        commandHistory: const [],
      );
      expect(a, isNot(equals(b)));
    });

    test('not equal when commandHistory differs', () {
      final record = BridgeCommandRecord(
        timestamp: _ts,
        method: 'm',
        args: const [],
        isPrivileged: false,
        succeeded: true,
        durationMs: 0,
      );
      final a = _minimal();
      final b = AboutSnapshot(
        updatedAt: _ts,
        cliPath: '/usr/bin/legion_cli',
        cliPathExists: true,
        pythonAvailable: true,
        pkexecAvailable: true,
        systemctlAvailable: true,
        cliHealthy: true,
        cliHealthSummary: 'Healthy',
        diagnostics: const [],
        kernelVersion: null,
        hardwareModel: null,
        moduleVersion: null,
        cliVersion: null,
        commandHistory: [record],
      );
      expect(a, isNot(equals(b)));
    });
  });
}
```

**Step 2: Run to verify it fails**

```bash
flutter test test/features/about/about_snapshot_test.dart
```

Expected: FAIL — `AboutSnapshot` does not have the new fields.

**Step 3: Update AboutSnapshot**

Replace `lib/features/about/models/about_snapshot.dart` with:

```dart
import 'package:equatable/equatable.dart';

import '../../../core/models/bridge_command_record.dart';
import 'about_diagnostic_item.dart';

class AboutSnapshot extends Equatable {
  const AboutSnapshot({
    required this.updatedAt,
    required this.cliPath,
    required this.cliPathExists,
    required this.pythonAvailable,
    required this.pkexecAvailable,
    required this.systemctlAvailable,
    required this.cliHealthy,
    required this.cliHealthSummary,
    required this.diagnostics,
    required this.kernelVersion,
    required this.hardwareModel,
    required this.moduleVersion,
    required this.cliVersion,
    required this.commandHistory,
  });

  final DateTime updatedAt;
  final String cliPath;
  final bool cliPathExists;
  final bool pythonAvailable;
  final bool pkexecAvailable;
  final bool systemctlAvailable;
  final bool cliHealthy;
  final String cliHealthSummary;
  final List<AboutDiagnosticItem> diagnostics;

  // Environment metadata
  final String? kernelVersion;
  final String? hardwareModel;
  final String? moduleVersion;
  final String? cliVersion;

  // Recent command history
  final List<BridgeCommandRecord> commandHistory;

  @override
  List<Object?> get props => [
        updatedAt,
        cliPath,
        cliPathExists,
        pythonAvailable,
        pkexecAvailable,
        systemctlAvailable,
        cliHealthy,
        cliHealthSummary,
        diagnostics,
        kernelVersion,
        hardwareModel,
        moduleVersion,
        cliVersion,
        commandHistory,
      ];
}
```

**Step 4: Fix the compile error in AboutRepository**

The `loadSnapshot()` call in the repository now needs the new required fields. Add them as `null` / `const []` placeholders for now (Task 4 will fill them in):

In `lib/features/about/repository/about_repository.dart`, update the `return AboutSnapshot(...)` call:

```dart
return AboutSnapshot(
  updatedAt: DateTime.now(),
  cliPath: _cli.cliPath,
  cliPathExists: cliPathExists,
  pythonAvailable: pythonAvailable,
  pkexecAvailable: pkexecAvailable,
  systemctlAvailable: systemctlAvailable,
  cliHealthy: cliProbe.$1,
  cliHealthSummary: cliProbe.$2,
  diagnostics: diagnostics,
  kernelVersion: null,      // filled in Task 4
  hardwareModel: null,      // filled in Task 4
  moduleVersion: null,      // filled in Task 4
  cliVersion: null,         // filled in Task 4
  commandHistory: const [], // filled in Task 4
);
```

**Step 5: Run tests**

```bash
flutter test
```

Expected: All tests PASS (new about_snapshot_test passes; existing tests unaffected).

**Step 6: Commit**

```bash
git add lib/features/about/models/about_snapshot.dart \
        lib/features/about/repository/about_repository.dart \
        test/features/about/about_snapshot_test.dart
git commit -m "feat(about): add environment metadata and command history fields to AboutSnapshot"
```

---

### Task 4: AboutRepository collects environment metadata and command history

**Files:**
- Modify: `lib/features/about/repository/about_repository.dart`

**Step 1: Understand the data sources**

| Field | Source |
|---|---|
| `kernelVersion` | `Process.run('uname', ['-r'])` → trim stdout |
| `hardwareModel` | `/sys/class/dmi/id/product_family` + `/sys/class/dmi/id/product_name` → `"Legion 7 (83ET)"` |
| `moduleVersion` | `/sys/module/legion_laptop/version` → direct sysfs read |
| `cliVersion` | `legion_cli --version` via `bridge.runCommand(method: 'diagnostics.cli_version', args: ['--version'])` → first non-empty line of stdout |
| `commandHistory` | `bridge.commandHistory` getter |

**Step 2: Add private helper methods to AboutRepository**

Add these helpers to `about_repository.dart` (before the closing `}`):

```dart
Future<String?> _readKernelVersion() async {
  try {
    final result = await Process.run('uname', ['-r']);
    if (result.exitCode != 0) return null;
    final version = (result.stdout as String).trim();
    return version.isEmpty ? null : version;
  } on ProcessException {
    return null;
  }
}

Future<String?> _readHardwareModel() async {
  final family = await _readDmiField('product_family');
  final name = await _readDmiField('product_name');
  if (family == null && name == null) return null;
  if (family == null) return name;
  if (name == null) return family;
  return '$family ($name)';
}

Future<String?> _readDmiField(String field) async {
  try {
    final file = File('/sys/class/dmi/id/$field');
    if (!await file.exists()) return null;
    final value = (await file.readAsString()).trim();
    return value.isEmpty ? null : value;
  } on FileSystemException {
    return null;
  }
}

Future<String?> _readModuleVersion() async {
  try {
    final file = File('/sys/module/legion_laptop/version');
    if (!await file.exists()) return null;
    final value = (await file.readAsString()).trim();
    return value.isEmpty ? null : value;
  } on FileSystemException {
    return null;
  }
}

Future<String?> _readCliVersion() async {
  try {
    final result = await _bridge.runCommand(
      method: 'diagnostics.cli_version',
      args: const ['--version'],
      timeout: const Duration(seconds: 2),
    );
    final lines = (result.stdout as String)
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    return lines.isEmpty ? null : lines.first;
  } catch (_) {
    return null;
  }
}
```

**Step 3: Update `loadSnapshot` to collect and pass new data**

Replace the final block of `loadSnapshot()`:

```dart
final cliPathExists = File(_cli.cliPath).existsSync();
final pythonAvailable = await _isCommandAvailable('python3');
final pkexecAvailable = await _isCommandAvailable('pkexec');
final systemctlAvailable = await _isCommandAvailable('systemctl');
final cliProbe = await _probeCliHealth();

// Collect environment metadata in parallel — all are independent reads.
final results = await Future.wait([
  _readKernelVersion(),
  _readHardwareModel(),
  _readModuleVersion(),
  _readCliVersion(),
]);

return AboutSnapshot(
  updatedAt: DateTime.now(),
  cliPath: _cli.cliPath,
  cliPathExists: cliPathExists,
  pythonAvailable: pythonAvailable,
  pkexecAvailable: pkexecAvailable,
  systemctlAvailable: systemctlAvailable,
  cliHealthy: cliProbe.$1,
  cliHealthSummary: cliProbe.$2,
  diagnostics: diagnostics,
  kernelVersion: results[0],
  hardwareModel: results[1],
  moduleVersion: results[2],
  cliVersion: results[3],
  commandHistory: _bridge.commandHistory,
);
```

**Step 4: Run tests and verify the app compiles**

```bash
flutter test
flutter analyze
```

Expected: all tests PASS, no analysis errors.

**Step 5: Commit**

```bash
git add lib/features/about/repository/about_repository.dart
git commit -m "feat(about): collect kernel version, hardware model, module version, and CLI version in AboutRepository"
```

---

### Task 5: AboutPage view — Environment and Command History sections

**Files:**
- Modify: `lib/features/about/view/about_page.dart`

**Step 1: Add the Environment section**

After the "Runtime Dependencies" `AppSectionCard` and before the "Backend Capability Probes" card, insert a new card:

```dart
const SizedBox(height: 16),
AppSectionCard(
  title: 'Environment',
  children: [
    _StatusLine(
      label: 'Kernel',
      value: snapshot?.kernelVersion ?? 'Unknown',
      status: snapshot?.kernelVersion != null
          ? AboutDiagnosticStatus.ok
          : AboutDiagnosticStatus.unavailable,
    ),
    _StatusLine(
      label: 'Hardware',
      value: snapshot?.hardwareModel ?? 'Unknown',
      status: snapshot?.hardwareModel != null
          ? AboutDiagnosticStatus.ok
          : AboutDiagnosticStatus.unavailable,
    ),
    _StatusLine(
      label: 'Module version',
      value: snapshot?.moduleVersion ?? 'Unknown',
      status: snapshot?.moduleVersion != null
          ? AboutDiagnosticStatus.ok
          : AboutDiagnosticStatus.unavailable,
    ),
    _StatusLine(
      label: 'CLI version',
      value: snapshot?.cliVersion ?? 'Unknown',
      status: snapshot?.cliVersion != null
          ? AboutDiagnosticStatus.ok
          : AboutDiagnosticStatus.unavailable,
    ),
  ],
),
```

**Step 2: Add the Command History section**

After the "Backend Capability Probes" card, add:

```dart
const SizedBox(height: 16),
AppSectionCard(
  title: 'Command History (last 20)',
  children: [
    if (snapshot == null || snapshot.commandHistory.isEmpty)
      const Text('No commands recorded yet.'),
    if (snapshot != null)
      ...snapshot.commandHistory.reversed.map(
        (record) => _CommandHistoryTile(record: record),
      ),
  ],
),
```

**Step 3: Add the `_CommandHistoryTile` widget** (private, inside `about_page.dart`, after `_StatusLine`):

```dart
class _CommandHistoryTile extends StatelessWidget {
  const _CommandHistoryTile({required this.record});

  final BridgeCommandRecord record;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = record.succeeded ? Colors.green.shade700 : scheme.error;
    final icon = record.succeeded
        ? Icons.check_circle_outline
        : Icons.error_outline;
    final timeLabel = _formatTime(record.timestamp);
    final argsLabel = record.redactedArgs.join(' ');
    final subtitle = '${record.method}  $argsLabel';
    final trailing = '${record.durationMs} ms';

    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(icon, color: color, size: 18),
      title: Text(subtitle, style: const TextStyle(fontSize: 12)),
      subtitle: Text(
        timeLabel,
        style: TextStyle(fontSize: 11, color: scheme.outline),
      ),
      trailing: Text(
        trailing,
        style: TextStyle(fontSize: 11, color: scheme.outline),
      ),
    );
  }

  String _formatTime(DateTime ts) {
    final local = ts.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    final s = local.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}
```

**Step 4: Import `BridgeCommandRecord` in the view file**

Add to the imports at the top of `about_page.dart`:

```dart
import '../../../core/models/bridge_command_record.dart';
```

**Step 5: Update `_copyDiagnosticsJson` to include new fields**

In the `_copyDiagnosticsJson` method, add to the `payload` map:

```dart
'kernel_version': snapshot.kernelVersion,
'hardware_model': snapshot.hardwareModel,
'module_version': snapshot.moduleVersion,
'cli_version': snapshot.cliVersion,
'command_history': snapshot.commandHistory
    .map(
      (r) => <String, Object?>{
        'timestamp': r.timestamp.toIso8601String(),
        'method': r.method,
        'args': r.redactedArgs,
        'is_privileged': r.isPrivileged,
        'succeeded': r.succeeded,
        'duration_ms': r.durationMs,
      },
    )
    .toList(growable: false),
```

The full updated payload block:

```dart
final payload = <String, Object?>{
  'updated_at': snapshot.updatedAt.toIso8601String(),
  'cli_path': snapshot.cliPath,
  'cli_path_exists': snapshot.cliPathExists,
  'python_available': snapshot.pythonAvailable,
  'pkexec_available': snapshot.pkexecAvailable,
  'systemctl_available': snapshot.systemctlAvailable,
  'cli_healthy': snapshot.cliHealthy,
  'cli_health_summary': snapshot.cliHealthSummary,
  'kernel_version': snapshot.kernelVersion,
  'hardware_model': snapshot.hardwareModel,
  'module_version': snapshot.moduleVersion,
  'cli_version': snapshot.cliVersion,
  'diagnostics': snapshot.diagnostics
      .map(
        (entry) => <String, Object?>{
          'id': entry.id,
          'label': entry.label,
          'status': entry.status.name,
          'value': entry.value,
          'details': entry.details,
        },
      )
      .toList(growable: false),
  'command_history': snapshot.commandHistory
      .map(
        (r) => <String, Object?>{
          'timestamp': r.timestamp.toIso8601String(),
          'method': r.method,
          'args': r.redactedArgs,
          'is_privileged': r.isPrivileged,
          'succeeded': r.succeeded,
          'duration_ms': r.durationMs,
        },
      )
      .toList(growable: false),
};
```

**Step 6: Run tests and analyze**

```bash
flutter test
flutter analyze
```

Expected: all tests PASS, no analysis errors.

**Step 7: Commit**

```bash
git add lib/features/about/view/about_page.dart
git commit -m "feat(about): add Environment and Command History sections to AboutPage; update export JSON"
```

---

### Task 6: Final verification

**Step 1: Run full test suite**

```bash
flutter test --reporter=expanded
```

Expected: all tests PASS with no failures or errors.

**Step 2: Run static analysis**

```bash
flutter analyze
```

Expected: No issues found.

**Step 3: Close the bead**

```bash
cd /home/prnice/Projects/personal/LenovoLegionLinux
bd close LenovoLegionLinux-okf.13 --reason "Implemented in standalone frontend repo: environment metadata (kernel, hardware model, module version, CLI version) + command history ring buffer with path redaction + updated export JSON"
```
