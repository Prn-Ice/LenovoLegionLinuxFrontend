# Boot Logo Customization — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a Boot Logo section to the app that lets the user set a custom boot logo image or restore the stock one, driven by `legion_cli boot-logo {status|enable|restore}`.

**Architecture:** New `boot_logo` feature slice (models → snapshot → state/event → repository → bloc → view), new `AppSection.bootLogo` nav entry. Status is read unprivileged via `_bridgeService.runCommand(..., privileged: false)`. Enable and restore are privileged via `_bridgeService.runPrivilegedCommand`. File selection uses the `file_picker` package. Dimension and format validation is surfaced from the CLI error message — no client-side image decoding needed.

**Tech Stack:** Flutter, riverbloc, equatable, file_picker (new dep), existing `LegionFrontendBridgeService`

**NOTE:** All `flutter` commands must be run from inside `frontend/legion_frontend/` (direnv activates Flutter via the Nix flake).

**CLI surface (python/legion_linux/legion_linux/legion_cli.py:434):**
- `legion_cli boot-logo status` → `"Current Boot Logo status: ON; Required image dimensions: 1920 x 1080"` (unprivileged)
- `legion_cli boot-logo enable <image_path>` → validates dimensions + format via PIL, writes to EFI + `/boot/EFI/Lenovo/Logo/` (privileged)
- `legion_cli boot-logo restore` → resets EFI custom-logo flag to OFF (privileged)

**Supported formats (backend-enforced):** JPEG, PNG, BMP

---

### Task 1: Add file_picker dependency

**Files:**
- Modify: `pubspec.yaml`

**Step 1: Add dependency**

In `pubspec.yaml`, under `dependencies:`, add:

```yaml
  file_picker: ^8.0.7
```

**Step 2: Fetch**

```bash
cd frontend/legion_frontend
flutter pub get
```

Expected: resolves cleanly; `pubspec.lock` updated.

**Step 3: Run tests (no regressions)**

```bash
flutter test
```

Expected: 114 tests pass.

**Step 4: Commit**

```bash
git add frontend/legion_frontend/pubspec.yaml frontend/legion_frontend/pubspec.lock
git commit -m "chore: add file_picker dependency for boot logo image selection"
```

---

### Task 2: BootLogoStatus model + parsing tests

**Files:**
- Create: `lib/features/boot_logo/models/boot_logo_status.dart`
- Create: `test/features/boot_logo/boot_logo_status_test.dart`

**Step 1: Write the failing test first**

```dart
// test/features/boot_logo/boot_logo_status_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/boot_logo/models/boot_logo_status.dart';

void main() {
  group('BootLogoStatus.parseStatusOutput', () {
    test('parses ON with specific dimensions', () {
      final status = BootLogoStatus.parseStatusOutput(
        'Current Boot Logo status: ON; Required image dimensions: 1920 x 1080',
      );
      expect(status, isNotNull);
      expect(status!.isCustomEnabled, isTrue);
      expect(status.requiredWidth, equals(1920));
      expect(status.requiredHeight, equals(1080));
    });

    test('parses OFF with zero dimensions', () {
      final status = BootLogoStatus.parseStatusOutput(
        'Current Boot Logo status: OFF; Required image dimensions: 0 x 0',
      );
      expect(status, isNotNull);
      expect(status!.isCustomEnabled, isFalse);
      expect(status.requiredWidth, equals(0));
      expect(status.requiredHeight, equals(0));
    });

    test('returns null when output does not match expected format', () {
      expect(BootLogoStatus.parseStatusOutput(''), isNull);
      expect(BootLogoStatus.parseStatusOutput('Error: not found'), isNull);
    });

    test('hasDimensionConstraint is true when dimensions are non-zero', () {
      final status = BootLogoStatus(
        isCustomEnabled: false,
        requiredWidth: 1920,
        requiredHeight: 1080,
      );
      expect(status.hasDimensionConstraint, isTrue);
    });

    test('hasDimensionConstraint is false when both dimensions are zero', () {
      final status = BootLogoStatus(
        isCustomEnabled: false,
        requiredWidth: 0,
        requiredHeight: 0,
      );
      expect(status.hasDimensionConstraint, isFalse);
    });

    test('dimensionLabel returns WxH string when constrained', () {
      final status = BootLogoStatus(
        isCustomEnabled: true,
        requiredWidth: 800,
        requiredHeight: 600,
      );
      expect(status.dimensionLabel, equals('800×600'));
    });

    test('dimensionLabel returns "any" when unconstrained', () {
      final status = BootLogoStatus(
        isCustomEnabled: false,
        requiredWidth: 0,
        requiredHeight: 0,
      );
      expect(status.dimensionLabel, equals('any'));
    });
  });
}
```

