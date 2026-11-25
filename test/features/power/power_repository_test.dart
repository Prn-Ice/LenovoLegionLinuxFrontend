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

  test('retains supported zero and positive readings', () async {
    when(() => sysfs.readPlatformProfile()).thenAnswer((_) async => 'balanced');
    when(() => sysfs.readPlatformProfileChoices())
        .thenAnswer((_) async => ['balanced']);
    when(() => sysfs.readCpuOverclockMode()).thenAnswer((_) async => null);
    when(() => sysfs.readGpuOverclockMode()).thenAnswer((_) async => null);
    when(() => sysfs.readOnPowerSupplyMode()).thenAnswer((_) async => true);
    when(() => sysfs.readCpuPolicySnapshot()).thenAnswer((_) async => null);
    when(() => profileService.loadDaemonSnapshot())
        .thenAnswer((_) async => null);
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

    expect(snapshot.powerLimits, hasLength(12));
    expect(snapshot.powerLimits.first.spec.id, 'cpu_longterm');
    expect(snapshot.powerLimits.first.value, 35);
    expect(snapshot.powerLimits.first.reference, 54);
    expect(
      snapshot.powerLimits
          .where((reading) => !reading.spec.isWritable)
          .map((reading) => reading.spec.id),
      ['cpu_temperature', 'cpu_default', 'gpu_power_target_offset'],
    );
    expect(
      snapshot.powerLimits
          .firstWhere((reading) => reading.spec.id == 'gpu_power_target_offset')
          .reference,
      45,
    );
    expect(
      snapshot.powerLimits
          .where((reading) => reading.value == 0)
          .map((reading) => reading.spec.id),
      containsAll(<String>[
        'cpu_peak',
        'cpu_cross_loading',
        'cpu_apu_sppt',
        'gpu_ctgp',
        'gpu_ppab',
        'gpu_boost_clock',
        'gpu_temperature',
      ]),
    );
    expect(
      snapshot.powerLimits
          .firstWhere((reading) => reading.spec.id == 'cpu_shortterm')
          .value,
      201,
    );

    when(() => sysfs.readBiosVersion()).thenAnswer((_) async => 'M1CN49WW');
    final otherBiosSnapshot = await repository.loadSnapshot();
    expect(
      otherBiosSnapshot.powerLimits.every(
        (reading) => reading.reference == null,
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

  test(
    'keeps zero visible but preserves the app request lower bound',
    () async {
      final zeroReading = PowerLimitReading(
        spec: PowerRepository.allPowerLimits.firstWhere(
          (spec) => spec.min == 0,
        ),
        value: 0,
      );
      expect(zeroReading.spec.effectiveMin, 1);
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
    },
  );

  test('writes validated staged limits in Custom mode on AC', () async {
    when(() => sysfs.readPlatformProfile()).thenAnswer((_) async => 'custom');
    when(() => sysfs.readOnPowerSupplyMode()).thenAnswer((_) async => true);
    var reads = 0;
    when(() => sysfs.readLegionIntFile(reading.spec.sysfsAttribute))
        .thenAnswer((_) async => reads++ == 0 ? 55 : 60);
    when(
      () => bridge.runControlOperation(
        operation: any(named: 'operation'),
        method: 'feature.set',
        args: [reading.spec.feature!.wireValue, '60'],
        timeout: const Duration(seconds: 5),
      ),
    ).thenAnswer((_) async {});

    await repository.setPowerLimits([reading]);

    verify(
      () => bridge.runControlOperation(
        operation: any(named: 'operation'),
        method: 'feature.set',
        args: [reading.spec.feature!.wireValue, '60'],
        timeout: const Duration(seconds: 5),
      ),
    ).called(1);
  });

  test('reports a clamped readback instead of claiming success', () async {
    when(() => sysfs.readPlatformProfile()).thenAnswer((_) async => 'custom');
    when(() => sysfs.readOnPowerSupplyMode()).thenAnswer((_) async => true);
    var reads = 0;
    when(() => sysfs.readLegionIntFile(reading.spec.sysfsAttribute)).thenAnswer(
      (_) async => switch (reads++) {
        0 => 55,
        1 => 50,
        _ => 55,
      },
    );
    when(
      () => bridge.runControlOperation(
        operation: any(named: 'operation'),
        method: 'feature.set',
        args: [reading.spec.feature!.wireValue, '60'],
        timeout: const Duration(seconds: 5),
      ),
    ).thenAnswer((_) async {});
    when(
      () => bridge.runControlOperation(
        operation: any(named: 'operation'),
        method: 'feature.set',
        args: [reading.spec.feature!.wireValue, '55'],
        timeout: const Duration(seconds: 5),
      ),
    ).thenAnswer((_) async {});

    await expectLater(
      repository.setPowerLimits([reading]),
      throwsA(
        isA<PowerLimitReadbackException>()
            .having((error) => error.requested, 'requested', 60)
            .having((error) => error.actual, 'actual', 50)
            .having((error) => error.message, 'message', contains('clamped')),
      ),
    );
  });

  test('reports missing readback without claiming success', () async {
    when(() => sysfs.readPlatformProfile()).thenAnswer((_) async => 'custom');
    when(() => sysfs.readOnPowerSupplyMode()).thenAnswer((_) async => true);
    var reads = 0;
    when(() => sysfs.readLegionIntFile(reading.spec.sysfsAttribute)).thenAnswer(
      (_) async => switch (reads++) {
        0 => 55,
        1 => null,
        _ => 55,
      },
    );
    when(
      () => bridge.runControlOperation(
        operation: any(named: 'operation'),
        method: 'feature.set',
        args: [reading.spec.feature!.wireValue, '60'],
        timeout: const Duration(seconds: 5),
      ),
    ).thenAnswer((_) async {});
    when(
      () => bridge.runControlOperation(
        operation: any(named: 'operation'),
        method: 'feature.set',
        args: [reading.spec.feature!.wireValue, '55'],
        timeout: const Duration(seconds: 5),
      ),
    ).thenAnswer((_) async {});

    await expectLater(
      repository.setPowerLimits([reading]),
      throwsA(
        isA<PowerLimitReadbackException>()
            .having((error) => error.actual, 'actual', isNull)
            .having(
              (error) => error.message,
              'message',
              contains('actual value is unavailable'),
            ),
      ),
    );
  });

  test(
    'rolls back all changed limits after an accepted-but-clamped batch write',
    () async {
      final second = PowerLimitReading(
        spec: PowerRepository.allPowerLimits[1],
        value: 80,
      );
      when(() => sysfs.readPlatformProfile()).thenAnswer((_) async => 'custom');
      when(() => sysfs.readOnPowerSupplyMode()).thenAnswer((_) async => true);
      var firstReads = 0;
      var secondReads = 0;
      when(() => sysfs.readLegionIntFile(reading.spec.sysfsAttribute))
          .thenAnswer(
            (_) async => switch (firstReads++) {
              0 => 55,
              1 => 60,
              _ => 55,
            },
          );
      when(() => sysfs.readLegionIntFile(second.spec.sysfsAttribute))
          .thenAnswer(
            (_) async => switch (secondReads++) {
              0 => 75,
              1 => 70,
              _ => 75,
            },
          );
      for (final args in [
        [reading.spec.feature!.wireValue, '60'],
        [second.spec.feature!.wireValue, '80'],
        [second.spec.feature!.wireValue, '75'],
        [reading.spec.feature!.wireValue, '55'],
      ]) {
        when(
          () => bridge.runControlOperation(
            operation: any(named: 'operation'),
            method: 'feature.set',
            args: args,
            timeout: const Duration(seconds: 5),
          ),
        ).thenAnswer((_) async {});
      }

      await expectLater(
        repository.setPowerLimits([reading, second]),
        throwsA(
          isA<PowerLimitReadbackException>()
              .having((error) => error.limit, 'limit', second.spec)
              .having((error) => error.actual, 'actual', 70),
        ),
      );
      verify(
        () => bridge.runControlOperation(
          operation: any(named: 'operation'),
          method: 'feature.set',
          args: [second.spec.feature!.wireValue, '75'],
          timeout: const Duration(seconds: 5),
        ),
      ).called(1);
      verify(
        () => bridge.runControlOperation(
          operation: any(named: 'operation'),
          method: 'feature.set',
          args: [reading.spec.feature!.wireValue, '55'],
          timeout: const Duration(seconds: 5),
        ),
      ).called(1);
    },
  );

  for (final rollbackFails in [false, true]) {
    test(
      'preserves write failure after rollback (rollback fails: $rollbackFails)',
      () async {
        final second = PowerLimitReading(
          spec: PowerRepository.allPowerLimits[1],
          value: 80,
        );
        when(() => sysfs.readPlatformProfile())
            .thenAnswer((_) async => 'custom');
        when(() => sysfs.readOnPowerSupplyMode()).thenAnswer((_) async => true);
        var firstReads = 0;
        when(() => sysfs.readLegionIntFile(reading.spec.sysfsAttribute))
            .thenAnswer(
              (_) async => switch (firstReads++) {
                0 => 55,
                1 => 60,
                _ => 55,
              },
            );
        when(() => sysfs.readLegionIntFile(second.spec.sysfsAttribute))
            .thenAnswer((_) async => 75);
        when(
          () => bridge.runControlOperation(
            operation: any(named: 'operation'),
            method: 'feature.set',
            args: [reading.spec.feature!.wireValue, '60'],
            timeout: const Duration(seconds: 5),
          ),
        ).thenAnswer((_) async {});
        when(
          () => bridge.runControlOperation(
            operation: any(named: 'operation'),
            method: 'feature.set',
            args: [second.spec.feature!.wireValue, '80'],
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
            args: [reading.spec.feature!.wireValue, '55'],
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
            args: [reading.spec.feature!.wireValue, '55'],
            timeout: const Duration(seconds: 5),
          ),
        ).called(1);
      },
    );
  }
}
