import 'dart:io';

import '../../../core/data/privileged_repository.dart';
import '../../../core/models/app_failure.dart';
import '../../../core/models/gpu_process.dart';
import '../../../core/services/legion_frontend_bridge_service.dart';
import '../models/dgpu_snapshot.dart';
import '../models/graphics_mode.dart';

class DgpuRepositoryException extends AppFailure {
  const DgpuRepositoryException(super.message, {super.kind, super.details});
}

class DgpuRepository extends PrivilegedRepository {
  const DgpuRepository({
    required super.bridgeService,
    this.findPciAddress,
    this.readRuntimeStatus,
    this.queryComputeProcesses,
    this.queryPciName,
  });

  /// Callbacks replace PCI and process reads in hardware-free tests.
  /// Omitted callbacks use the sysfs and process readers below.
  final Future<String?> Function()? findPciAddress;
  final Future<bool?> Function(String path)? readRuntimeStatus;
  final Future<List<GpuProcess>> Function()? queryComputeProcesses;
  final Future<String?> Function(String pciAddress)? queryPciName;

  @override
  Exception wrapBridgeError(AppFailure failure) => DgpuRepositoryException(
    failure.message,
    kind: failure.kind,
    details: failure.details,
  );

  static const _knownRuntimeStatusPath =
      '/sys/bus/pci/devices/0000:01:00.0/power/runtime_status';

  Future<DgpuSnapshot> loadSnapshot() => _loadSnapshot();

  Future<DgpuSnapshot> loadSnapshotAfterGraphicsWrite() =>
      _loadSnapshot(requireGraphicsModeStatus: true);

  Future<DgpuSnapshot> _loadSnapshot({
    bool requireGraphicsModeStatus = false,
  }) async {
    final results = await Future.wait([
      findPciAddress?.call() ?? _findNvidiaGpuPciAddress(),
      loadGraphicsModeStatus(required: requireGraphicsModeStatus),
    ]);
    final pciAddress = results[0] as String?;
    final graphicsModeStatus = results[1] as GraphicsModeStatus?;

    final bool? isActive;
    if (pciAddress != null) {
      final runtimePath =
          '/sys/bus/pci/devices/$pciAddress/power/runtime_status';
      isActive =
          await (readRuntimeStatus?.call(runtimePath) ??
              _readRuntimeStatus(runtimePath));
    } else {
      isActive = null;
    }
    final processes =
        await (queryComputeProcesses?.call() ?? _queryComputeProcesses());
    final name = pciAddress == null
        ? null
        : await (queryPciName?.call(pciAddress) ?? _queryPciName(pciAddress));
    return DgpuSnapshot(
      isActive: isActive,
      processes: processes,
      pciAddress: pciAddress,
      graphicsModeStatus: graphicsModeStatus,
      name: name,
    );
  }

  Future<GraphicsModeStatus?> loadGraphicsModeStatus({
    bool required = false,
  }) async {
    try {
      final result = await bridgeService.runCommand(
        method: 'graphics_mode.status',
        args: const ['graphics-mode', 'status', '--json'],
        timeout: const Duration(seconds: 8),
        detectUnavailableResponse: false,
      );
      if (result.ok) {
        return GraphicsModeStatus.parse(result.stdout);
      }

      // Older legion_cli builds output JSON from `graphics-mode status` without
      // `--json` and list supported modes through `graphics-mode choices`.
      final legacyStatus = await bridgeService.runCommand(
        method: 'graphics_mode.status',
        args: const ['graphics-mode', 'status'],
        timeout: const Duration(seconds: 8),
        detectUnavailableResponse: false,
      );
      if (!legacyStatus.ok) {
        if (required) {
          throw DgpuRepositoryException(
            'Graphics mode and NVIDIA GPU status could not be reloaded after the '
            'mode request. Backend output: ${result.stderr}',
          );
        }
        return null;
      }
      final choicesResult = await bridgeService.runCommand(
        method: 'graphics_mode.choices',
        args: const ['graphics-mode', 'choices'],
        timeout: const Duration(seconds: 8),
        detectUnavailableResponse: false,
      );
      final availableModes = <GraphicsMode>[
        if (choicesResult.ok)
          for (final line in choicesResult.stdout.split('\n'))
            if (line.trim().isNotEmpty) GraphicsMode.parse(line.trim()),
      ];
      return GraphicsModeStatus.parseLegacyStatus(
        legacyStatus.stdout,
        availableModes,
      );
    } on DgpuRepositoryException {
      rethrow;
    } catch (error) {
      if (required) {
        final failure = AppFailure.from(error);
        throw DgpuRepositoryException(
          'Graphics mode and NVIDIA GPU status could not be reloaded after the mode '
          'request: $error',
          kind: failure.kind,
          details: failure.details,
        );
      }
      return null;
    }
  }

