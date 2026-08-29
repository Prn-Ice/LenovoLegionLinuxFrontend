import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/services/legion_frontend_bridge_service.dart';
import 'package:legion_frontend/core/services/legion_sysfs_service.dart';
import 'package:legion_frontend/core/services/power_profile_service.dart';
import 'package:legion_frontend/features/power/models/power_limit.dart';
import 'package:legion_frontend/features/power/repository/power_repository.dart';
import 'package:mocktail/mocktail.dart';

class _MockSysfs extends Mock implements LegionSysfsService {}

class _MockBridge extends Mock implements LegionFrontendBridgeService {}

class _MockProfileService extends Mock implements PowerProfileService {}

void main() {
  late _MockSysfs sysfs;
  late _MockBridge bridge;
  late PowerRepository repository;
  final reading = PowerLimitReading(
    spec: PowerRepository.allPowerLimits.first,
    value: 60,
  );

  setUp(() {
    sysfs = _MockSysfs();
    bridge = _MockBridge();
    repository = PowerRepository(
      sysfsService: sysfs,
      powerProfileService: _MockProfileService(),
      bridgeService: bridge,
    );
  });

  test('rejects power-limit writes outside Custom mode', () async {
    when(() => sysfs.readPlatformProfile()).thenAnswer((_) async => 'balanced');

    await expectLater(
      repository.setPowerLimits([reading]),
      throwsA(
        isA<PowerRepositoryException>().having(
          (error) => error.message,
          'message',
          contains('Custom mode'),
        ),
      ),
    );
    verifyZeroInteractions(bridge);
  });

  test('rejects custom power-limit writes while on battery', () async {
    when(() => sysfs.readPlatformProfile()).thenAnswer((_) async => 'custom');
    when(() => sysfs.readOnPowerSupplyMode()).thenAnswer((_) async => false);

    await expectLater(
      repository.setPowerLimits([reading]),
      throwsA(
        isA<PowerRepositoryException>().having(
          (error) => error.message,
          'message',
          contains('Connect AC power'),
        ),
      ),
    );
  });

  test('writes validated staged limits in Custom mode on AC', () async {
    when(() => sysfs.readPlatformProfile()).thenAnswer((_) async => 'custom');
    when(() => sysfs.readOnPowerSupplyMode()).thenAnswer((_) async => true);
    when(
      () => sysfs.readLegionIntFile(reading.spec.sysfsAttribute),
    ).thenAnswer((_) async => 55);
    when(
      () => bridge.runPrivilegedCommand(
        method: 'feature.set',
        args: ['set-feature', reading.spec.featureName, '60'],
        timeout: const Duration(seconds: 5),
        detectUnavailableResponse: true,
      ),
    ).thenAnswer((_) async {});

    await repository.setPowerLimits([reading]);

    verify(
      () => bridge.runPrivilegedCommand(
        method: 'feature.set',
        args: ['set-feature', reading.spec.featureName, '60'],
        timeout: const Duration(seconds: 5),
        detectUnavailableResponse: true,
      ),
    ).called(1);
  });

  test('rolls back earlier limits when a later write fails', () async {
    final second = PowerLimitReading(
      spec: PowerRepository.allPowerLimits[1],
      value: 80,
    );
    when(() => sysfs.readPlatformProfile()).thenAnswer((_) async => 'custom');
    when(() => sysfs.readOnPowerSupplyMode()).thenAnswer((_) async => true);
    when(
      () => sysfs.readLegionIntFile(reading.spec.sysfsAttribute),
    ).thenAnswer((_) async => 55);
    when(
      () => sysfs.readLegionIntFile(second.spec.sysfsAttribute),
    ).thenAnswer((_) async => 75);
    when(
      () => bridge.runPrivilegedCommand(
        method: 'feature.set',
        args: ['set-feature', reading.spec.featureName, '60'],
        timeout: const Duration(seconds: 5),
        detectUnavailableResponse: true,
      ),
    ).thenAnswer((_) async {});
    when(
      () => bridge.runPrivilegedCommand(
        method: 'feature.set',
        args: ['set-feature', second.spec.featureName, '80'],
        timeout: const Duration(seconds: 5),
        detectUnavailableResponse: true,
      ),
    ).thenThrow(
      const LegionBridgeException(
        code: LegionBridgeErrorCode.commandFailed,
        method: 'feature.set',
        message: 'failed',
      ),
    );
    when(
      () => bridge.runPrivilegedCommand(
        method: 'feature.set',
        args: ['set-feature', reading.spec.featureName, '55'],
        timeout: const Duration(seconds: 5),
        detectUnavailableResponse: true,
      ),
    ).thenAnswer((_) async {});

    await expectLater(
      repository.setPowerLimits([reading, second]),
      throwsA(isA<PowerRepositoryException>()),
    );

    verify(
      () => bridge.runPrivilegedCommand(
        method: 'feature.set',
        args: ['set-feature', reading.spec.featureName, '55'],
        timeout: const Duration(seconds: 5),
        detectUnavailableResponse: true,
      ),
    ).called(1);
  });
}
