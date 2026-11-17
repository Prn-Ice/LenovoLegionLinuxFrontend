import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/models/bridge_command_record.dart';
import 'package:legion_frontend/features/about/models/about_diagnostic_item.dart';
import 'package:legion_frontend/features/about/models/about_snapshot.dart';
import 'package:legion_frontend/features/lighting/models/spectrum_hid_discovery.dart';

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
  group('AboutSnapshot nullable and empty fixture values', () {
    test('kernelVersion preserves an explicit null', () {
      expect(minimal().kernelVersion, isNull);
    });

    test('hardwareModel preserves an explicit null', () {
      expect(minimal().hardwareModel, isNull);
    });

    test('moduleVersion preserves an explicit null', () {
      expect(minimal().moduleVersion, isNull);
    });

    test('cliVersion preserves an explicit null', () {
      expect(minimal().cliVersion, isNull);
    });

    test('commandHistory preserves an empty list', () {
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

  test('schema 5 omits Python and installed-service status while retaining runtime diagnostics', () {
    final json = minimal().toJson();

    expect(json['schema_version'], 5);
    expect(json, isNot(contains('python_available')));
    expect(json['cli_path_exists'], isTrue);
    expect(json['cli_healthy'], isTrue);
    expect(json['cli_health_summary'], 'Healthy');
    expect(json, isNot(contains('control_service_active')));
    expect(json['systemctl_available'], isTrue);
  });

  test('HID report redacts selected and configured paths', () {
    final json = minimal()
        .copyWithForTest(
          spectrumHid: const SpectrumHidDiscovery(
            outcome: SpectrumHidDiscoveryOutcome.supported,
            vendorId: 0x048d,
            productId: 0xc987,
            selectedHidrawPath: '/private/test/device/hidraw0',
          ),
        )
        .toJson();
    final text = json.toString();
    expect(text, contains('<custom-dev-root>/hidraw'));
    expect(text, isNot(contains('/private/test')));
    expect(text, isNot(contains('HID_UNIQ')));
  });
}

extension on AboutSnapshot {
  AboutSnapshot copyWithForTest({SpectrumHidDiscovery? spectrumHid}) =>
      AboutSnapshot(
        updatedAt: updatedAt,
        cliPath: cliPath,
        cliPathExists: cliPathExists,
        systemctlAvailable: systemctlAvailable,
        cliHealthy: cliHealthy,
        cliHealthSummary: cliHealthSummary,
        diagnostics: diagnostics,
        kernelVersion: kernelVersion,
        hardwareModel: hardwareModel,
        moduleVersion: moduleVersion,
        cliVersion: cliVersion,
        commandHistory: commandHistory,
        biosVersion: biosVersion,
        spectrumHid: spectrumHid ?? this.spectrumHid,
      );
}
