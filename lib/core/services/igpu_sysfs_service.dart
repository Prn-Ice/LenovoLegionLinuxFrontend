import 'dart:io';
import 'dart:typed_data';

import '../models/gpu_reading.dart';

/// Reads AMD APU usage and temperature from that device's sysfs directory.
class IgpuSysfsService {
  const IgpuSysfsService({this.drmPath = '/sys/class/drm'});

  final String drmPath;

  Future<GpuReading?> readSnapshot() async {
    try {
      final cards = await Directory(drmPath).list().toList();
      final readings = <GpuReading>[];
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
        final usage = double.tryParse(
          await _read('$device/gpu_busy_percent') ?? '',
        );
        readings.add(
          GpuReading(
            usagePercent:
                usage != null && usage.isFinite && usage >= 0 && usage <= 100
                ? usage
                : null,
            tempC: await _readTemperature(device),
          ),
        );
      }
      // A single iGPU label must not silently choose between multiple devices.
      return readings.length == 1 ? readings.single : null;
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
