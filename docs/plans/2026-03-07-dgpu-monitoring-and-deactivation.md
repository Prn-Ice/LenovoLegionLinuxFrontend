# dGPU Monitoring and Deactivation — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a dGPU page showing NVIDIA GPU active state and compute processes (wkz), with privileged kill-processes and restart-PCI-device actions (6ad).

**Architecture:** New `dgpu` feature slice + new `AppSection.dgpu` nav entry. GPU active state is read from sysfs `power/runtime_status` (unprivileged, no GPU wakeup). Process list comes from `nvidia-smi --query-compute-apps` (unprivileged). Two new `legion_cli.py` subcommands (`dgpu kill-processes`, `dgpu restart-pci`) handle the privileged deactivation actions and are routed through the existing bridge/pkexec infrastructure. Both features live on one page; the deactivation actions are only shown when the GPU is available.

**Tech Stack:** Flutter, riverbloc, equatable, `dart:io`, `legion_cli.py` (Python changes)

**NOTE:** All `flutter` commands must run from `frontend/legion_frontend/` (direnv). Python changes are in `python/legion_linux/legion_linux/legion_cli.py`.

**Backend surface:**
- `NVIDIAGPUIsRunning` reads `/sys/bus/pci/devices/0000:01:00.0/power/runtime_status` → `"active"` or `"suspended"` (legion.py:635)
- `nvidia-smi --query-compute-apps=pid,process_name,used_gpu_memory --format=csv,noheader,nounits` → CSV process list
- PCI address discovery: scan `/sys/bus/pci/devices/*/vendor` for NVIDIA vendor `0x10de` with display class `0x03xxxx`
- `dgpu kill-processes` (new): query compute process PIDs via nvidia-smi, kill -9 each (requires root)
- `dgpu restart-pci` (new): write `1` to `<addr>/remove`, then `1` to `/sys/bus/pci/rescan` (requires root)

**Files touched:**
- `python/legion_linux/legion_linux/legion_cli.py` — two new subcommands
- `lib/features/dgpu/models/dgpu_process.dart` — new
- `lib/features/dgpu/models/dgpu_snapshot.dart` — new
- `lib/features/dgpu/bloc/dgpu_state.dart` — new
- `lib/features/dgpu/bloc/dgpu_event.dart` — new
- `lib/features/dgpu/bloc/dgpu_bloc.dart` — new
- `lib/features/dgpu/repository/dgpu_repository.dart` — new
- `lib/features/dgpu/providers/dgpu_provider.dart` — new
- `lib/features/dgpu/view/dgpu_page.dart` — new
- `lib/features/navigation/models/app_section.dart` — add `dgpu`
- `lib/features/navigation/view/navigation_shell.dart` — wire `DgpuPage`
- `test/features/dgpu/dgpu_process_test.dart` — new
- `test/features/dgpu/dgpu_state_test.dart` — new

---

### Task 1: Python — add dgpu subcommands to legion_cli.py

**Files:**
- Modify: `python/legion_linux/legion_linux/legion_cli.py`

**Step 1: Add helper function `_find_nvidia_pci_address`**

After the `boot_logo_status` function (around line 464), add:

```python
def _find_nvidia_pci_address():
    """Return the PCI address string of the NVIDIA discrete GPU, or None."""
    import glob
    for vendor_path in glob.glob('/sys/bus/pci/devices/*/vendor'):
        try:
            with open(vendor_path) as f:
                if f.read().strip() != '0x10de':
                    continue
            class_path = vendor_path.replace('vendor', 'class')
            with open(class_path) as f:
                device_class = int(f.read().strip(), 16)
            if (device_class >> 16) == 0x03:  # Display controller
                return vendor_path.split('/')[-2]
        except (IOError, ValueError):
            continue
    return None


def dgpu_kill_processes(**kwargs) -> int:
    """Kill all compute processes using the NVIDIA GPU (requires root)."""
    try:
        result = subprocess.run(
            ['nvidia-smi', '--query-compute-apps=pid', '--format=csv,noheader'],
            capture_output=True, text=True, timeout=10,
        )
        if result.returncode != 0:
            print(f"nvidia-smi failed: {result.stderr.strip()}")
            return 1
        pids = [line.strip() for line in result.stdout.strip().splitlines() if line.strip().isdigit()]
        if not pids:
            print("No compute processes found on GPU.")
            return 0
        import signal
        for pid_str in pids:
            try:
                os.kill(int(pid_str), signal.SIGKILL)
                print(f"Killed PID {pid_str}")
            except (ProcessLookupError, PermissionError) as e:
                print(f"Could not kill PID {pid_str}: {e}")
        return 0
    except FileNotFoundError:
        print("nvidia-smi not found. Is the NVIDIA driver installed?")
        return 1
    except Exception as e:
        print(f"Error killing GPU processes: {e}")
        return 1


def dgpu_restart_pci(**kwargs) -> int:
    """Remove the NVIDIA GPU from the PCI tree and rescan to reinitialise it (requires root)."""
    addr = _find_nvidia_pci_address()
    if not addr:
        print("Could not find NVIDIA GPU PCI address.")
        return 1
    try:
        remove_path = f"/sys/bus/pci/devices/{addr}/remove"
        with open(remove_path, 'w') as f:
            f.write('1')
        print(f"Removed PCI device {addr}")
        rescan_path = "/sys/bus/pci/rescan"
        with open(rescan_path, 'w') as f:
            f.write('1')
        print("PCI bus rescanned — device should reappear.")
        return 0
    except (IOError, PermissionError) as e:
        print(f"PCI operation failed: {e}")
        return 1
```