**Step 2: Run test — expect failure**

```bash
cd frontend/legion_frontend
flutter test test/features/boot_logo/boot_logo_status_test.dart -v
```

Expected: compile error — `boot_logo_status.dart` does not exist yet.

**Step 3: Write the model**

```dart
// lib/features/boot_logo/models/boot_logo_status.dart
import 'package:equatable/equatable.dart';

class BootLogoStatus extends Equatable {
  const BootLogoStatus({
    required this.isCustomEnabled,
    required this.requiredWidth,
    required this.requiredHeight,
  });

  final bool isCustomEnabled;
  final int requiredWidth;
  final int requiredHeight;

  bool get hasDimensionConstraint => requiredWidth > 0 || requiredHeight > 0;

  String get dimensionLabel =>
      hasDimensionConstraint ? '${requiredWidth}×${requiredHeight}' : 'any';

  // Parses: "Current Boot Logo status: ON; Required image dimensions: 1920 x 1080"
  static BootLogoStatus? parseStatusOutput(String output) {
    final dimMatch = RegExp(r'dimensions: (\d+) x (\d+)').firstMatch(output);
    if (dimMatch == null) return null;
    return BootLogoStatus(
      isCustomEnabled: output.contains('status: ON'),
      requiredWidth: int.parse(dimMatch.group(1)!),
      requiredHeight: int.parse(dimMatch.group(2)!),
    );
  }

  @override
  List<Object?> get props => [isCustomEnabled, requiredWidth, requiredHeight];
}
```

**Step 4: Run test — expect pass**

```bash
flutter test test/features/boot_logo/boot_logo_status_test.dart -v
```

Expected: 7 tests pass.

**Step 5: Commit**

```bash
git add lib/features/boot_logo/models/boot_logo_status.dart test/features/boot_logo/boot_logo_status_test.dart
git commit -m "feat(boot-logo): add BootLogoStatus model with parseStatusOutput"
```

---

### Task 3: BootLogoSnapshot, State, Events

**Files:**
- Create: `lib/features/boot_logo/models/boot_logo_snapshot.dart`
- Create: `lib/features/boot_logo/bloc/boot_logo_state.dart`
- Create: `lib/features/boot_logo/bloc/boot_logo_event.dart`
- Create: `test/features/boot_logo/boot_logo_state_test.dart`

**Step 1: Write state tests first**

