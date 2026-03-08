import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/models/bridge_command_record.dart';

void main() {
  final ts = DateTime(2026, 3, 8, 12, 0, 0);

  group('BridgeCommandRecord constructor', () {
    test('stores all fields', () {
      final r = BridgeCommandRecord(
        timestamp: ts,
        method: 'power.set_mode',
        args: const ['set-feature', 'PlatformProfile', 'quiet'],
        isPrivileged: true,
        succeeded: true,
        durationMs: 234,
      );
      expect(r.timestamp, ts);
      expect(r.method, 'power.set_mode');
      expect(r.args, ['set-feature', 'PlatformProfile', 'quiet']);
      expect(r.isPrivileged, isTrue);
      expect(r.succeeded, isTrue);
      expect(r.durationMs, 234);
    });
  });

  group('BridgeCommandRecord.redactedArgs', () {
    test('keeps args without slashes unchanged', () {
      final r = BridgeCommandRecord(
        timestamp: ts,
        method: 'm',
        args: const ['set-feature', 'PlatformProfile', 'quiet'],
        isPrivileged: true,
        succeeded: true,
        durationMs: 0,
      );
      expect(r.redactedArgs, ['set-feature', 'PlatformProfile', 'quiet']);
    });

    test('redacts args that contain a slash', () {
      final r = BridgeCommandRecord(
        timestamp: ts,
        method: 'm',
        args: const ['boot-logo', 'enable', '/home/user/boot.bmp'],
        isPrivileged: true,
        succeeded: true,
        durationMs: 0,
      );
      expect(r.redactedArgs, ['boot-logo', 'enable', '<path>']);
    });

    test('unprivileged commands: args left unchanged even with slashes', () {
      final r = BridgeCommandRecord(
        timestamp: ts,
        method: 'diagnostics.cli_health',
        args: const ['--help'],
        isPrivileged: false,
        succeeded: true,
        durationMs: 0,
      );
      expect(r.redactedArgs, ['--help']);
    });
  });

  group('BridgeCommandRecord Equatable', () {
    test('equal when all fields match', () {
      final a = BridgeCommandRecord(
        timestamp: ts,
        method: 'm',
        args: const ['a'],
        isPrivileged: false,
        succeeded: true,
        durationMs: 1,
      );
      final b = BridgeCommandRecord(
        timestamp: ts,
        method: 'm',
        args: const ['a'],
        isPrivileged: false,
        succeeded: true,
        durationMs: 1,
      );
      expect(a, equals(b));
    });

    test('not equal when succeeded differs', () {
      final a = BridgeCommandRecord(
        timestamp: ts,
        method: 'm',
        args: const [],
        isPrivileged: false,
        succeeded: true,
        durationMs: 0,
      );
      final b = a.copyWith(succeeded: false);
      expect(a, isNot(equals(b)));
    });
  });
}
