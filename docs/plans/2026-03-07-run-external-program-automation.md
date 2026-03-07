# Run External Program Automation Step — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a "run external command" action type to the automation runner so users can execute a user-defined shell command as part of each automation cycle.

**Architecture:** Extends `AutomationConfig` with three new fields (`runExternalCommand`, `externalCommand`, `externalCommandOnContextChange`), adds a `runShellCommand` method to `AutomationRepository` (unprivileged `sh -c`), wires two new event handlers and integrates into the existing `_executeCycle` action chain, and adds a UI subsection to `AutomationPage` with a command text field, trigger toggle, and a user-context security notice.

**Tech Stack:** Flutter, riverbloc, equatable, `dart:io Process.run`

**NOTE:** All `flutter` commands must be run from inside `frontend/legion_frontend/` (direnv activates Flutter).

**Key distinction:** All existing automation actions are **privileged** (pkexec → legion_cli). This new action runs as the **current user** (`sh -c <command>`) — no pkexec, no root. This must be clearly communicated in the UI.

**Files touched:**
- `lib/features/automation/models/automation_config.dart` — 3 new fields
- `lib/features/automation/repository/automation_repository.dart` — `runShellCommand`
- `lib/features/automation/bloc/automation_event.dart` — 2 new events
- `lib/features/automation/bloc/automation_bloc.dart` — 2 handlers + `_executeCycle` integration
- `lib/features/automation/view/automation_page.dart` — external command subsection
- `test/features/automation/automation_config_test.dart` — new field tests

---

### Task 1: Extend AutomationConfig with external command fields

**Files:**
- Modify: `lib/features/automation/models/automation_config.dart`
- Modify: `test/features/automation/automation_config_test.dart`

**Step 1: Add tests for the new fields first**

Append a new `group` to `test/features/automation/automation_config_test.dart`:

```dart
  group('AutomationConfig external command defaults', () {
    test('runExternalCommand is false', () {
      expect(AutomationConfig.defaults().runExternalCommand, isFalse);
    });

    test('externalCommand is empty string', () {
      expect(AutomationConfig.defaults().externalCommand, equals(''));
    });

    test('externalCommandOnContextChange is true', () {
      expect(AutomationConfig.defaults().externalCommandOnContextChange, isTrue);
    });
  });

  group('AutomationConfig.fromJson external command', () {
    test('uses defaults when keys absent', () {
      final c = AutomationConfig.fromJson({});
      expect(c.runExternalCommand, isFalse);
      expect(c.externalCommand, equals(''));
      expect(c.externalCommandOnContextChange, isTrue);
    });

    test('reads runExternalCommand from bool', () {
      final c = AutomationConfig.fromJson({'runExternalCommand': true});
      expect(c.runExternalCommand, isTrue);
    });

    test('reads externalCommand from string', () {
      final c = AutomationConfig.fromJson({'externalCommand': 'notify-send hello'});
      expect(c.externalCommand, equals('notify-send hello'));
    });

    test('reads externalCommandOnContextChange from bool', () {
      final c = AutomationConfig.fromJson({'externalCommandOnContextChange': false});
      expect(c.externalCommandOnContextChange, isFalse);
    });

    test('ignores non-string value for externalCommand', () {
      final c = AutomationConfig.fromJson({'externalCommand': 42});
      expect(c.externalCommand, equals(''));
    });
  });

  group('AutomationConfig.toJson external command roundtrip', () {
    test('toJson includes all three new fields', () {
      final c = AutomationConfig.defaults().copyWith(
        runExternalCommand: true,
        externalCommand: 'echo hello',
        externalCommandOnContextChange: false,
      );
      final json = c.toJson();
      expect(json['runExternalCommand'], isTrue);
      expect(json['externalCommand'], equals('echo hello'));
      expect(json['externalCommandOnContextChange'], isFalse);
    });

    test('fromJson(toJson(c)) round-trips without loss', () {
      final original = AutomationConfig.defaults().copyWith(
        runExternalCommand: true,
        externalCommand: 'notify-send done',
        externalCommandOnContextChange: false,
      );
      final roundTripped = AutomationConfig.fromJson(original.toJson());
      expect(roundTripped, equals(original));
    });
  });
```

