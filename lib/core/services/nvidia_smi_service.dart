import 'dart:io';

class NvidiaSmiSnapshot {
  const NvidiaSmiSnapshot({
    required this.name,
    required this.utilPercent,
    required this.clkGhz,
    required this.tempC,
    required this.fanPercent,
    required this.vramUsedGb,
    required this.vramTotalGb,
    required this.powerDrawW,
    this.performanceState,
  });

  final String? name;
  final double? utilPercent;
  final double? clkGhz;
  final double? tempC;
  final int? fanPercent;
  final double? vramUsedGb;
  final double? vramTotalGb;
  final double? powerDrawW;
  final String? performanceState;
}

class NvidiaSmiService {
  /// Returns null if nvidia-smi is not available or dGPU is not active.
  Future<NvidiaSmiSnapshot?> readSnapshot() async {
    try {
      final result = await Process.run('nvidia-smi', [
        '--query-gpu=name,utilization.gpu,clocks.gr,temperature.gpu,'
            'fan.speed,memory.used,memory.total,power.draw,pstate',
        '--format=csv,noheader,nounits',
      ]);
      if (result.exitCode != 0) return null;
      return parseCsvOutput('${result.stdout}');
    } catch (_) {
      return null;
    }
  }

  static NvidiaSmiSnapshot? parseCsvOutput(String output) {
    final lines = output
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty);
    if (lines.isEmpty) return null;
    final parts = lines.first.split(',').map((part) => part.trim()).toList();
    if (parts.length != 9) return null;

    double? parseDouble(String value) =>
        double.tryParse(value.replaceAll('[Not Supported]', '').trim());
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
    final vramUsedMib = parseDouble(parts[5]);
    final vramTotalMib = parseDouble(parts[6]);
    return NvidiaSmiSnapshot(
      name: parseString(parts[0]),
      utilPercent: parseDouble(parts[1]),
      clkGhz: clockMhz == null ? null : clockMhz / 1000.0,
      tempC: parseDouble(parts[3]),
      fanPercent: parseInt(parts[4]),
      vramUsedGb: vramUsedMib == null ? null : vramUsedMib / 1024.0,
      vramTotalGb: vramTotalMib == null ? null : vramTotalMib / 1024.0,
      powerDrawW: parseDouble(parts[7]),
      performanceState: parseString(parts[8]),
    );
  }
}