```dart
// test/features/boot_logo/boot_logo_state_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/boot_logo/bloc/boot_logo_state.dart';
import 'package:legion_frontend/features/boot_logo/models/boot_logo_status.dart';

const _status1920 = BootLogoStatus(
  isCustomEnabled: false,
  requiredWidth: 1920,
  requiredHeight: 1080,
);

void main() {
  group('BootLogoState.initial', () {
    test('status is null', () {
      expect(BootLogoState.initial().status, isNull);
    });

    test('selectedImagePath is null', () {
      expect(BootLogoState.initial().selectedImagePath, isNull);
    });

    test('validationError is null', () {
      expect(BootLogoState.initial().validationError, isNull);
    });

    test('isLoading and isApplying are false', () {
      final s = BootLogoState.initial();
      expect(s.isLoading, isFalse);
      expect(s.isApplying, isFalse);
    });

    test('canApply is false when no image selected', () {
      expect(BootLogoState.initial().canApply, isFalse);
    });
  });

  group('BootLogoState.canApply', () {
    test('true when image selected, no validation error, not applying', () {
      final s = BootLogoState.initial().copyWith(
        selectedImagePath: '/tmp/logo.png',
        validationError: null,
        isApplying: false,
      );
      expect(s.canApply, isTrue);
    });

    test('false when validationError is set', () {
      final s = BootLogoState.initial().copyWith(
        selectedImagePath: '/tmp/logo.txt',
        validationError: 'Unsupported format',
      );
      expect(s.canApply, isFalse);
    });

    test('false when isApplying is true', () {
      final s = BootLogoState.initial().copyWith(
        selectedImagePath: '/tmp/logo.png',
        isApplying: true,
      );
      expect(s.canApply, isFalse);
    });
  });

  group('BootLogoState.copyWith sentinel', () {
    test('copyWith with no args returns equal state', () {
      expect(BootLogoState.initial().copyWith(), equals(BootLogoState.initial()));
    });

    test('copyWith(status: null) clears it', () {
      final s = BootLogoState.initial()
          .copyWith(status: _status1920)
          .copyWith(status: null);
      expect(s.status, isNull);
    });

    test('copyWith omitting status preserves it', () {
      final s = BootLogoState.initial()
          .copyWith(status: _status1920)
          .copyWith(isLoading: true);
      expect(s.status, equals(_status1920));
    });

    test('copyWith(errorMessage: null) clears it', () {
      final s = BootLogoState.initial()
          .copyWith(errorMessage: 'oops')
          .copyWith(errorMessage: null);
      expect(s.errorMessage, isNull);
    });

    test('copyWith(selectedImagePath: null) clears it', () {
      final s = BootLogoState.initial()
          .copyWith(selectedImagePath: '/tmp/x.png')
          .copyWith(selectedImagePath: null);
      expect(s.selectedImagePath, isNull);
    });
  });

  group('BootLogoState props', () {
    test('identical initial states are equal', () {
      expect(BootLogoState.initial(), equals(BootLogoState.initial()));
    });

    test('differ when status differs', () {
      final a = BootLogoState.initial();
      final b = a.copyWith(status: _status1920);
      expect(a, isNot(equals(b)));
    });

    test('differ when selectedImagePath differs', () {
      final a = BootLogoState.initial().copyWith(selectedImagePath: '/a.png');
      final b = BootLogoState.initial().copyWith(selectedImagePath: '/b.png');
      expect(a, isNot(equals(b)));
    });
  });
}
```

**Step 2: Run test — expect failure**

```bash
flutter test test/features/boot_logo/boot_logo_state_test.dart -v
```

Expected: compile error — files don't exist yet.

**Step 3: Create the snapshot model**

```dart
// lib/features/boot_logo/models/boot_logo_snapshot.dart
import 'boot_logo_status.dart';

class BootLogoSnapshot {
  const BootLogoSnapshot({required this.status});

  final BootLogoStatus? status;
}
```

**Step 4: Create state**

```dart
// lib/features/boot_logo/bloc/boot_logo_state.dart
import 'package:equatable/equatable.dart';

import '../models/boot_logo_status.dart';

class BootLogoState extends Equatable {
  const BootLogoState({
    required this.status,
    required this.selectedImagePath,
    required this.validationError,
    required this.isLoading,
    required this.isApplying,
    required this.errorMessage,
    required this.noticeMessage,
  });

  factory BootLogoState.initial() => const BootLogoState(
    status: null,
    selectedImagePath: null,
    validationError: null,
    isLoading: false,
    isApplying: false,
    errorMessage: null,
    noticeMessage: null,
  );

  static const _unset = Object();

  final BootLogoStatus? status;
  final String? selectedImagePath;
  final String? validationError;
  final bool isLoading;
  final bool isApplying;
  final String? errorMessage;
  final String? noticeMessage;

  bool get canApply =>
      selectedImagePath != null && validationError == null && !isApplying;

  BootLogoState copyWith({
    Object? status = _unset,
    Object? selectedImagePath = _unset,
    Object? validationError = _unset,
    bool? isLoading,
    bool? isApplying,
    Object? errorMessage = _unset,
    Object? noticeMessage = _unset,
  }) {
    return BootLogoState(
      status: status == _unset ? this.status : status as BootLogoStatus?,
      selectedImagePath: selectedImagePath == _unset
          ? this.selectedImagePath
          : selectedImagePath as String?,
      validationError: validationError == _unset
          ? this.validationError
          : validationError as String?,
      isLoading: isLoading ?? this.isLoading,
      isApplying: isApplying ?? this.isApplying,
      errorMessage: errorMessage == _unset
          ? this.errorMessage
          : errorMessage as String?,
      noticeMessage: noticeMessage == _unset
          ? this.noticeMessage
          : noticeMessage as String?,
    );
  }

  @override
  List<Object?> get props => [
    status,
    selectedImagePath,
    validationError,
    isLoading,
    isApplying,
    errorMessage,
    noticeMessage,
  ];
}
```

