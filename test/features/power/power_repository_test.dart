import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/services/legion_control_client.dart';
import 'package:legion_frontend/core/models/app_failure.dart';
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
  setUpAll(() {
    registerFallbackValue((LegionControlClient client) async {});
  });
  late _MockSysfs sysfs;
  late _MockBridge bridge;
  late _MockProfileService profileService;
  late PowerRepository repository;
  final reading = PowerLimitReading(
    spec: PowerRepository.allPowerLimits.first,
    value: 60,
  );

  setUp(() {
    sysfs = _MockSysfs();
    bridge = _MockBridge();
    profileService = _MockProfileService();
    repository = PowerRepository(
      sysfsService: sysfs,
      powerProfileService: profileService,
      bridgeService: bridge,
    );
    when(() => sysfs.readDeviceProductName()).thenAnswer((_) async => null);
    when(() => sysfs.readBiosVersion()).thenAnswer((_) async => null);
  });

  test('omits non-positive limits while retaining positive readings', () async {
    when(() => sysfs.readPlatformProfile()).thenAnswer((_) async => 'balanced');
    when(
      () => sysfs.readPlatformProfileChoices(),
    ).thenAnswer((_) async => ['balanced']);
    when(() => sysfs.readCpuOverclockMode()).thenAnswer((_) async => null);
    when(() => sysfs.readGpuOverclockMode()).thenAnswer((_) async => null);
    when(() => sysfs.readOnPowerSupplyMode()).thenAnswer((_) async => true);
    when(() => sysfs.readCpuPolicySnapshot()).thenAnswer((_) async => null);
    when(
      () => profileService.loadDaemonSnapshot(),
    ).thenAnswer((_) async => null);
    when(
      () => profileService.availableProfiles(
        hardwareProfiles: ['balanced'],
        daemon: null,
      ),
    ).thenReturn(['balanced']);
    when(() => sysfs.readDeviceProductName()).thenAnswer((_) async => '82Y4');
    when(() => sysfs.readBiosVersion()).thenAnswer((_) async => 'M1CN48WW');
    for (final spec in PowerRepository.allPowerLimits) {
      when(() => sysfs.readLegionIntFile(spec.sysfsAttribute)).thenAnswer(
        (_) async => switch (spec.id) {
          'cpu_longterm' => 35,
          'cpu_shortterm' => 201,
          'cpu_temperature' => 100,
          'cpu_default' => 45,
          'gpu_power_target_offset' => 45,
          _ => 0,
        },
      );
    }

    final snapshot = await repository.loadSnapshot();

    expect(snapshot.powerLimits, hasLength(4));
    expect(snapshot.powerLimits.first.spec.id, 'cpu_longterm');
    expect(snapshot.powerLimits.first.value, 35);
    expect(snapshot.powerLimits.first.hardwareDefault, 54);
    expect(
      snapshot.powerLimits
          .where((reading) => !reading.spec.isWritable)
          .map((reading) => reading.spec.id),
      ['cpu_temperature', 'cpu_default', 'gpu_power_target_offset'],
    );
    expect(snapshot.powerLimits.last.hardwareDefault, 45);

    when(() => sysfs.readBiosVersion()).thenAnswer((_) async => 'M1CN49WW');
    final otherBiosSnapshot = await repository.loadSnapshot();
    expect(
      otherBiosSnapshot.powerLimits.every(
        (reading) => reading.hardwareDefault == null,
      ),
      isTrue,
    );
  });

  for (final id in [
    'cpu_temperature',
    'cpu_default',
    'gpu_power_target_offset',
  ]) {
    test('rejects single and batch writes to read-only $id', () async {
      final readOnly = PowerRepository.allPowerLimits.firstWhere(
        (spec) => spec.id == id,
      );

      await expectLater(
        repository.setPowerLimit(readOnly, 100),
        throwsA(
          isA<PowerRepositoryException>().having(
            (error) => error.message,
            'message',
            contains('read-only'),
          ),
        ),
      );
      verifyZeroInteractions(bridge);
      await expectLater(
        repository.setPowerLimits([
          reading,
          PowerLimitReading(spec: readOnly, value: 45),
        ]),
        throwsA(isA<PowerRepositoryException>()),
      );
      verifyZeroInteractions(bridge);
      verifyZeroInteractions(sysfs);
    });
  }

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

  test('rejects non-positive power-limit writes', () async {
    final zeroReading = PowerLimitReading(
      spec: PowerRepository.allPowerLimits.firstWhere((spec) => spec.min == 0),
      value: 0,
    );

    await expectLater(
      repository.setPowerLimit(zeroReading.spec, zeroReading.value),
      throwsA(
        isA<PowerRepositoryException>().having(
          (error) => error.message,
          'message',
          contains('between 1 and'),
        ),
      ),
    );
    await expectLater(
      repository.setPowerLimits([zeroReading]),
      throwsA(isA<PowerRepositoryException>()),
    );
    verifyZeroInteractions(bridge);
  });

  test('writes validated staged limits in Custom mode on AC', () async {
    when(() => sysfs.readPlatformProfile()).thenAnswer((_) async => 'custom');
    when(() => sysfs.readOnPowerSupplyMode()).thenAnswer((_) async => true);
    when(
      () => sysfs.readLegionIntFile(reading.spec.sysfsAttribute),
    ).thenAnswer((_) async => 55);
    when(
      () => bridge.runControlOperation(
        operation: any(named: 'operation'),
        method: 'feature.set',
        args: [reading.spec.featureName!, '60'],
        timeout: const Duration(seconds: 5),
      ),
    ).thenAnswer((_) async {});

    await repository.setPowerLimits([reading]);

    verify(
      () => bridge.runControlOperation(
        operation: any(named: 'operation'),
        method: 'feature.set',
        args: [reading.spec.featureName!, '60'],
        timeout: const Duration(seconds: 5),
      ),
    ).called(1);
  });

  for (final rollbackFails in [false, true]) {
    test(
      'preserves write failure after rollback (rollback fails: $rollbackFails)',
      () async {
        final second = PowerLimitReading(
          spec: PowerRepository.allPowerLimits[1],
          value: 80,
        );
        when(
          () => sysfs.readPlatformProfile(),
        ).thenAnswer((_) async => 'custom');
        when(() => sysfs.readOnPowerSupplyMode()).thenAnswer((_) async => true);
        when(
          () => sysfs.readLegionIntFile(reading.spec.sysfsAttribute),
        ).thenAnswer((_) async => 55);
        when(
          () => sysfs.readLegionIntFile(second.spec.sysfsAttribute),
        ).thenAnswer((_) async => 75);
        when(
          () => bridge.runControlOperation(
            operation: any(named: 'operation'),
            method: 'feature.set',
            args: [reading.spec.featureName!, '60'],
            timeout: const Duration(seconds: 5),
          ),
        ).thenAnswer((_) async {});
        when(
          () => bridge.runControlOperation(
            operation: any(named: 'operation'),
            method: 'feature.set',
            args: [second.spec.featureName!, '80'],
            timeout: const Duration(seconds: 5),
          ),
        ).thenThrow(
          const LegionBridgeException(
            code: LegionBridgeErrorCode.commandFailed,
            method: 'feature.set',
            message: 'failed',
            stderr: 'original diagnostic',
          ),
        );
        when(
          () => bridge.runControlOperation(
            operation: any(named: 'operation'),
            method: 'feature.set',
            args: [reading.spec.featureName!, '55'],
            timeout: const Duration(seconds: 5),
          ),
        ).thenAnswer((_) async {
          if (rollbackFails) {
            throw const LegionBridgeException(
              code: LegionBridgeErrorCode.busy,
              method: 'feature.set',
              message: 'restore failed',
            );
          }
        });

        await expectLater(
          repository.setPowerLimits([reading, second]),
          throwsA(
            isA<PowerRepositoryException>()
                .having(
                  (failure) => failure.kind,
                  'kind',
                  AppFailureKind.commandFailed,
                )
                .having(
                  (failure) => failure.details,
                  'details',
                  'original diagnostic',
                )
                .having(
                  (failure) =>
                      failure.message.contains('could not be restored'),
                  'rollback consequence',
                  rollbackFails,
                ),
          ),
        );

        verify(
          () => bridge.runControlOperation(
            operation: any(named: 'operation'),
            method: 'feature.set',
            args: [reading.spec.featureName!, '55'],
            timeout: const Duration(seconds: 5),
          ),
        ).called(1);
      },
    );
  }
}