**Step 2: Run tests — expect failure**

```bash
cd frontend/legion_frontend
flutter test test/features/automation/automation_config_test.dart -v
```

Expected: compile error — new fields don't exist yet.

**Step 3: Add fields to AutomationConfig**

In `lib/features/automation/models/automation_config.dart`:

**Constructor** — add three required params after `conservationUpperLimit`:
```dart
    required this.runExternalCommand,
    required this.externalCommand,
    required this.externalCommandOnContextChange,
```

**Field declarations** — add after `conservationUpperLimit`:
```dart
  final bool runExternalCommand;
  final String externalCommand;
  final bool externalCommandOnContextChange;
```

**`defaults()` factory** — add:
```dart
    runExternalCommand: false,
    externalCommand: '',
    externalCommandOnContextChange: true,
```

**`fromJson()` factory** — add after `conservationUpperLimit` parsing:
```dart
      runExternalCommand:
          _asBool(json['runExternalCommand']) ?? defaults.runExternalCommand,
      externalCommand:
          _asString(json['externalCommand']) ?? defaults.externalCommand,
      externalCommandOnContextChange:
          _asBool(json['externalCommandOnContextChange']) ??
          defaults.externalCommandOnContextChange,
```

**`toJson()`** — add:
```dart
      'runExternalCommand': runExternalCommand,
      'externalCommand': externalCommand,
      'externalCommandOnContextChange': externalCommandOnContextChange,
```

**`copyWith()`** — add params and body:
```dart
    bool? runExternalCommand,
    String? externalCommand,
    bool? externalCommandOnContextChange,
```
```dart
      runExternalCommand: runExternalCommand ?? this.runExternalCommand,
      externalCommand: externalCommand ?? this.externalCommand,
      externalCommandOnContextChange:
          externalCommandOnContextChange ?? this.externalCommandOnContextChange,
```

**`props`** — add:
```dart
    runExternalCommand,
    externalCommand,
    externalCommandOnContextChange,
```

**Add `_asString` helper** alongside `_asBool` and `_asInt`:
```dart
  static String? _asString(dynamic value) {
    if (value is String) return value;
    return null;
  }
```

**Step 4: Run tests — expect pass**

```bash
flutter test test/features/automation/automation_config_test.dart -v
```

Expected: all tests pass (existing + new).

**Step 5: Commit**

```bash
git add \
  lib/features/automation/models/automation_config.dart \
  test/features/automation/automation_config_test.dart
git commit -m "feat(automation): add external command fields to AutomationConfig"
```

---

### Task 2: Add runShellCommand to AutomationRepository

**Files:**
- Modify: `lib/features/automation/repository/automation_repository.dart`

No unit test for this method — it spawns a real process, making it integration-only. The integration path is exercised via the automation cycle in manual testing.

**Step 1: Add the method**

At the bottom of `AutomationRepository`, before the `_configFile` getter, add:

```dart
  /// Runs [command] as the current user (NOT privileged — no pkexec).
  /// Returns the trimmed stdout on success.
  /// Throws [AutomationRepositoryException] on non-zero exit or timeout.
  Future<String> runShellCommand(String command) async {
    try {
      final result = await Process.run('sh', ['-c', command])
          .timeout(const Duration(seconds: 30));
      if (result.exitCode == 0) {
        return '${result.stdout}'.trim();
      }
      final stderr = '${result.stderr}'.trim();
      final detail = stderr.isNotEmpty ? ': $stderr' : '';
      throw AutomationRepositoryException(
        'External command exited with code ${result.exitCode}$detail',
      );
    } on TimeoutException {
      throw const AutomationRepositoryException(
        'External command timed out after 30 seconds.',
      );
    } on ProcessException catch (e) {
      throw AutomationRepositoryException(
        'Failed to start external command: ${e.message}',
      );
    }
  }
```

