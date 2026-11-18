import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/services/nvidia_smi_service.dart';

void main() {
  test('parses P-state with the existing telemetry fields', () {
    final snapshot = NvidiaSmiService.parseCsvOutput(
      'NVIDIA GeForce RTX 4060, 42, 1800, 64, 35, 2048, 8192, 38.5, P2',
    );

    expect(snapshot?.name, 'NVIDIA GeForce RTX 4060');
    expect(snapshot?.usagePercent, 42);
    expect(snapshot?.clockGhz, 1.8);
    expect(snapshot?.vramUsedGb, 2);
    expect(snapshot?.performanceState, 'P2');
  });

  test('keeps telemetry when P-state is unsupported', () {
    final snapshot = NvidiaSmiService.parseCsvOutput(
      'Test GPU, 12, 900, 51, [Not Supported], 512, 4096, 14, N/A',
    );

    expect(snapshot?.usagePercent, 12);
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

  test('keeps unavailable and invalid usage distinct from zero', () {
    for (final value in [
      'N/A',
      '[Not Supported]',
      '-1',
      '101',
      'NaN',
      'Infinity',
    ]) {
      final reading = NvidiaSmiService.parseCsvOutput(
        'GPU, $value, 100, 40, 0, 0, 1024, 5, P8',
      );
      expect(reading?.usagePercent, isNull);
    }
    expect(
      NvidiaSmiService.parseCsvOutput('GPU, 0, 100, 40, 0, 0, 1024, 5, P8')
          ?.usagePercent,
      0,
    );
  });

  test(
    'queries the identified GPU only while active and skips suspended devices',
    () async {
      final root = await Directory.systemTemp.createTemp('nvidia-usage-');
      addTearDown(() => root.delete(recursive: true));
      final device = Directory('${root.path}/0000:02:00.0');
      await Directory('${device.path}/power').create(recursive: true);
      await File('${device.path}/vendor').writeAsString('0x10de');
      await File('${device.path}/class').writeAsString('0x030200');
      final runtime = File('${device.path}/power/runtime_status');
      var calls = 0;
      final service = NvidiaSmiService(
        pciDevicesPath: root.path,
        runProcess: (executable, arguments) async {
          calls++;
          expect(executable, 'nvidia-smi');
          expect(arguments, contains('--id=0000:02:00.0'));
          return ProcessResult(1, 0, 'GPU, 42, 100, 40, 0, 0, 1024, 5, P8', '');
        },
      );
      for (final state in ['suspended', 'suspending', 'resuming']) {
        await runtime.writeAsString(state);
        expect(await service.readSnapshot(), isNull);
      }
      expect(calls, 0);
      await runtime.writeAsString('active');
      expect((await service.readSnapshot())?.usagePercent, 42);
      expect(calls, 1);
      await runtime.delete();
      expect(await service.readSnapshot(), isNull);
      expect(calls, 1);
    },
  );
}