**Step 5: Create events**

```dart
// lib/features/boot_logo/bloc/boot_logo_event.dart
abstract class BootLogoEvent {
  const BootLogoEvent();
}

/// Fired when the page opens — triggers loadSnapshot.
final class BootLogoStarted extends BootLogoEvent {
  const BootLogoStarted();
}

/// Fired when the user picks a file via the file picker.
final class BootLogoFileSelected extends BootLogoEvent {
  const BootLogoFileSelected(this.imagePath);
  final String imagePath;
}

/// Fired when the user taps "Apply Custom Logo" (after polkit confirmation).
final class BootLogoApplyRequested extends BootLogoEvent {
  const BootLogoApplyRequested();
}

/// Fired when the user taps "Restore Default Logo" (after polkit confirmation).
final class BootLogoRestoreRequested extends BootLogoEvent {
  const BootLogoRestoreRequested();
}

/// Fired by AppRefreshButton / periodic timer.
final class BootLogoRefreshRequested extends BootLogoEvent {
  const BootLogoRefreshRequested();
}
```

**Step 6: Run state tests — expect pass**

```bash
flutter test test/features/boot_logo/boot_logo_state_test.dart -v
```

Expected: 16 tests pass.

**Step 7: Commit**

```bash
git add \
  lib/features/boot_logo/models/boot_logo_snapshot.dart \
  lib/features/boot_logo/bloc/boot_logo_state.dart \
  lib/features/boot_logo/bloc/boot_logo_event.dart \
  test/features/boot_logo/boot_logo_state_test.dart
git commit -m "feat(boot-logo): add BootLogoSnapshot, BootLogoState, BootLogoEvent"
```

---

### Task 4: BootLogoRepository

**Files:**
- Create: `lib/features/boot_logo/repository/boot_logo_repository.dart`

No dedicated repository unit tests here — the repository calls the bridge (I/O) and all pure logic is in the model layer (already tested). Integration would require a real CLI.

**Step 1: Write the repository**

