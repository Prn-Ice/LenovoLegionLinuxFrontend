import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/models/gpu_process.dart';

void main() {
  group('GpuProcess.parseNvidiaSmiOutput', () {
    test('parses single process line', () {
      final result = GpuProcess.parseNvidiaSmiOutput(
        '1234, /usr/bin/Xorg, 4\n',
      );
      expect(result, hasLength(1));
      expect(result.first.pid, equals(1234));
      expect(result.first.name, equals('Xorg'));
      expect(result.first.usedMemoryMib, equals(4));
    });

    test('parses multiple lines', () {
      const output = '1234, /usr/bin/Xorg, 4\n5678, blender, 2048\n';
      final result = GpuProcess.parseNvidiaSmiOutput(output);
      expect(result, hasLength(2));
      expect(result[1].pid, equals(5678));
      expect(result[1].usedMemoryMib, equals(2048));
    });

    test('returns empty list for empty output', () {
      expect(GpuProcess.parseNvidiaSmiOutput(''), isEmpty);
      expect(GpuProcess.parseNvidiaSmiOutput('\n'), isEmpty);
    });

    test('skips malformed lines', () {
      const output = 'not_a_number, Xorg, 4\n9999, blender, 1024\n';
      final result = GpuProcess.parseNvidiaSmiOutput(output);
      expect(result, hasLength(1));
      expect(result.first.pid, equals(9999));
    });

    test('uses base name when full path is given', () {
      final result = GpuProcess.parseNvidiaSmiOutput(
        '42, /usr/lib/xorg/Xorg, 10\n',
      );
      expect(result.first.name, equals('Xorg'));
    });

    test('preserves name when no slash', () {
      final result = GpuProcess.parseNvidiaSmiOutput('42, blender, 10\n');
      expect(result.first.name, equals('blender'));
    });

    test('defaults to 0 when memory field is non-integer', () {
      final result = GpuProcess.parseNvidiaSmiOutput('1234, blender, N/A\n');
      expect(result, hasLength(1));
      expect(result.first.usedMemoryMib, equals(0));
    });

    test('equality based on all fields', () {
      const a = GpuProcess(pid: 1, name: 'Xorg', usedMemoryMib: 4);
      const b = GpuProcess(pid: 1, name: 'Xorg', usedMemoryMib: 4);
      const c = GpuProcess(pid: 2, name: 'Xorg', usedMemoryMib: 4);
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });
}