**NOTE:** `subprocess` and `os` are already imported at the top of `legion_cli.py`. Verify `import os` is present; if not, add it.

**Step 2: Register subcommands in `create_argparser()`**

In `create_argparser()`, before `return parser, subcommands`, add after the boot-logo block:

```python
    dgpu_parser = subcommands.add_parser('dgpu', help='Discrete GPU management')
    dgpu_sub = dgpu_parser.add_subparsers(dest='dgpu_cmd')
    dgpu_kill_parser = dgpu_sub.add_parser('kill-processes', help='Kill compute processes using the GPU')
    dgpu_kill_parser.set_defaults(func=lambda legion, **kw: dgpu_kill_processes(**kw))
    dgpu_restart_parser = dgpu_sub.add_parser('restart-pci', help='Remove and rescan GPU PCI device')
    dgpu_restart_parser.set_defaults(func=lambda legion, **kw: dgpu_restart_pci(**kw))
```

**Step 3: Verify the commands parse correctly (manual check)**

```bash
cd python/legion_linux
python -m legion_linux.legion_cli dgpu --help
python -m legion_linux.legion_cli dgpu kill-processes --help
python -m legion_linux.legion_cli dgpu restart-pci --help
```

Expected: help text shows for each subcommand.

**Step 4: Commit**

```bash
git add python/legion_linux/legion_linux/legion_cli.py
git commit -m "feat(dgpu): add dgpu kill-processes and restart-pci CLI subcommands"
```

---

### Task 2: DgpuProcess model + parsing tests

**Files:**
- Create: `lib/features/dgpu/models/dgpu_process.dart`
- Create: `test/features/dgpu/dgpu_process_test.dart`

**Step 1: Write failing tests**

```dart
// test/features/dgpu/dgpu_process_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/dgpu/models/dgpu_process.dart';

void main() {
  group('DgpuProcess.parseNvidiaSmiOutput', () {
    test('parses single process line', () {
      final result = DgpuProcess.parseNvidiaSmiOutput('1234, /usr/bin/Xorg, 4\n');
      expect(result, hasLength(1));
      expect(result.first.pid, equals(1234));
      expect(result.first.name, equals('Xorg'));
      expect(result.first.usedMemoryMib, equals(4));
    });

    test('parses multiple lines', () {
      const output = '1234, /usr/bin/Xorg, 4\n5678, blender, 2048\n';
      final result = DgpuProcess.parseNvidiaSmiOutput(output);
      expect(result, hasLength(2));
      expect(result[1].pid, equals(5678));
      expect(result[1].usedMemoryMib, equals(2048));
    });

    test('returns empty list for empty output', () {
      expect(DgpuProcess.parseNvidiaSmiOutput(''), isEmpty);
      expect(DgpuProcess.parseNvidiaSmiOutput('\n'), isEmpty);
    });

    test('skips malformed lines', () {
      const output = 'not_a_number, Xorg, 4\n9999, blender, 1024\n';
      final result = DgpuProcess.parseNvidiaSmiOutput(output);
      expect(result, hasLength(1));
      expect(result.first.pid, equals(9999));
    });

    test('uses base name when full path is given', () {
      final result = DgpuProcess.parseNvidiaSmiOutput('42, /usr/lib/xorg/Xorg, 10\n');
      expect(result.first.name, equals('Xorg'));
    });

    test('preserves name when no slash', () {
      final result = DgpuProcess.parseNvidiaSmiOutput('42, blender, 10\n');
      expect(result.first.name, equals('blender'));
    });

    test('equality based on all fields', () {
      const a = DgpuProcess(pid: 1, name: 'Xorg', usedMemoryMib: 4);
      const b = DgpuProcess(pid: 1, name: 'Xorg', usedMemoryMib: 4);
      const c = DgpuProcess(pid: 2, name: 'Xorg', usedMemoryMib: 4);
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });
}
```

