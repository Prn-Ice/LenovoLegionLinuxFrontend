import 'dart:io';

class XrandrServiceException implements Exception {
  const XrandrServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

class XrandrDisplayInfo {
  const XrandrDisplayInfo({
    required this.outputName,
    required this.availableRates,
    required this.currentRate,
  });

  final String outputName;
  final List<double> availableRates;
  final double currentRate;
}

class XrandrService {
  Future<XrandrDisplayInfo?> queryBuiltInDisplay() async {
    try {
      final result = await Process.run('xrandr', ['--query']);
      if (result.exitCode != 0) {
        return null;
      }
      return parseOutput(result.stdout as String);
    } catch (_) {
      return null;
    }
  }

  Future<void> setRefreshRate(String outputName, double rate) async {
    final rateStr = rate.toStringAsFixed(2);
    final result = await Process.run('xrandr', [
      '--output',
      outputName,
      '--rate',
      rateStr,
    ]);
    if (result.exitCode != 0) {
      throw XrandrServiceException('xrandr failed: ${result.stderr}'.trim());
    }
  }

  static XrandrDisplayInfo? parseOutput(String output) {
    final lines = output.split('\n');
    final edpPattern = RegExp(r'^(eDP[-\w]+)\s+connected');
    final modeLinePattern = RegExp(r'^\s+(\d+x\d+)\s+(.+)$');
    final ratePattern = RegExp(r'([\d.]+)([*+]*)');

    String? outputName;
    var inEdpBlock = false;

    for (final line in lines) {
      if (!inEdpBlock) {
        final match = edpPattern.firstMatch(line);
        if (match != null) {
          outputName = match.group(1);
          inEdpBlock = true;
        }
        continue;
      }

      final modeMatch = modeLinePattern.firstMatch(line);
      if (modeMatch == null) {
        break;
      }

      if (!line.contains('*')) {
        continue;
      }

      final ratePart = modeMatch.group(2)!;
      final rates = <double>[];
      double? currentRate;

      for (final match in ratePattern.allMatches(ratePart)) {
        final rate = double.tryParse(match.group(1)!);
        if (rate == null) {
          continue;
        }
        rates.add(rate);
        if (match.group(2)!.contains('*')) {
          currentRate = rate;
        }
      }

      if (currentRate != null && outputName != null && rates.isNotEmpty) {
        return XrandrDisplayInfo(
          outputName: outputName,
          availableRates: rates,
          currentRate: currentRate,
        );
      }

      break;
    }

    return null;
  }
}
