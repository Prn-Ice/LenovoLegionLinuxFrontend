import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/models/power_profiles_daemon_snapshot.dart';
import 'package:legion_frontend/core/services/legion_sysfs_service.dart';
import 'package:legion_frontend/core/services/power_profile_service.dart';
import 'package:mocktail/mocktail.dart';

class _MockSysfs extends Mock implements LegionSysfsService {}

class _MockDaemon extends Mock implements PowerProfilesDaemonClient {}

void main() {
  late _MockSysfs sysfs;
  late _MockDaemon daemon;
  late PowerProfileService service;

  setUp(() {
    sysfs = _MockSysfs();
    daemon = _MockDaemon();
    service = PowerProfileService(sysfsService: sysfs, daemonClient: daemon);
  });

  test('parses the modern daemon profile and driver properties', () {
    final parsed = DBusPowerProfilesDaemonClient.parseProperties({
      'ActiveProfile': const DBusString('balanced'),
      'Profiles': DBusArray(DBusSignature('a{sv}'), [
        DBusDict.stringVariant({
          'Profile': const DBusString('balanced'),
          'CpuDriver': const DBusString('amd_pstate'),
          'PlatformDriver': const DBusString('platform_profile'),
        }),
      ]),
      'BatteryAware': const DBusBoolean(true),
      'Version': const DBusString('0.30'),
      'PerformanceDegraded': const DBusString(''),
    });

    expect(parsed?.activeProfile, 'balanced');
    expect(parsed?.cpuDrivers, ['amd_pstate']);
    expect(parsed?.platformDrivers, ['platform_profile']);
    expect(parsed?.batteryAware, isTrue);
  });

  test('maps PPD profiles while retaining vendor-only hardware modes', () {
    final values = service.availableProfiles(
      hardwareProfiles: const [
        'low-power',
        'balanced',
        'performance',
        'max-power',
        'custom',
      ],
      daemon: _snapshot(),
    );

    expect(values, [
      'low-power',
      'balanced',
      'performance',
      'max-power',
      'custom',
    ]);
  });

  test('does not synthesize standard modes missing from firmware choices', () {
    final values = service.availableProfiles(
      hardwareProfiles: const ['max-power', 'custom'],
      daemon: _snapshot(),
    );

    expect(values, ['max-power', 'custom']);
  });

  test('standard profile is delegated to PPD without a direct write', () async {
    when(
      () => sysfs.readPlatformProfileChoices(),
    ).thenAnswer((_) async => ['low-power', 'balanced', 'performance']);
    when(() => daemon.loadSnapshot()).thenAnswer((_) async => _snapshot());
    when(() => daemon.setActiveProfile('balanced')).thenAnswer((_) async {});
    when(() => sysfs.readPlatformProfile()).thenAnswer((_) async => 'balanced');
    final directWrites = <String>[];

    await service.setProfile(
      'balanced',
      writePlatformProfile: (profile) async => directWrites.add(profile),
    );

    verify(() => daemon.setActiveProfile('balanced')).called(1);
    expect(directWrites, isEmpty);
  });

  test('repairs a PPD no-op when leaving a vendor profile', () async {
    when(() => sysfs.readPlatformProfileChoices()).thenAnswer(
      (_) async => ['low-power', 'balanced', 'performance', 'custom'],
    );
    when(() => daemon.loadSnapshot()).thenAnswer((_) async => _snapshot());
    when(() => daemon.setActiveProfile('performance')).thenAnswer((_) async {});
    when(() => sysfs.readPlatformProfile()).thenAnswer((_) async => 'custom');
    final directWrites = <String>[];

    await service.setProfile(
      'performance',
      writePlatformProfile: (profile) async => directWrites.add(profile),
    );

    expect(directWrites, ['performance']);
  });

  test('pairs vendor profiles with the PPD performance CPU policy', () async {
    when(() => sysfs.readPlatformProfileChoices()).thenAnswer(
      (_) async => ['low-power', 'balanced', 'performance', 'custom'],
    );
    when(() => sysfs.readOnPowerSupplyMode()).thenAnswer((_) async => true);
    when(() => daemon.loadSnapshot()).thenAnswer((_) async => _snapshot());
    when(() => daemon.setActiveProfile('performance')).thenAnswer((_) async {});
    final directWrites = <String>[];

    await service.setProfile(
      'custom',
      writePlatformProfile: (profile) async => directWrites.add(profile),
    );

    verify(() => daemon.setActiveProfile('performance')).called(1);
    expect(directWrites, ['custom']);
  });

  test(
    'rejects vendor profiles on battery before changing PPD state',
    () async {
      when(() => sysfs.readPlatformProfileChoices()).thenAnswer(
        (_) async => ['low-power', 'balanced', 'performance', 'custom'],
      );
      when(() => sysfs.readOnPowerSupplyMode()).thenAnswer((_) async => false);
      final directWrites = <String>[];

      await expectLater(
        service.setProfile(
          'custom',
          writePlatformProfile: (profile) async => directWrites.add(profile),
        ),
        throwsA(
          isA<PowerProfileServiceException>().having(
            (error) => error.message,
            'message',
            'Connect AC power before switching to Custom mode.',
          ),
        ),
      );

      verifyNever(() => daemon.loadSnapshot());
      verifyNever(() => daemon.setActiveProfile(any()));
      expect(directWrites, isEmpty);
    },
  );

  test('rejects an unsupported mode before changing PPD state', () async {
    when(
      () => sysfs.readPlatformProfileChoices(),
    ).thenAnswer((_) async => ['custom']);
    when(() => daemon.loadSnapshot()).thenAnswer((_) async => _snapshot());

    await expectLater(
      service.setProfile('performance', writePlatformProfile: (_) async {}),
      throwsA(isA<PowerProfileServiceException>()),
    );

    verifyNever(() => daemon.setActiveProfile(any()));
  });
}

PowerProfilesDaemonSnapshot _snapshot() {
  return const PowerProfilesDaemonSnapshot(
    activeProfile: 'balanced',
    profiles: [
      PowerProfileDescriptor(
        profile: 'power-saver',
        cpuDriver: 'amd_pstate',
        platformDriver: 'platform_profile',
      ),
      PowerProfileDescriptor(
        profile: 'balanced',
        cpuDriver: 'amd_pstate',
        platformDriver: 'platform_profile',
      ),
      PowerProfileDescriptor(
        profile: 'performance',
        cpuDriver: 'amd_pstate',
        platformDriver: 'platform_profile',
      ),
    ],
    batteryAware: true,
    version: '0.30',
    performanceDegraded: '',
  );
}