**Step 2: Run test — expect failure**

```bash
cd frontend/legion_frontend
flutter test test/features/dgpu/dgpu_process_test.dart -v
```

Expected: compile error — file doesn't exist.

**Step 3: Write the model**

```dart
// lib/features/dgpu/models/dgpu_process.dart
import 'package:equatable/equatable.dart';

class DgpuProcess extends Equatable {
  const DgpuProcess({
    required this.pid,
    required this.name,
    required this.usedMemoryMib,
  });

  final int pid;
  final String name;
  final int usedMemoryMib;

  /// Parses output of:
  /// nvidia-smi --query-compute-apps=pid,process_name,used_gpu_memory
  ///            --format=csv,noheader,nounits
  ///
  /// Each line: "<pid>, <process_name>, <used_memory_MiB>"
  static List<DgpuProcess> parseNvidiaSmiOutput(String output) {
    final processes = <DgpuProcess>[];
    for (final line in output.trim().split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final parts = trimmed.split(',');
      if (parts.length < 3) continue;
      final pid = int.tryParse(parts[0].trim());
      if (pid == null) continue;
      final rawName = parts[1].trim();
      final name = rawName.contains('/') ? rawName.split('/').last : rawName;
      final mem = int.tryParse(parts[2].trim()) ?? 0;
      processes.add(DgpuProcess(pid: pid, name: name, usedMemoryMib: mem));
    }
    return processes;
  }

  @override
  List<Object?> get props => [pid, name, usedMemoryMib];
}
```

**Step 4: Run tests — expect pass**

```bash
flutter test test/features/dgpu/dgpu_process_test.dart -v
```

Expected: 7 tests pass.

**Step 5: Create snapshot model**

```dart
// lib/features/dgpu/models/dgpu_snapshot.dart
import 'dgpu_process.dart';

class DgpuSnapshot {
  const DgpuSnapshot({
    required this.isActive,
    required this.processes,
    required this.pciAddress,
  });

  /// null = GPU sysfs path not found (not available / not NVIDIA)
  final bool? isActive;

  /// Empty if nvidia-smi is not installed or reports no processes.
  final List<DgpuProcess> processes;

  /// The discovered PCI address (e.g. "0000:01:00.0"), or null if not found.
  final String? pciAddress;
}
```

**Step 6: Commit**

```bash
git add \
  lib/features/dgpu/models/dgpu_process.dart \
  lib/features/dgpu/models/dgpu_snapshot.dart \
  test/features/dgpu/dgpu_process_test.dart
git commit -m "feat(dgpu): add DgpuProcess model with nvidia-smi parser and DgpuSnapshot"
```

---

### Task 3: DgpuState, DgpuEvent, state tests

**Files:**
- Create: `lib/features/dgpu/bloc/dgpu_state.dart`
- Create: `lib/features/dgpu/bloc/dgpu_event.dart`
- Create: `test/features/dgpu/dgpu_state_test.dart`

**Step 1: Write state tests first**

