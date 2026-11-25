import 'dart:io';

import '../models/gpu_reading.dart';

class NvidiaSmiService {
  NvidiaSmiService({
    this._pciDevicesPath = '/sys/bus/pci/devices',
    Future<ProcessResult> Function(String, List<String>)? runProcess,
  }) : _runProcess = runProcess ?? Process.run;

  final String _pciDevicesPath;
  final Future<ProcessResult> Function(String, List<String>) _runProcess;

  /// Skip inactive devices before invoking nvidia-smi, which can wake a GPU.
  Future<GpuReading?> readSnapshot() async {
    try {
      final address = await _activeDevice();
      if (address == null) return null;
      final result = await _runProcess('nvidia-smi', [
        '--id=$address',
        '--query-gpu=name,utilization.gpu,clocks.gr,temperature.gpu,'
            'fan.speed,memory.used,memory.total,power.draw,pstate',
        '--format=csv,noheader,nounits',
      ]).timeout(const Duration(seconds: 4));
      if (result.exitCode != 0) return null;
      return parseCsvOutput('${result.stdout}');
    } catch (_) {
      return null;
    }
  }

  Future<String?> _activeDevice() async {
    final addresses = <String>[];
    await for (final device in Directory(_pciDevicesPath).list()) {
      try {
        final vendor = (await File(
          '${device.path}/vendor',
        ).readAsString()).trim();
        if (vendor != '0x10de') continue;
        final deviceClass = int.tryParse(
          (await File('${device.path}/class').readAsString()).trim(),
        );
        if (deviceClass == null || deviceClass >> 16 != 0x03) continue;
        // Count all NVIDIA display devices: ambiguity must not change identity
        // when one of several devices suspends.
        addresses.add(device.path);
      } on FileSystemException {
        continue;
      }
    }
    if (addresses.length != 1) return null;
    final path = addresses.single;
    final runtime = (await File(
      '$path/power/runtime_status',
    ).readAsString()).trim();
    if (runtime != 'active' && runtime != 'unsupported') return null;
    return path.split('/').last;
  }

  static GpuReading? parseCsvOutput(String output) {
    final lines = output
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty);
    if (lines.isEmpty) return null;
    final parts = lines.first.split(',').map((part) => part.trim()).toList();
    if (parts.length != 9) return null;

    double? parseDouble(String value) {
      final number = double.tryParse(value.trim());
      return number != null && number.isFinite && number >= 0 ? number : null;
    }

    int? parseInt(String value) =>
        int.tryParse(value.replaceAll('[Not Supported]', '').trim());
    String? parseString(String value) {
      final cleaned = value.trim();
      if (cleaned.isEmpty || cleaned == '[Not Supported]' || cleaned == 'N/A') {
        return null;
      }
      return cleaned;
    }

    final clockMhz = parseDouble(parts[2]);
    final usage = parseDouble(parts[1]);
    final vramUsedMib = parseDouble(parts[5]);
    final vramTotalMib = parseDouble(parts[6]);
    return GpuReading(
      name: parseString(parts[0]),
      usagePercent: usage != null && usage <= 100 ? usage : null,
      clockGhz: clockMhz == null ? null : clockMhz / 1000.0,
      tempC: parseDouble(parts[3]),
      fanPercent: parseInt(parts[4]),
      vramUsedGb: vramUsedMib == null ? null : vramUsedMib / 1024.0,
      vramTotalGb: vramTotalMib == null ? null : vramTotalMib / 1024.0,
      powerDrawW: parseDouble(parts[7]),
      performanceState: parseString(parts[8]),
    );
  }
}