```dart
// lib/features/boot_logo/repository/boot_logo_repository.dart
import '../../../core/services/legion_frontend_bridge_service.dart';
import '../models/boot_logo_snapshot.dart';
import '../models/boot_logo_status.dart';

class BootLogoRepositoryException implements Exception {
  const BootLogoRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}

class BootLogoRepository {
  const BootLogoRepository({required LegionFrontendBridgeService bridgeService})
    : _bridgeService = bridgeService;

  final LegionFrontendBridgeService _bridgeService;

  /// Reads boot logo status without root. Returns null status if CLI fails or
  /// the EFI variable is inaccessible (e.g. non-Lenovo machine).
  Future<BootLogoSnapshot> loadSnapshot() async {
    try {
      final result = await _bridgeService.runCommand(
        method: 'boot-logo.status',
        args: ['boot-logo', 'status'],
        privileged: false,
        detectUnavailableResponse: false,
      );
      if (!result.ok) {
        return const BootLogoSnapshot(status: null);
      }
      final status = BootLogoStatus.parseStatusOutput(result.stdout);
      return BootLogoSnapshot(status: status);
    } catch (_) {
      return const BootLogoSnapshot(status: null);
    }
  }

  /// Enables a custom boot logo from [imagePath]. Root can read any absolute
  /// path, so no temp-file copy is needed — pass the original path directly.
  Future<void> enableBootLogo(String imagePath) async {
    await _runPrivilegedCommand(
      ['boot-logo', 'enable', imagePath],
      method: 'boot-logo.enable',
      failurePrefix: 'Failed to enable boot logo',
    );
  }

  /// Restores the stock boot logo by clearing the EFI custom-logo flag.
  Future<void> restoreBootLogo() async {
    await _runPrivilegedCommand(
      ['boot-logo', 'restore'],
      method: 'boot-logo.restore',
      failurePrefix: 'Failed to restore boot logo',
    );
  }

  Future<void> _runPrivilegedCommand(
    List<String> args, {
    required String method,
    required String failurePrefix,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    try {
      await _bridgeService.runPrivilegedCommand(
        method: method,
        args: args,
        timeout: timeout,
      );
    } on LegionBridgeException catch (error) {
      final details = error.details;
      final message = details.isEmpty ? '$failurePrefix.' : '$failurePrefix: $details';
      throw BootLogoRepositoryException(message);
    }
  }
}
```

**NOTE on timeout:** `boot-logo enable` copies a file into `/boot/EFI/Lenovo/Logo/` — on slow EFI partitions this can take a few seconds. Using 30 s timeout instead of the default 5 s.

**Step 2: Verify the project still compiles**

```bash
cd frontend/legion_frontend
flutter analyze
```

Expected: No issues.

**Step 3: Commit**

```bash
git add lib/features/boot_logo/repository/boot_logo_repository.dart
git commit -m "feat(boot-logo): add BootLogoRepository with status/enable/restore"
```

---

### Task 5: BootLogoBloc

**Files:**
- Create: `lib/features/boot_logo/bloc/boot_logo_bloc.dart`

**Step 1: Write the bloc**

```dart
// lib/features/boot_logo/bloc/boot_logo_bloc.dart
import 'package:riverbloc/riverbloc.dart';

import '../repository/boot_logo_repository.dart';
import 'boot_logo_event.dart';
import 'boot_logo_state.dart';

// Accepted image extensions (backend enforces format via PIL; we guard early).
const _acceptedExtensions = {'.png', '.jpg', '.jpeg', '.bmp'};

class BootLogoBloc extends Bloc<BootLogoEvent, BootLogoState> {
  BootLogoBloc({required BootLogoRepository repository})
    : _repository = repository,
      super(BootLogoState.initial()) {
    on<BootLogoStarted>(_onStarted);
    on<BootLogoFileSelected>(_onFileSelected);
    on<BootLogoApplyRequested>(_onApplyRequested);
    on<BootLogoRestoreRequested>(_onRestoreRequested);
    on<BootLogoRefreshRequested>(_onRefreshRequested);
  }

  final BootLogoRepository _repository;

  Future<void> _onStarted(
    BootLogoStarted event,
    Emitter<BootLogoState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, errorMessage: null));
    await _reloadState(emit);
  }

  Future<void> _onRefreshRequested(
    BootLogoRefreshRequested event,
    Emitter<BootLogoState> emit,
  ) async {
    await _reloadState(emit);
  }

  void _onFileSelected(
    BootLogoFileSelected event,
    Emitter<BootLogoState> emit,
  ) {
    final path = event.imagePath;
    final ext = path.contains('.')
        ? '.${path.split('.').last.toLowerCase()}'
        : '';
    final validationError = _acceptedExtensions.contains(ext)
        ? null
        : 'Unsupported format "$ext". Use PNG, JPEG, or BMP.';
    emit(state.copyWith(
      selectedImagePath: path,
      validationError: validationError,
      errorMessage: null,
      noticeMessage: null,
    ));
  }

  Future<void> _onApplyRequested(
    BootLogoApplyRequested event,
    Emitter<BootLogoState> emit,
  ) async {
    final imagePath = state.selectedImagePath;
    if (imagePath == null || !state.canApply) return;

    emit(state.copyWith(isApplying: true, errorMessage: null, noticeMessage: null));
    try {
      await _repository.enableBootLogo(imagePath);
      await _reloadState(emit, noticeMessage: 'Boot logo applied successfully.');
    } on BootLogoRepositoryException catch (error) {
      emit(state.copyWith(isApplying: false, errorMessage: error.message));
    }
  }

  Future<void> _onRestoreRequested(
    BootLogoRestoreRequested event,
    Emitter<BootLogoState> emit,
  ) async {
    if (state.isApplying) return;

    emit(state.copyWith(isApplying: true, errorMessage: null, noticeMessage: null));
    try {
      await _repository.restoreBootLogo();
      await _reloadState(emit, noticeMessage: 'Boot logo restored to default.');
    } on BootLogoRepositoryException catch (error) {
      emit(state.copyWith(isApplying: false, errorMessage: error.message));
    }
  }

  Future<void> _reloadState(
    Emitter<BootLogoState> emit, {
    String? noticeMessage,
  }) async {
    try {
      final snapshot = await _repository.loadSnapshot();
      emit(state.copyWith(
        status: snapshot.status,
        isLoading: false,
        isApplying: false,
        noticeMessage: noticeMessage,
      ));
    } catch (error) {
      emit(state.copyWith(
        isLoading: false,
        isApplying: false,
        errorMessage: 'Failed to load boot logo status: $error',
      ));
    }
  }
}
```