```dart
// test/features/dgpu/dgpu_state_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/dgpu/bloc/dgpu_state.dart';
import 'package:legion_frontend/features/dgpu/models/dgpu_process.dart';

const _proc = DgpuProcess(pid: 1234, name: 'Xorg', usedMemoryMib: 4);

void main() {
  group('DgpuState.initial', () {
    test('isActive is null', () {
      expect(DgpuState.initial().isActive, isNull);
    });

    test('processes is empty', () {
      expect(DgpuState.initial().processes, isEmpty);
    });

    test('isLoading and isApplying are false', () {
      final s = DgpuState.initial();
      expect(s.isLoading, isFalse);
      expect(s.isApplying, isFalse);
    });

    test('errorMessage and noticeMessage are null', () {
      final s = DgpuState.initial();
      expect(s.errorMessage, isNull);
      expect(s.noticeMessage, isNull);
    });
  });

  group('DgpuState.isAvailable', () {
    test('false when isActive is null', () {
      expect(DgpuState.initial().isAvailable, isFalse);
    });

    test('true when isActive is set (even false)', () {
      final s = DgpuState.initial().copyWith(isActive: false);
      expect(s.isAvailable, isTrue);
    });

    test('true when isActive is true', () {
      final s = DgpuState.initial().copyWith(isActive: true);
      expect(s.isAvailable, isTrue);
    });
  });

  group('DgpuState.copyWith sentinel', () {
    test('copyWith with no args returns equal state', () {
      expect(DgpuState.initial().copyWith(), equals(DgpuState.initial()));
    });

    test('copyWith(isActive: null) clears it', () {
      final s = DgpuState.initial()
          .copyWith(isActive: true)
          .copyWith(isActive: null);
      expect(s.isActive, isNull);
    });

    test('copyWith omitting isActive preserves it', () {
      final s = DgpuState.initial()
          .copyWith(isActive: true)
          .copyWith(isLoading: true);
      expect(s.isActive, isTrue);
    });

    test('copyWith(errorMessage: null) clears it', () {
      final s = DgpuState.initial()
          .copyWith(errorMessage: 'oops')
          .copyWith(errorMessage: null);
      expect(s.errorMessage, isNull);
    });

    test('copyWith(processes: ...) sets list', () {
      final s = DgpuState.initial().copyWith(processes: [_proc]);
      expect(s.processes, hasLength(1));
    });

    test('copyWith(pciAddress: null) clears it', () {
      final s = DgpuState.initial()
          .copyWith(pciAddress: '0000:01:00.0')
          .copyWith(pciAddress: null);
      expect(s.pciAddress, isNull);
    });
  });

  group('DgpuState props', () {
    test('identical initial states are equal', () {
      expect(DgpuState.initial(), equals(DgpuState.initial()));
    });

    test('differ when isActive differs', () {
      final a = DgpuState.initial().copyWith(isActive: true);
      final b = DgpuState.initial().copyWith(isActive: false);
      expect(a, isNot(equals(b)));
    });

    test('differ when processes differ', () {
      final a = DgpuState.initial().copyWith(processes: [_proc]);
      final b = DgpuState.initial();
      expect(a, isNot(equals(b)));
    });
  });
}
```

**Step 2: Run tests — expect failure**

```bash
flutter test test/features/dgpu/dgpu_state_test.dart -v
```

Expected: compile error — files don't exist.

**Step 3: Write DgpuState**

```dart
// lib/features/dgpu/bloc/dgpu_state.dart
import 'package:equatable/equatable.dart';

import '../models/dgpu_process.dart';

class DgpuState extends Equatable {
  const DgpuState({
    required this.isActive,
    required this.processes,
    required this.pciAddress,
    required this.isLoading,
    required this.isApplying,
    required this.errorMessage,
    required this.noticeMessage,
  });

  factory DgpuState.initial() => const DgpuState(
    isActive: null,
    processes: [],
    pciAddress: null,
    isLoading: false,
    isApplying: false,
    errorMessage: null,
    noticeMessage: null,
  );

  static const _unset = Object();

  /// null = sysfs runtime_status path not found (NVIDIA GPU unavailable)
  final bool? isActive;
  final List<DgpuProcess> processes;
  final String? pciAddress;
  final bool isLoading;
  final bool isApplying;
  final String? errorMessage;
  final String? noticeMessage;

  /// true when the GPU sysfs entry was found (even if suspended)
  bool get isAvailable => isActive != null;

  DgpuState copyWith({
    Object? isActive = _unset,
    List<DgpuProcess>? processes,
    Object? pciAddress = _unset,
    bool? isLoading,
    bool? isApplying,
    Object? errorMessage = _unset,
    Object? noticeMessage = _unset,
  }) {
    return DgpuState(
      isActive: isActive == _unset ? this.isActive : isActive as bool?,
      processes: processes ?? this.processes,
      pciAddress: pciAddress == _unset ? this.pciAddress : pciAddress as String?,
      isLoading: isLoading ?? this.isLoading,
      isApplying: isApplying ?? this.isApplying,
      errorMessage:
          errorMessage == _unset ? this.errorMessage : errorMessage as String?,
      noticeMessage:
          noticeMessage == _unset ? this.noticeMessage : noticeMessage as String?,
    );
  }

  @override
  List<Object?> get props => [
    isActive,
    processes,
    pciAddress,
    isLoading,
    isApplying,
    errorMessage,
    noticeMessage,
  ];
}
```

**Step 4: Write DgpuEvent**