The `dart:async` import is already present at the top of the file (used for Timer in bloc — but check if it's in the repository file; add `import 'dart:async';` if needed).

**Step 2: Verify compilation**

```bash
cd frontend/legion_frontend
flutter analyze
```

Expected: No issues.

**Step 3: Commit**

```bash
git add lib/features/automation/repository/automation_repository.dart
git commit -m "feat(automation): add runShellCommand to AutomationRepository"
```

---

### Task 3: Add events and bloc handlers

**Files:**
- Modify: `lib/features/automation/bloc/automation_event.dart`
- Modify: `lib/features/automation/bloc/automation_bloc.dart`

**Step 1: Add two new events**

In `automation_event.dart`, add after `AutomationConservationLimitsUpdated`:

```dart
final class AutomationExternalCommandRuleToggled extends AutomationEvent {
  const AutomationExternalCommandRuleToggled(this.enabled);

  final bool enabled;

  @override
  List<Object?> get props => [enabled];
}

final class AutomationExternalCommandUpdated extends AutomationEvent {
  const AutomationExternalCommandUpdated(this.command);

  final String command;

  @override
  List<Object?> get props => [command];
}

final class AutomationExternalCommandTriggerUpdated extends AutomationEvent {
  const AutomationExternalCommandTriggerUpdated(this.onContextChange);

  final bool onContextChange;

  @override
  List<Object?> get props => [onContextChange];
}
```

**Step 2: Register handlers in AutomationBloc constructor**

In the `AutomationBloc` constructor body, after `on<AutomationConservationLimitsUpdated>`:

```dart
    on<AutomationExternalCommandRuleToggled>(_onExternalCommandRuleToggled);
    on<AutomationExternalCommandUpdated>(_onExternalCommandUpdated);
    on<AutomationExternalCommandTriggerUpdated>(_onExternalCommandTriggerUpdated);
```

**Step 3: Add handler methods**

After `_onConservationLimitsUpdated`, add:

```dart
  Future<void> _onExternalCommandRuleToggled(
    AutomationExternalCommandRuleToggled event,
    Emitter<AutomationState> emit,
  ) async {
    final updatedConfig = state.config.copyWith(
      runExternalCommand: event.enabled,
    );
    await _persistConfig(updatedConfig, emit);
  }

  Future<void> _onExternalCommandUpdated(
    AutomationExternalCommandUpdated event,
    Emitter<AutomationState> emit,
  ) async {
    final updatedConfig = state.config.copyWith(externalCommand: event.command);
    await _persistConfig(updatedConfig, emit);
  }

  Future<void> _onExternalCommandTriggerUpdated(
    AutomationExternalCommandTriggerUpdated event,
    Emitter<AutomationState> emit,
  ) async {
    final updatedConfig = state.config.copyWith(
      externalCommandOnContextChange: event.onContextChange,
    );
    await _persistConfig(updatedConfig, emit);
  }
```

**Step 4: Integrate into _executeCycle**

In `_executeCycle`, after the rapid charging action block and before `_lastSnapshot = snapshot;`, add:

```dart
      if (state.config.runExternalCommand &&
          state.config.externalCommand.trim().isNotEmpty) {
        final runThisCycle = !state.config.externalCommandOnContextChange ||
            shouldRunContextActions;
        if (runThisCycle) {
          try {
            await _repository.runShellCommand(state.config.externalCommand);
            actions.add(
              'Ran external command: ${state.config.externalCommand}',
            );
          } on AutomationRepositoryException catch (e) {
            // Non-fatal: log in summary but don't abort the rest of the cycle.
            actions.add('External command failed: $e');
          }
        }
      }
```

**NOTE on non-fatal error handling:** External command errors are logged in the cycle summary but do NOT abort the cycle. This is consistent with the idea that a user script failing shouldn't prevent fan preset or conservation from applying. The error text appears in `lastRunSummary`.

**Step 5: Verify compilation and run tests**

```bash
cd frontend/legion_frontend
flutter analyze && flutter test
```

Expected: no issues, all existing tests pass.

**Step 6: Commit**

```bash
git add \
  lib/features/automation/bloc/automation_event.dart \
  lib/features/automation/bloc/automation_bloc.dart
git commit -m "feat(automation): add external command events and bloc handlers"
```

---

### Task 4: UI — external command subsection in AutomationPage

**Files:**
- Modify: `lib/features/automation/view/automation_page.dart`

**Step 1: Add imports if needed**

At the top, verify `automation_event.dart` is already imported (it is). No new imports needed.

**Step 2: Add the subsection**

In `automation_page.dart`, find the "Action chain" section. After the rapid charging block (which ends with the indented `rapidChargingOnBattery` tile), add before the closing `],` of the Rules card's `children`:

```dart
            AppSwitchTile(
              value: state.config.runExternalCommand,
              onChanged: (enabled) {
                bloc.add(AutomationExternalCommandRuleToggled(enabled));
              },
              title: 'Run external command',
              subtitle: 'Execute a shell command as your user account',
            ),
            if (state.config.runExternalCommand) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.warning_amber_outlined, size: 16),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Runs as your user account — not as root. '
                            'Avoid commands that require admin privileges.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _CommandField(
                      initialValue: state.config.externalCommand,
                      onSubmitted: (command) {
                        bloc.add(AutomationExternalCommandUpdated(command));
                      },
                    ),
                    const SizedBox(height: 8),
                    AppSwitchTile(
                      contentPadding: EdgeInsets.zero,
                      value: state.config.externalCommandOnContextChange,
                      onChanged: (onContextChange) {
                        bloc.add(
                          AutomationExternalCommandTriggerUpdated(
                            onContextChange,
                          ),
                        );
                      },
                      title: 'Only on context change',
                      subtitle: state.config.externalCommandOnContextChange
                          ? 'Runs when profile or power source changes'
                          : 'Runs every automation cycle',
                    ),
                  ],
                ),
              ),
            ],
```

**Step 3: Add _CommandField widget**

At the bottom of `automation_page.dart`, after `_LimitFieldState`, add:

```dart
class _CommandField extends StatefulWidget {
  const _CommandField({
    required this.initialValue,
    required this.onSubmitted,
  });

  final String initialValue;
  final ValueChanged<String> onSubmitted;

  @override
  State<_CommandField> createState() => _CommandFieldState();
}

class _CommandFieldState extends State<_CommandField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void didUpdateWidget(covariant _CommandField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue &&
        _controller.text != widget.initialValue) {
      _controller.text = widget.initialValue;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      decoration: const InputDecoration(
        labelText: 'Shell command',
        hintText: 'e.g. notify-send "Automation ran"',
      ),
      onSubmitted: (value) => widget.onSubmitted(value.trim()),
    );
  }
}
```

**Step 4: Verify compilation**

```bash
cd frontend/legion_frontend
flutter analyze
```

Expected: No issues.

**Step 5: Commit**

```bash
git add lib/features/automation/view/automation_page.dart
git commit -m "feat(automation): add external command UI section to AutomationPage"
```

---

### Task 5: Final verification

**Step 1: Run full test suite**

```bash
cd frontend/legion_frontend
flutter test --reporter=expanded
```

Expected: all tests pass (target: 148+ tests — 137 existing + 11 new config tests).

**Step 2: Run analyzer**

```bash
flutter analyze
```

Expected: No issues.

**Step 3: Quick manual smoke-check (optional)**

If you have a working LLL dev environment, enable the runner and set the command to `echo hello` with "every cycle". Let it tick once. Verify `lastRunSummary` shows `Ran external command: echo hello`. Then set a bad command (`nonexistent-binary`) and verify the summary shows `External command failed: ...` without the cycle erroring out.

**Step 4: Commit (only if cleanup needed)**

```bash
git commit -m "fix: resolve analyzer warnings in automation external command"
```