  Future<void> setGraphicsMode(GraphicsMode mode) async {
    if (mode == GraphicsMode.hybridAuto) {
      throw const DgpuRepositoryException(
        'Automatic graphics switching is not supported. Choose Hybrid instead.',
      );
    }

    try {
      await bridgeService.runControlOperation(
        operation: (client) => client.setGraphicsMode(mode),
        method: 'graphics_mode.set',
        args: [mode.wireValue],
        timeout: const Duration(seconds: 45),
      );
    } on LegionBridgeException catch (error) {
      switch (error.code) {
        case LegionBridgeErrorCode.graphicsBlocked:
          throw DgpuRepositoryException(
            '${mode.label} was not applied. Close applications using NVIDIA '
            'graphics and disconnect external displays, then try again. '
            'If the desktop is using NVIDIA graphics, log out and switch '
            'modes from a text console.',
            kind: AppFailureKind.graphicsBlocked,
            details: error.details,
          );
        case LegionBridgeErrorCode.graphicsPending:
          throw DgpuRepositoryException(
            'The setting for ${mode.label} was saved, but the switch did not '
            'finish. Save your work and restart the laptop before trying another '
            'mode. If the problem continues, restore Hybrid/Switchable graphics '
            'in BIOS.',
            kind: AppFailureKind.graphicsPending,
            details: error.details,
          );
        case _:
          throw DgpuRepositoryException(
            switch (error.code) {
              LegionBridgeErrorCode.timeout =>
                'Switching to ${mode.label} timed out. Use Refresh to check '
                    'the current mode, then close and reopen the app before trying again.',
              LegionBridgeErrorCode.busy =>
                'Another hardware change is running. Wait for it to finish, '
                    'then try switching to ${mode.label} again.',
              _ =>
                'Could not switch to ${mode.label}. Use Refresh to check '
                    'the current mode before trying again.',
            },
            kind: AppFailure.from(error).kind,
            details: error.details,
          );
      }
    }
  }

  Future<void> setGraphicsBootSupport(bool enabled) async {
    try {
      await bridgeService.runControlOperation(
        operation: (client) => client.setGraphicsBootSupport(enabled),
        method: 'graphics_mode.boot_support',
        args: [enabled ? 'enable' : 'disable'],
      );
    } on LegionBridgeException catch (error) {
      throw DgpuRepositoryException(
        enabled
            ? 'Could not set up iGPU-only at startup. Refresh to check the current setup.'
            : 'Could not remove iGPU-only startup support. Refresh to check the current setup.',
        kind: AppFailure.from(error).kind,
        details: error.details,
      );
    }
  }

  Future<void> killGpuProcesses(List<int> expectedPids) async {
    final currentPids =
        (await (queryComputeProcesses?.call() ?? _queryComputeProcesses()))
            .map((process) => process.pid)
            .toList()
          ..sort();
    final baseline = [...expectedPids]..sort();
    if (baseline.isEmpty || !_sameValues(currentPids, baseline)) {
      throw const DgpuRepositoryException(
        'The GPU process list changed. Refresh and confirm the current targets before trying again.',
      );
    }
    throw const DgpuRepositoryException(
      'Killing GPU processes is not supported by the control service.',
      kind: AppFailureKind.unavailable,
    );
  }

  Future<void> restartPciDevice(String expectedPciAddress) async {
    final currentAddress =
        await (findPciAddress?.call() ?? _findNvidiaGpuPciAddress());
    if (currentAddress != expectedPciAddress) {
      throw const DgpuRepositoryException(
        'The GPU PCI target changed. Refresh before trying again.',
      );
    }
    if ((await (queryComputeProcesses?.call() ?? _queryComputeProcesses()))
        .isNotEmpty) {
      throw const DgpuRepositoryException(
        'GPU compute processes are still active. Stop them before restarting the PCI device.',
      );
    }
    throw const DgpuRepositoryException(
      'Restarting PCI devices is not supported by the control service.',
      kind: AppFailureKind.unavailable,
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
        final classHex = (await classFile.readAsString()).trim().replaceFirst(
          '0x',
          '',
        );
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
  Future<List<GpuProcess>> _queryComputeProcesses() async {
    try {
      final result = await Process.run('nvidia-smi', [
        '--query-compute-apps=pid,process_name,used_gpu_memory',
        '--format=csv,noheader,nounits',
      ]).timeout(const Duration(seconds: 8));
      if (result.exitCode != 0) return [];
      return GpuProcess.parseNvidiaSmiOutput('${result.stdout}');
    } on Exception catch (_) {
      return [];
    }
  }

  Future<String?> _queryPciName(String pciAddress) async {
    try {
      final result = await Process.run('lspci', [
        '-s',
        pciAddress,
      ]).timeout(const Duration(seconds: 4));
      if (result.exitCode != 0) return null;
      final output = '${result.stdout}'.trim();
      if (output.isEmpty) return null;
      final separator = output.indexOf(': ');
      return separator == -1 ? output : output.substring(separator + 2);
    } on Exception catch (_) {
      return null;
    }
  }

  bool _sameValues(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }
}
