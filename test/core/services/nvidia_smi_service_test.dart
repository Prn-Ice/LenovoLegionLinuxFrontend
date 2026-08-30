import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/services/nvidia_smi_service.dart';

void main() {
  test('parses P-state with the existing telemetry fields', () {
    final snapshot = NvidiaSmiService.parseCsvOutput(
      'NVIDIA GeForce RTX 4060, 42, 1800, 64, 35, 2048, 8192, 38.5, P2',
    );

    expect(snapshot?.name, 'NVIDIA GeForce RTX 4060');
    expect(snapshot?.utilPercent, 42);
    expect(snapshot?.clkGhz, 1.8);
    expect(snapshot?.vramUsedGb, 2);
    expect(snapshot?.performanceState, 'P2');
  });

  test('keeps telemetry when P-state is unsupported', () {
    final snapshot = NvidiaSmiService.parseCsvOutput(
      'Test GPU, 12, 900, 51, [Not Supported], 512, 4096, 14, N/A',
    );

    expect(snapshot?.utilPercent, 12);
    expect(snapshot?.fanPercent, isNull);
    expect(snapshot?.performanceState, isNull);
  });

  test('uses the first GPU and rejects malformed rows', () {
    final snapshot = NvidiaSmiService.parseCsvOutput(
      'First GPU, 1, 100, 40, 0, 0, 1024, 5, P8\n'
      'Second GPU, 99, 2000, 80, 90, 900, 1024, 100, P0',
    );

    expect(snapshot?.name, 'First GPU');
    expect(NvidiaSmiService.parseCsvOutput('missing,fields'), isNull);
  });
}