```dart
// lib/features/dgpu/bloc/dgpu_event.dart
abstract class DgpuEvent {
  const DgpuEvent();
}

final class DgpuStarted extends DgpuEvent {
  const DgpuStarted();
}

final class DgpuRefreshRequested extends DgpuEvent {
  const DgpuRefreshRequested();
}

/// Kill all compute processes using the GPU (privileged).
final class DgpuKillProcessesRequested extends DgpuEvent {
  const DgpuKillProcessesRequested();
}

/// Remove the GPU from the PCI tree and rescan to reinitialise (privileged).
final class DgpuRestartPciRequested extends DgpuEvent {
  const DgpuRestartPciRequested();
}
```

**Step 5: Run state tests — expect pass**

```bash
flutter test test/features/dgpu/dgpu_state_test.dart -v
```

Expected: 15 tests pass.

**Step 6: Commit**

```bash
git add \
  lib/features/dgpu/bloc/dgpu_state.dart \
  lib/features/dgpu/bloc/dgpu_event.dart \
  test/features/dgpu/dgpu_state_test.dart
git commit -m "feat(dgpu): add DgpuState (sentinel copyWith) and DgpuEvent"
```

---

### Task 4: DgpuRepository

**Files:**
- Create: `lib/features/dgpu/repository/dgpu_repository.dart`

**Step 1: Write the repository**

```dart
// lib/features/dgpu/repository/dgpu_repository.dart
import 'dart:io';

import '../../../core/services/legion_frontend_bridge_service.dart';
import '../models/dgpu_process.dart';
import '../models/dgpu_snapshot.dart';

class DgpuRepositoryException implements Exception {
  const DgpuRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}

class DgpuRepository {
  const DgpuRepository({required LegionFrontendBridgeService bridgeService})
    : _bridgeService = bridgeService;

  final LegionFrontendBridgeService _bridgeService;

  static const _knownRuntimeStatusPath =
      '/sys/bus/pci/devices/0000:01:00.0/power/runtime_status';

  Future<DgpuSnapshot> loadSnapshot() async {
    final pciAddress = await _findNvidiaGpuPciAddress();
    final bool? isActive;
    if (pciAddress != null) {
      final runtimePath = '/sys/bus/pci/devices/$pciAddress/power/runtime_status';
      isActive = await _readRuntimeStatus(runtimePath);
    } else {
      isActive = null;
    }
    final processes = await _queryComputeProcesses();
    return DgpuSnapshot(
      isActive: isActive,
      processes: processes,
      pciAddress: pciAddress,
    );
  }

  Future<void> killGpuProcesses() async {
    await _runPrivilegedCommand(
      ['dgpu', 'kill-processes'],
      method: 'dgpu.kill_processes',
      failurePrefix: 'Failed to kill GPU processes',
      timeout: const Duration(seconds: 15),
    );
  }

  Future<void> restartPciDevice() async {
    await _runPrivilegedCommand(
      ['dgpu', 'restart-pci'],
      method: 'dgpu.restart_pci',
      failurePrefix: 'Failed to restart GPU PCI device',
      timeout: const Duration(seconds: 20),
    );
  }

  /// Returns the PCI address of the NVIDIA discrete GPU.
  /// Tries the known address first; falls back to scanning /sys/bus/pci/devices/.
  Future<String?> _findNvidiaGpuPciAddress() async {
    // Fast path: try the well-known address first.
    final knownStatusFile = File(_knownRuntimeStatusPath);
    if (await knownStatusFile.exists()) {
      return '0000:01:00.0';
    }

    // Scan for NVIDIA vendor ID 0x10de with display class 0x03xxxx.
    final devicesDir = Directory('/sys/bus/pci/devices');
    if (!await devicesDir.exists()) return null;

    try {
      await for (final entity in devicesDir.list(followLinks: false)) {
        if (entity is! Directory) continue;
        final vendorFile = File('${entity.path}/vendor');
        if (!await vendorFile.exists()) continue;
        final vendor = (await vendorFile.readAsString()).trim();
        if (vendor != '0x10de') continue;
        final classFile = File('${entity.path}/class');
        if (!await classFile.exists()) continue;
        final classHex = (await classFile.readAsString()).trim().replaceFirst('0x', '');
        final deviceClass = int.tryParse(classHex, radix: 16);
        if (deviceClass == null || (deviceClass >> 16) != 0x03) continue;
        final runtimeFile = File('${entity.path}/power/runtime_status');
        if (await runtimeFile.exists()) {
          return entity.path.split('/').last;
        }
      }
    } catch (_) {}

    return null;
  }

  Future<bool?> _readRuntimeStatus(String path) async {
    try {
      final value = (await File(path).readAsString()).trim();
      return value != 'suspended';
    } catch (_) {
      return null;
    }
  }

  /// Queries NVIDIA compute processes via nvidia-smi.
  /// Returns empty list if nvidia-smi is not installed or fails.
  Future<List<DgpuProcess>> _queryComputeProcesses() async {
    try {
      final result = await Process.run('nvidia-smi', [
        '--query-compute-apps=pid,process_name,used_gpu_memory',
        '--format=csv,noheader,nounits',
      ]).timeout(const Duration(seconds: 8));
      if (result.exitCode != 0) return [];
      return DgpuProcess.parseNvidiaSmiOutput('${result.stdout}');
    } catch (_) {
      return [];
    }
  }

  Future<void> _runPrivilegedCommand(
    List<String> args, {
    required String method,
    required String failurePrefix,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    try {
      await _bridgeService.runPrivilegedCommand(
        method: method,
        args: args,
        timeout: timeout,
      );
    } on LegionBridgeException catch (error) {
      final details = error.details;
      final message =
          details.isEmpty ? '$failurePrefix.' : '$failurePrefix: $details';
      throw DgpuRepositoryException(message);
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
git add lib/features/dgpu/repository/dgpu_repository.dart
git commit -m "feat(dgpu): add DgpuRepository with sysfs read, nvidia-smi query, and privileged actions"
```

