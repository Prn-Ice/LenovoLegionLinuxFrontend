import 'dart:io';

class NvidiaSmiSnapshot {
  const NvidiaSmiSnapshot({
    required this.name,
    required this.utilPercent,
    required this.clkGhz,
    required this.tempC,
    required this.fanRpm,
    required this.vramUsedGb,
    required this.vramTotalGb,
    required this.powerDrawW,
  });

  final String? name;
  final double? utilPercent;
  final double? clkGhz;
  final double? tempC;
  final int? fanRpm;
  final double? vramUsedGb;
  final double? vramTotalGb;
  final double? powerDrawW;
}

class NvidiaSmiService {
  /// Returns null if nvidia-smi is not available or dGPU is not active.
  Future<NvidiaSmiSnapshot?> readSnapshot() async {
    try {
      final result = await Process.run('nvidia-smi', [
        '--query-gpu=name,utilization.gpu,clocks.gr,temperature.gpu,'
            'fan.speed,memory.used,memory.total,power.draw',
        '--format=csv,noheader,nounits',
      ]);
      if (result.exitCode != 0) return null;
      final line = (result.stdout as String).trim();
      if (line.isEmpty) return null;
      final parts = line.split(',').map((s) => s.trim()).toList();
      if (parts.length < 8) return null;

      double? parseDouble(String s) =>
          double.tryParse(s.replaceAll('[Not Supported]', '').trim());
      int? parseInt(String s) =>
          int.tryParse(s.replaceAll('[Not Supported]', '').trim());

      final clkMhz = parseDouble(parts[2]);

      return NvidiaSmiSnapshot(
        name: parts[0].isEmpty ? null : parts[0],
        utilPercent: parseDouble(parts[1]),
        clkGhz: clkMhz != null ? clkMhz / 1000.0 : null,
        tempC: parseDouble(parts[3]),
        fanRpm: parseInt(parts[4]),
        vramUsedGb: parseDouble(parts[5]) != null
            ? parseDouble(parts[5])! / 1024.0
            : null,
        vramTotalGb: parseDouble(parts[6]) != null
            ? parseDouble(parts[6])! / 1024.0
            : null,
        powerDrawW: parseDouble(parts[7]),
      );
    } catch (_) {
      return null;
    }
  }
}
