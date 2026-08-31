import 'dart:io';

import '../../../core/data/privileged_repository.dart';
import '../../../core/services/legion_frontend_bridge_service.dart';
import '../models/dgpu_process.dart';
import '../models/dgpu_snapshot.dart';
import '../models/graphics_mode.dart';

class DgpuRepositoryException implements Exception {
  const DgpuRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}

class DgpuRepository extends PrivilegedRepository {
  const DgpuRepository({required super.bridgeService});

  @override
  Exception wrapBridgeError(String message) => DgpuRepositoryException(message);

  static const _knownRuntimeStatusPath =
      '/sys/bus/pci/devices/0000:01:00.0/power/runtime_status';

  Future<DgpuSnapshot> loadSnapshot() => _loadSnapshot();

  Future<DgpuSnapshot> loadSnapshotAfterGraphicsWrite() =>
      _loadSnapshot(requireGraphicsModeStatus: true);

  Future<DgpuSnapshot> _loadSnapshot({
    bool requireGraphicsModeStatus = false,
  }) async {
    final results = await Future.wait([
      _findNvidiaGpuPciAddress(),
      loadGraphicsModeStatus(required: requireGraphicsModeStatus),
    ]);
    final pciAddress = results[0] as String?;
    final graphicsModeStatus = results[1] as GraphicsModeStatus?;

    final bool? isActive;
    if (pciAddress != null) {
      final runtimePath =
          '/sys/bus/pci/devices/$pciAddress/power/runtime_status';
      isActive = await _readRuntimeStatus(runtimePath);
    } else {
      isActive = null;
    }
    final processes = await _queryComputeProcesses();
    final name = pciAddress == null ? null : await _queryPciName(pciAddress);
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
      if (!result.ok) {
        if (required) {
          throw DgpuRepositoryException(
            'Authoritative graphics status could not be reloaded after the '
            'mode request. Backend output: ${result.stderr}',
          );
        }
        return null;
      }
      return GraphicsModeStatus.parse(result.stdout);
    } on DgpuRepositoryException {
      rethrow;
    } catch (error) {
      if (required) {
        throw DgpuRepositoryException(
          'Authoritative graphics status could not be reloaded after the mode '
          'request: $error',
        );
      }
      return null;
    }
  }

  Future<void> setGraphicsMode(GraphicsMode mode) async {
    if (mode == GraphicsMode.hybridAuto) {
      throw const DgpuRepositoryException(
        'Hybrid Auto is not available as a desktop action because it can '
        'detach the dGPU after AC is unplugged without another client preflight.',
      );
    }

    try {
      await bridgeService.runPrivilegedCommand(
        method: 'graphics_mode.set',
        args: ['graphics-mode', 'set', mode.wireValue],
        timeout: const Duration(seconds: 45),
        detectUnavailableResponse: false,
      );
    } on LegionBridgeException catch (error) {
      final technicalDetails = error.details.isEmpty
          ? ''
          : '\n\nTechnical details:\n${error.details}';
      switch (error.code) {
        case LegionBridgeErrorCode.graphicsBlocked:
          throw DgpuRepositoryException(
            'Could not switch to ${mode.label}. The firmware policy was not '
            'changed because the privileged preflight found active dGPU/DRM '
            'clients or could not complete client inspection. Close '
            'GPU-accelerated applications and external-display sessions, then '
            'retry from a text console.$technicalDetails',
          );
        case LegionBridgeErrorCode.graphicsPending:
          throw DgpuRepositoryException(
            '${mode.label} was selected, but the effective GPU topology did '
            'not settle. The firmware policy may have changed, so do not '
            'assume the requested mode is active. Check authoritative status '
            'and restore Hybrid from a text console or reboot before '
            'continuing.$technicalDetails',
          );
        case _:
          throw DgpuRepositoryException(
            'Could not request ${mode.label}. No authoritative confirmation '
            'was received that the graphics policy changed.$technicalDetails',
          );
      }
    }
  }

  Future<void> killGpuProcesses(List<int> expectedPids) async {
    final currentPids =
        (await _queryComputeProcesses()).map((process) => process.pid).toList()
          ..sort();
    final baseline = [...expectedPids]..sort();
    if (baseline.isEmpty || !_sameValues(currentPids, baseline)) {
      throw const DgpuRepositoryException(
        'The GPU process list changed. Refresh and confirm the current targets before trying again.',
      );
    }
    await runPrivilegedCommand(
      ['dgpu', 'kill-processes'],
      method: 'dgpu.kill_processes',
      failurePrefix: 'Failed to kill GPU processes',
      timeout: const Duration(seconds: 15),
      detectUnavailableResponse: false,
    );
  }

  Future<void> restartPciDevice(String expectedPciAddress) async {
    final currentAddress = await _findNvidiaGpuPciAddress();
    if (currentAddress != expectedPciAddress) {
      throw const DgpuRepositoryException(
        'The GPU PCI target changed. Refresh before trying again.',
      );
    }
    if ((await _queryComputeProcesses()).isNotEmpty) {
      throw const DgpuRepositoryException(
        'GPU compute processes are still active. Stop them before restarting the PCI device.',
      );
    }
    await runPrivilegedCommand(
      ['dgpu', 'restart-pci'],
      method: 'dgpu.restart_pci',
      failurePrefix: 'Failed to restart GPU PCI device',
      timeout: const Duration(seconds: 20),
      detectUnavailableResponse: false,
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
  Future<List<DgpuProcess>> _queryComputeProcesses() async {
    try {
      final result = await Process.run('nvidia-smi', [
        '--query-compute-apps=pid,process_name,used_gpu_memory',
        '--format=csv,noheader,nounits',
      ]).timeout(const Duration(seconds: 8));
      if (result.exitCode != 0) return [];
      return DgpuProcess.parseNvidiaSmiOutput('${result.stdout}');
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
