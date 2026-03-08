import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/models/bridge_command_record.dart';
import 'package:legion_frontend/features/about/models/about_diagnostic_item.dart';
import 'package:legion_frontend/features/about/models/about_snapshot.dart';

final ts = DateTime(2026, 3, 8, 12, 0);
const item = AboutDiagnosticItem(
  id: 'a',
  label: 'A',
  status: AboutDiagnosticStatus.ok,
  value: 'v',
);

AboutSnapshot minimal() => AboutSnapshot(
  updatedAt: ts,
  cliPath: '/usr/bin/legion_cli',
  cliPathExists: true,
  pythonAvailable: true,
  pkexecAvailable: true,
  systemctlAvailable: true,
  cliHealthy: true,
  cliHealthSummary: 'Healthy',
  diagnostics: const [],
  kernelVersion: null,
  hardwareModel: null,
  moduleVersion: null,
  cliVersion: null,
  commandHistory: const [],
);

void main() {
  group('AboutSnapshot new fields default to null / empty', () {
    test('kernelVersion is null when not provided', () {
      expect(minimal().kernelVersion, isNull);
    });

    test('hardwareModel is null when not provided', () {
      expect(minimal().hardwareModel, isNull);
    });

    test('moduleVersion is null when not provided', () {
      expect(minimal().moduleVersion, isNull);
    });

    test('cliVersion is null when not provided', () {
      expect(minimal().cliVersion, isNull);
    });

    test('commandHistory is empty by default', () {
      expect(minimal().commandHistory, isEmpty);
    });
  });

  group('AboutSnapshot Equatable', () {
    test('equal when all fields match', () {
      expect(minimal(), equals(minimal()));
    });

    test('not equal when kernelVersion differs', () {
      final a = minimal();
      final b = AboutSnapshot(
        updatedAt: ts,
        cliPath: '/usr/bin/legion_cli',
        cliPathExists: true,
        pythonAvailable: true,
        pkexecAvailable: true,
        systemctlAvailable: true,
        cliHealthy: true,
        cliHealthSummary: 'Healthy',
        diagnostics: const [],
        kernelVersion: '6.8.0',
        hardwareModel: null,
        moduleVersion: null,
        cliVersion: null,
        commandHistory: const [],
      );
      expect(a, isNot(equals(b)));
    });

    test('not equal when commandHistory differs', () {
      final record = BridgeCommandRecord(
        timestamp: ts,
        method: 'm',
        args: const [],
        isPrivileged: false,
        succeeded: true,
        durationMs: 0,
      );
      final a = minimal();
      final b = AboutSnapshot(
        updatedAt: ts,
        cliPath: '/usr/bin/legion_cli',
        cliPathExists: true,
        pythonAvailable: true,
        pkexecAvailable: true,
        systemctlAvailable: true,
        cliHealthy: true,
        cliHealthSummary: 'Healthy',
        diagnostics: const [],
        kernelVersion: null,
        hardwareModel: null,
        moduleVersion: null,
        cliVersion: null,
        commandHistory: [record],
      );
      expect(a, isNot(equals(b)));
    });
  });
}