---

### Task 5: DgpuBloc

**Files:**
- Create: `lib/features/dgpu/bloc/dgpu_bloc.dart`

**Step 1: Write the bloc**

```dart
// lib/features/dgpu/bloc/dgpu_bloc.dart
import 'package:riverbloc/riverbloc.dart';

import '../repository/dgpu_repository.dart';
import 'dgpu_event.dart';
import 'dgpu_state.dart';

class DgpuBloc extends Bloc<DgpuEvent, DgpuState> {
  DgpuBloc({required DgpuRepository repository})
    : _repository = repository,
      super(DgpuState.initial()) {
    on<DgpuStarted>(_onStarted);
    on<DgpuRefreshRequested>(_onRefreshRequested);
    on<DgpuKillProcessesRequested>(_onKillProcessesRequested);
    on<DgpuRestartPciRequested>(_onRestartPciRequested);
  }

  final DgpuRepository _repository;

  Future<void> _onStarted(
    DgpuStarted event,
    Emitter<DgpuState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, errorMessage: null));
    await _reloadState(emit);
  }

  Future<void> _onRefreshRequested(
    DgpuRefreshRequested event,
    Emitter<DgpuState> emit,
  ) async {
    await _reloadState(emit);
  }

  Future<void> _onKillProcessesRequested(
    DgpuKillProcessesRequested event,
    Emitter<DgpuState> emit,
  ) async {
    if (state.isApplying) return;
    emit(state.copyWith(isApplying: true, errorMessage: null, noticeMessage: null));
    try {
      await _repository.killGpuProcesses();
      await _reloadState(emit, noticeMessage: 'GPU processes killed.');
    } on DgpuRepositoryException catch (error) {
      emit(state.copyWith(isApplying: false, errorMessage: error.message));
    }
  }

  Future<void> _onRestartPciRequested(
    DgpuRestartPciRequested event,
    Emitter<DgpuState> emit,
  ) async {
    if (state.isApplying) return;
    emit(state.copyWith(isApplying: true, errorMessage: null, noticeMessage: null));
    try {
      await _repository.restartPciDevice();
      await _reloadState(
        emit,
        noticeMessage: 'PCI device restarted. The GPU will reinitialise shortly.',
      );
    } on DgpuRepositoryException catch (error) {
      emit(state.copyWith(isApplying: false, errorMessage: error.message));
    }
  }

  Future<void> _reloadState(
    Emitter<DgpuState> emit, {
    String? noticeMessage,
  }) async {
    try {
      final snapshot = await _repository.loadSnapshot();
      emit(state.copyWith(
        isActive: snapshot.isActive,
        processes: snapshot.processes,
        pciAddress: snapshot.pciAddress,
        isLoading: false,
        isApplying: false,
        noticeMessage: noticeMessage,
      ));
    } catch (error) {
      emit(state.copyWith(
        isLoading: false,
        isApplying: false,
        errorMessage: 'Failed to load GPU status: $error',
      ));
    }
  }
}
```

**Step 2: Verify**

```bash
flutter analyze
```

Expected: No issues.

**Step 3: Commit**

```bash
git add lib/features/dgpu/bloc/dgpu_bloc.dart
git commit -m "feat(dgpu): add DgpuBloc with load, kill-processes, restart-pci handlers"
```

