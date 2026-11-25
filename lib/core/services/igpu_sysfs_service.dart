import 'dart:io';
import 'dart:typed_data';

import '../models/gpu_process_scan.dart';
import '../models/gpu_reading.dart';
import 'drm_process_service.dart';

/// Reads AMD APU usage, temperature, and process use from sysfs and procfs.
class IgpuSysfsService {
  IgpuSysfsService({
    this.drmPath = '/sys/class/drm',
    DrmProcessService? processService,
  }) : processService = processService ?? DrmProcessService();

  final String drmPath;
  final DrmProcessService processService;

  Future<GpuReading?> readSnapshot() async {
    final device = await _findApuDevice();
    if (device == null) return null;

    final usage = double.tryParse(
      await _read('$device/gpu_busy_percent') ?? '',
    );
    final productName = await _read('$device/product_name');
    final name = productName != null && productName.isNotEmpty
        ? productName
        : 'AMD Integrated Graphics';
    return GpuReading(
      name: name,
      usagePercent:
          usage != null && usage.isFinite && usage >= 0 && usage <= 100
          ? usage
          : null,
      tempC: await _readTemperature(device),
    );
  }

  /// Returns the processes the kernel attributes to the identified APU.
  ///
  /// Returns null when no single APU was identified. The scan distinguishes
  /// kernels that do not report a GPU for DRM clients.
  Future<GpuProcessScan?> readProcesses() async {
    final device = await _findApuDevice();
    if (device == null) return null;
    final pciAddress = await _readPciAddress(device);
    if (pciAddress == null) return GpuProcessScan.notReported;
    return processService.readProcesses(pciAddress);
  }

  Future<String?> _findApuDevice() async {
    try {
      final cards = await Directory(drmPath).list().toList();
      final devices = <String>[];
      for (final card in cards) {
        if (!RegExp(r'^card\d+$').hasMatch(card.path.split('/').last)) continue;
        final device = '${card.path}/device';
        if (await _read('$device/vendor') != '0x1002') continue;
        final uevent = await _read('$device/uevent');
        if (uevent == null || !uevent.split('\n').contains('DRIVER=amdgpu')) {
          continue;
        }
        final runtime = await _read('$device/power/runtime_status');
        if (runtime != 'active' && runtime != 'unsupported') continue;
        if (!await _hasApuMetrics(device)) continue;
        devices.add(device);
      }
      // A single iGPU label must not silently choose between multiple devices.
      return devices.length == 1 ? devices.single : null;
    } on FileSystemException {
      return null;
    }
  }

  Future<String?> _readPciAddress(String device) async {
    final uevent = await _read('$device/uevent');
    for (final line in uevent?.split('\n') ?? const <String>[]) {
      if (!line.startsWith('PCI_SLOT_NAME=')) continue;
      final slot = line.substring('PCI_SLOT_NAME='.length).trim();
      if (slot.isNotEmpty) return slot;
    }

    try {
      final resolved = await Directory(device).resolveSymbolicLinks();
      final name = resolved.split('/').last;
      return RegExp(r'^[0-9a-fA-F]{4}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\.[0-7]$')
              .hasMatch(name)
          ? name
          : null;
    } on FileSystemException {
      return null;
    }
  }

  Future<bool> _hasApuMetrics(String device) async {
    try {
      final bytes = await File('$device/gpu_metrics').readAsBytes();
      if (bytes.length < 4) return false;
      final size = ByteData.sublistView(bytes).getUint16(0, Endian.little);
      if (size < 4 || size > bytes.length) return false;
      // The kernel's gpu_metrics_v2_* and v3_* layouts describe APUs.
      // Other layouts do not establish that this GPU is integrated.
      return bytes[2] == 2 || bytes[2] == 3;
    } on FileSystemException {
      return false;
    }
  }

  Future<double?> _readTemperature(String device) async {
    try {
      await for (final hwmon in Directory('$device/hwmon').list()) {
        if (await _read('${hwmon.path}/name') != 'amdgpu') continue;
        final raw = int.tryParse(
          await _read('${hwmon.path}/temp1_input') ?? '',
        );
        return raw == null ? null : raw / 1000;
      }
    } on FileSystemException {
      return null;
    }
    return null;
  }

  Future<String?> _read(String path) async {
    try {
      return (await File(path).readAsString()).trim();
    } on FileSystemException {
      return null;
    }
  }
}