**Step 2: Verify compilation**

```bash
cd frontend/legion_frontend
flutter analyze
```

Expected: No issues.

**Step 3: Commit**

```bash
git add lib/features/boot_logo/bloc/boot_logo_bloc.dart
git commit -m "feat(boot-logo): add BootLogoBloc with status/enable/restore handlers"
```

---

### Task 6: Provider registration + navigation wiring

**Files:**
- Create: `lib/features/boot_logo/providers/boot_logo_provider.dart`
- Modify: `lib/features/navigation/models/app_section.dart`
- Modify: `lib/features/navigation/view/navigation_shell.dart`

**Step 1: Create the provider**

```dart
// lib/features/boot_logo/providers/boot_logo_provider.dart
import 'package:riverbloc/riverbloc.dart';

import '../../../core/providers/system_services_provider.dart';
import '../bloc/boot_logo_bloc.dart';
import '../bloc/boot_logo_event.dart';
import '../bloc/boot_logo_state.dart';
import '../repository/boot_logo_repository.dart';

final bootLogoRepositoryProvider = Provider<BootLogoRepository>((ref) {
  final bridgeService = ref.watch(legionBridgeServiceProvider);
  return BootLogoRepository(bridgeService: bridgeService);
});

final bootLogoBlocProvider =
    BlocProvider.autoDispose<BootLogoBloc, BootLogoState>((ref) {
      final repository = ref.watch(bootLogoRepositoryProvider);
      return BootLogoBloc(repository: repository)..add(const BootLogoStarted());
    });
```

**Step 2: Add `bootLogo` to AppSection enum**

In `lib/features/navigation/models/app_section.dart`:

- Add `bootLogo,` to the enum (place between `displayLighting` and `automation`)
- Add `case AppSection.bootLogo: return 'Boot Logo';` to `label`
- Add `case AppSection.bootLogo: return Icons.image_outlined;` to `icon`
- Add `case AppSection.bootLogo: return YaruIcons.image;` to `yaruIcon`

**Step 3: Wire BootLogoPage in navigation_shell.dart**

In `lib/features/navigation/view/navigation_shell.dart`:

- Add import: `import '../../boot_logo/view/boot_logo_page.dart';`
- In `_buildPage`, add: `case AppSection.bootLogo: return const BootLogoPage();`

**Step 4: Verify**

```bash
cd frontend/legion_frontend
flutter analyze
```

Expected: No issues.

**Step 5: Commit**