---

### Task 6: Provider + navigation wiring

**Files:**
- Create: `lib/features/dgpu/providers/dgpu_provider.dart`
- Modify: `lib/features/navigation/models/app_section.dart`
- Modify: `lib/features/navigation/view/navigation_shell.dart`

**Step 1: Create provider**

```dart
// lib/features/dgpu/providers/dgpu_provider.dart
import 'package:riverbloc/riverbloc.dart';

import '../../../core/providers/system_services_provider.dart';
import '../bloc/dgpu_bloc.dart';
import '../bloc/dgpu_event.dart';
import '../bloc/dgpu_state.dart';
import '../repository/dgpu_repository.dart';

final dgpuRepositoryProvider = Provider<DgpuRepository>((ref) {
  final bridgeService = ref.watch(legionBridgeServiceProvider);
  return DgpuRepository(bridgeService: bridgeService);
});

final dgpuBlocProvider =
    BlocProvider.autoDispose<DgpuBloc, DgpuState>((ref) {
      final repository = ref.watch(dgpuRepositoryProvider);
      return DgpuBloc(repository: repository)..add(const DgpuStarted());
    });
```

**Step 2: Add `dgpu` to AppSection**

In `lib/features/navigation/models/app_section.dart`:

- Add `dgpu,` to the enum (place between `displayLighting` and `automation`)
- `label` → `case AppSection.dgpu: return 'Discrete GPU';`
- `icon` → `case AppSection.dgpu: return Icons.memory_outlined;`
- `yaruIcon` → `case AppSection.dgpu: return YaruIcons.chip;`

**Step 3: Wire DgpuPage in navigation_shell.dart**

- Add import: `import '../../dgpu/view/dgpu_page.dart';`
- In `_buildPage`: `case AppSection.dgpu: return const DgpuPage();`

**Step 4: Verify**

```bash
flutter analyze
```

Expected: error that `DgpuPage` doesn't exist yet — that's expected and fine at this step. Alternatively, create a stub `DgpuPage` first:

```dart
// lib/features/dgpu/view/dgpu_page.dart (stub — will be replaced in Task 7)
import 'package:flutter/material.dart';
class DgpuPage extends StatelessWidget {
  const DgpuPage({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
```

Then run `flutter analyze` — expect no issues.

**Step 5: Commit**

```bash
git add \
  lib/features/dgpu/providers/dgpu_provider.dart \
  lib/features/dgpu/view/dgpu_page.dart \
  lib/features/navigation/models/app_section.dart \
  lib/features/navigation/view/navigation_shell.dart
git commit -m "feat(dgpu): register provider and add Discrete GPU nav section"
```

---

### Task 7: DgpuPage view

**Files:**
- Modify (rewrite): `lib/features/dgpu/view/dgpu_page.dart`

**Step 1: Read existing page for widget names**

Before writing, confirm the exact widget names in `lib/core/widgets/app_shell_components.dart`:
- `AppPageBody`, `AppSectionCard`, `AppRefreshButton`
- `PrivilegedActionNotice`
- `confirmPrivilegedAction`
- `AppUnavailableNotice`, `AppErrorBanner`, `AppNoticeBanner`

Adjust the code below if any name differs.

**Step 2: Write the full page**

