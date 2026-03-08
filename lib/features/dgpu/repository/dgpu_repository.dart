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
      final runtimePath =
          '/sys/bus/pci/devices/$pciAddress/power/runtime_status';
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
        final classHex =
            (await classFile.readAsString()).trim().replaceFirst('0x', '');
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