```bash
git add \
  lib/features/boot_logo/providers/boot_logo_provider.dart \
  lib/features/navigation/models/app_section.dart \
  lib/features/navigation/view/navigation_shell.dart
git commit -m "feat(boot-logo): register provider and add Boot Logo nav section"
```

---

### Task 7: BootLogoPage view

**Files:**
- Create: `lib/features/boot_logo/view/boot_logo_page.dart`

**Step 1: Reference an existing page for structural patterns**

Before writing, read `lib/features/display_lighting/view/display_lighting_page.dart` to confirm:
- `AppSectionCard` usage (from `lib/core/widgets/app_shell_components.dart`)
- `PrivilegedActionNotice` widget signature
- `confirmPrivilegedAction` helper
- `AppRefreshButton` pattern

**Step 2: Write the page**

```dart
// lib/features/boot_logo/view/boot_logo_page.dart
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_shell_components.dart';
import '../bloc/boot_logo_bloc.dart';
import '../bloc/boot_logo_event.dart';
import '../providers/boot_logo_provider.dart';

class BootLogoPage extends ConsumerWidget {
  const BootLogoPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(bootLogoBlocProvider);
    final bloc = ref.read(bootLogoBlocProvider.bloc);

    return AppPageScaffold(
      refreshButton: AppRefreshButton(
        isLoading: state.isLoading,
        onPressed: () => bloc.add(const BootLogoRefreshRequested()),
      ),
      children: [
        AppSectionCard(
          title: 'Boot Logo',
          children: [
            if (state.isLoading && state.status == null)
              const Center(child: CircularProgressIndicator())
            else if (state.status == null)
              const AppUnavailableNotice(
                message:
                    'Boot logo status is unavailable. This feature requires a '
                    'supported Lenovo Legion model and the EFI variable to be '
                    'readable.',
              )
            else ...[
              _StatusRow(
                isCustomEnabled: state.status!.isCustomEnabled,
                dimensionLabel: state.status!.dimensionLabel,
              ),
              const SizedBox(height: 16),
              _FilePickerRow(
                selectedPath: state.selectedImagePath,
                validationError: state.validationError,
                isApplying: state.isApplying,
                onPick: () => _pickFile(context, bloc),
                onClear: () => bloc.add(const BootLogoFileSelected('')),
              ),
              if (state.status!.hasDimensionConstraint) ...[
                const SizedBox(height: 8),
                Text(
                  'Required dimensions: ${state.status!.dimensionLabel}  '
                  '·  Supported formats: PNG, JPEG, BMP',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
            if (state.errorMessage != null) ...[
              const SizedBox(height: 12),
              AppErrorBanner(message: state.errorMessage!),
            ],
            if (state.noticeMessage != null) ...[
              const SizedBox(height: 12),
              AppNoticeBanner(message: state.noticeMessage!),
            ],
            if (state.status != null) ...[
              const SizedBox(height: 16),
              const PrivilegedActionNotice(),
              const SizedBox(height: 8),
              _ActionRow(
                canApply: state.canApply,
                isApplying: state.isApplying,
                onApply: () => _applyLogo(context, bloc),
                onRestore: () => _restoreLogo(context, bloc),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Future<void> _pickFile(BuildContext context, BootLogoBloc bloc) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'bmp'],
      dialogTitle: 'Select Boot Logo Image',
    );
    final path = result?.files.single.path;
    if (path != null) {
      bloc.add(BootLogoFileSelected(path));
    }
  }

  Future<void> _applyLogo(BuildContext context, BootLogoBloc bloc) async {
    final confirmed = await confirmPrivilegedAction(
      context: context,
      title: 'Apply Boot Logo',
      message:
          'This will write your image to the EFI partition and modify UEFI '
          'variables. Changes take effect on next reboot. Continue?',
    );
    if (confirmed && context.mounted) {
      bloc.add(const BootLogoApplyRequested());
    }
  }

  Future<void> _restoreLogo(BuildContext context, BootLogoBloc bloc) async {
    final confirmed = await confirmPrivilegedAction(
      context: context,
      title: 'Restore Default Logo',
      message:
          'This will clear the custom boot logo flag in UEFI variables. The '
          'stock Lenovo logo will appear on next reboot. Continue?',
    );
    if (confirmed && context.mounted) {
      bloc.add(const BootLogoRestoreRequested());
    }
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.isCustomEnabled,
    required this.dimensionLabel,
  });

  final bool isCustomEnabled;
  final String dimensionLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          isCustomEnabled ? Icons.check_circle_outline : Icons.radio_button_unchecked,
          size: 18,
          color: isCustomEnabled
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.outline,
        ),
        const SizedBox(width: 8),
        Text(
          isCustomEnabled ? 'Custom logo active' : 'Stock logo active',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}

class _FilePickerRow extends StatelessWidget {
  const _FilePickerRow({
    required this.selectedPath,
    required this.validationError,
    required this.isApplying,
    required this.onPick,
    required this.onClear,
  });

  final String? selectedPath;
  final String? validationError;
  final bool isApplying;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final hasPath = selectedPath != null && selectedPath!.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: hasPath
                  ? Text(
                      selectedPath!,
                      style: Theme.of(context).textTheme.bodyMedium,
                      overflow: TextOverflow.ellipsis,
                    )
                  : Text(
                      'No image selected',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                    ),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: isApplying ? null : onPick,
              icon: const Icon(Icons.folder_open_outlined, size: 16),
              label: const Text('Browse…'),
            ),
            if (hasPath) ...[
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.clear, size: 16),
                onPressed: isApplying ? null : onClear,
                tooltip: 'Clear selection',
              ),
            ],
          ],
        ),
        if (validationError != null) ...[
          const SizedBox(height: 4),
          Text(
            validationError!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
          ),
        ],
      ],
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.canApply,
    required this.isApplying,
    required this.onApply,
    required this.onRestore,
  });

  final bool canApply;
  final bool isApplying;
  final VoidCallback onApply;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        FilledButton(
          onPressed: canApply ? onApply : null,
          child: isApplying
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Apply Custom Logo'),
        ),
        const SizedBox(width: 12),
        OutlinedButton(
          onPressed: isApplying ? null : onRestore,
          child: const Text('Restore Default'),
        ),
      ],
    );
  }
}
```