```dart
// lib/features/dgpu/view/dgpu_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yaru/yaru.dart';

import '../../../core/widgets/app_shell_components.dart';
import '../../../core/widgets/privileged_action_notice.dart';
import '../bloc/dgpu_bloc.dart';
import '../bloc/dgpu_event.dart';
import '../bloc/dgpu_state.dart';
import '../models/dgpu_process.dart';
import '../providers/dgpu_provider.dart';

class DgpuPage extends ConsumerWidget {
  const DgpuPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(dgpuBlocProvider);
    final bloc = ref.read(dgpuBlocProvider.bloc);

    if (state.isLoading && !state.isAvailable) {
      return const Center(child: YaruCircularProgressIndicator());
    }

    return AppPageBody(
      title: 'Discrete GPU',
      errorMessage: state.errorMessage,
      children: [
        AppSectionCard(
          title: 'Status',
          children: [
            AppRefreshButton(
              isLoading: state.isLoading,
              onPressed: () => bloc.add(const DgpuRefreshRequested()),
            ),
            if (!state.isAvailable)
              const AppUnavailableNotice(
                message:
                    'NVIDIA GPU not detected. This feature requires a Lenovo '
                    'Legion with NVIDIA discrete graphics in hybrid mode.',
              )
            else ...[
              _StatusRow(isActive: state.isActive!),
              if (state.pciAddress != null) ...[
                const SizedBox(height: 4),
                Text(
                  'PCI address: ${state.pciAddress}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ],
        ),
        if (state.isAvailable) ...[
          const SizedBox(height: 16),
          AppSectionCard(
            title: 'Compute Processes',
            children: [
              if (state.processes.isEmpty)
                Text(
                  'No compute processes on GPU.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                )
              else
                _ProcessTable(processes: state.processes),
              const SizedBox(height: 4),
              Text(
                'Shows CUDA/compute processes only. Display server processes '
                '(Xorg, Wayland compositor) may not appear here.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 16),
          AppSectionCard(
            title: 'Deactivation',
            children: [
              if (state.noticeMessage != null) ...[
                AppNoticeBanner(message: state.noticeMessage!),
                const SizedBox(height: 8),
              ],
              Text(
                'Kill GPU processes before restarting the PCI device. '
                'Restarting the PCI device will briefly remove the GPU from '
                'the system. Save any work before proceeding.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              const PrivilegedActionNotice(),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: state.isApplying
                        ? null
                        : () => _killProcesses(context, bloc),
                    icon: state.isApplying
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: YaruCircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.close_outlined, size: 16),
                    label: const Text('Kill GPU Processes'),
                  ),
                  OutlinedButton.icon(
                    onPressed: state.isApplying
                        ? null
                        : () => _restartPci(context, bloc),
                    icon: const Icon(Icons.refresh_outlined, size: 16),
                    label: const Text('Restart PCI Device'),
                  ),
                ],
              ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _killProcesses(BuildContext context, DgpuBloc bloc) async {
    final confirmed = await confirmPrivilegedAction(
      context,
      title: 'Kill GPU Processes',
      message:
          'This will send SIGKILL to all compute processes using the GPU. '
          'Applications may lose unsaved work. Continue?',
      confirmLabel: 'Kill processes',
    );
    if (confirmed && context.mounted) {
      bloc.add(const DgpuKillProcessesRequested());
    }
  }

  Future<void> _restartPci(BuildContext context, DgpuBloc bloc) async {
    final confirmed = await confirmPrivilegedAction(
      context,
      title: 'Restart PCI Device',
      message:
          'This will remove the GPU from the PCI tree and rescan to '
          'reinitialise it. The GPU will briefly disappear from the system. '
          'Kill GPU processes first. Continue?',
      confirmLabel: 'Restart device',
    );
    if (confirmed && context.mounted) {
      bloc.add(const DgpuRestartPciRequested());
    }
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.isActive});

  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          isActive ? Icons.memory : Icons.power_settings_new_outlined,
          size: 18,
          color: isActive
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.outline,
        ),
        const SizedBox(width: 8),
        Text(
          isActive ? 'GPU active' : 'GPU suspended (D3cold)',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}

class _ProcessTable extends StatelessWidget {
  const _ProcessTable({required this.processes});

  final List<DgpuProcess> processes;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 36,
        dataRowMinHeight: 32,
        dataRowMaxHeight: 36,
        columns: const [
          DataColumn(label: Text('PID')),
          DataColumn(label: Text('Process')),
          DataColumn(label: Text('GPU Mem'), numeric: true),
        ],
        rows: [
          for (final p in processes)
            DataRow(cells: [
              DataCell(Text('${p.pid}')),
              DataCell(Text(p.name)),
              DataCell(Text('${p.usedMemoryMib} MiB')),
            ]),
        ],
      ),
    );
  }
}
```

**Step 3: Verify compilation**

```bash
cd frontend/legion_frontend
flutter analyze
```

Expected: No issues. Fix any widget name mismatches found in Step 1.

**Step 4: Commit**

```bash
git add lib/features/dgpu/view/dgpu_page.dart
git commit -m "feat(dgpu): add DgpuPage with status, process table, and kill/restart actions"
```

---

### Task 8: Final verification

**Step 1: Run full test suite**

```bash
cd frontend/legion_frontend
flutter test --reporter=expanded
```

Expected: all tests pass (target: 169+ — 147 existing + 7 process + 15 state = 169).

**Step 2: Run analyzer**

```bash
flutter analyze
```

Expected: No issues.

**Step 3: Confirm Python changes parse**

```bash
cd python/legion_linux
python -m legion_linux.legion_cli dgpu --help
```

Expected: shows `kill-processes` and `restart-pci` subcommands.

**Step 4: Commit (if any cleanup needed)**

```bash
git commit -m "fix: resolve warnings in dgpu feature"
```