**NOTE on `_FilePickerRow.onClear`:** Passing an empty string triggers `BootLogoFileSelected('')` in the bloc, which produces a validation error. Instead, the bloc should treat an empty path as a clear. Add this guard to `_onFileSelected` in the bloc:

```dart
void _onFileSelected(...) {
  final path = event.imagePath;
  if (path.isEmpty) {
    // User cleared the selection
    emit(state.copyWith(selectedImagePath: null, validationError: null));
    return;
  }
  // ... rest of extension validation
}
```

Update the bloc's `_onFileSelected` with this guard before proceeding.

**Step 3: Check widget names against actual codebase**

Before finalizing, verify these widget names exist in `lib/core/widgets/app_shell_components.dart`:
- `AppPageScaffold` / `AppSectionCard` / `AppRefreshButton`
- `PrivilegedActionNotice`
- `confirmPrivilegedAction`
- `AppUnavailableNotice` / `AppErrorBanner` / `AppNoticeBanner`

If any name differs, adjust to match. Read the file: `lib/core/widgets/app_shell_components.dart`.

**Step 4: Verify compilation**

```bash
cd frontend/legion_frontend
flutter analyze
```

Expected: No issues. Fix any widget naming mismatches found in Step 3.

**Step 5: Commit**

```bash
git add lib/features/boot_logo/view/boot_logo_page.dart
git commit -m "feat(boot-logo): add BootLogoPage with file picker, status, and apply/restore UI"
```

---

### Task 8: Final verification

**Step 1: Run full test suite**

```bash
cd frontend/legion_frontend
flutter test --reporter=expanded
```

Expected: all tests pass (target: 130+ tests — 114 existing + 7 status + 16 state).

**Step 2: Run analyzer**

```bash
flutter analyze
```

Expected: No issues.

**Step 3: Commit (only if cleanup was needed)**

```bash
git commit -m "fix: resolve analyzer warnings in boot logo feature"
```
