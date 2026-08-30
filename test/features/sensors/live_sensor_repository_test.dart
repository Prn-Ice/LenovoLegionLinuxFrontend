import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/services/legion_sysfs_service.dart';
import 'package:legion_frontend/core/services/nvidia_smi_service.dart';
import 'package:legion_frontend/core/services/package_power_telemetry_service.dart';
import 'package:legion_frontend/features/sensors/repository/live_sensor_repository.dart';
import 'package:mocktail/mocktail.dart';

class _MockSysfs extends Mock implements LegionSysfsService {}

class _MockNvidia extends Mock implements NvidiaSmiService {}

class _MockPackagePower extends Mock implements PackagePowerTelemetryClient {}

void main() {
  late _MockSysfs sysfs;
  late _MockNvidia nvidia;
  late _MockPackagePower packagePower;
  late LiveSensorRepository repository;

  setUp(() {
    sysfs = _MockSysfs();
    nvidia = _MockNvidia();
    packagePower = _MockPackagePower();
    repository = LiveSensorRepository(
      sysfsService: sysfs,
      nvidiaSmiService: nvidia,
      packagePowerTelemetryClient: packagePower,
    );

    when(sysfs.readCpuName).thenAnswer((_) async => 'Test CPU');
    when(sysfs.readCpuTempC).thenAnswer((_) async => 62);
    when(sysfs.readCpuUtilisationPercent).thenAnswer((_) async => 18);
    when(sysfs.readAverageCpuClockGhz).thenAnswer((_) async => 3.1);
    when(sysfs.readFan1Rpm).thenAnswer((_) async => null);
    when(sysfs.readFan1MaxRpm).thenAnswer((_) async => null);
    when(sysfs.readFan2Rpm).thenAnswer((_) async => null);
    when(sysfs.readFan2MaxRpm).thenAnswer((_) async => null);
    when(sysfs.readMotherboardTempC).thenAnswer((_) async => null);
    when(sysfs.readBatteryPowerDrawW).thenAnswer((_) async => null);
    when(sysfs.readDiskTempC).thenAnswer((_) async => null);
    when(
      () => sysfs.readIntFile('/sys/class/power_supply/BAT0/capacity'),
    ).thenAnswer((_) async => null);
    when(packagePower.readPackagePowerWatts).thenAnswer((_) async => 24.5);
  });

  test('propagates package power into the dGPU snapshot', () async {
    when(nvidia.readSnapshot).thenAnswer(
      (_) async => const NvidiaSmiSnapshot(
        name: 'Test GPU',
        utilPercent: null,
        clkGhz: null,
        tempC: null,
        fanPercent: null,
        vramUsedGb: null,
        vramTotalGb: null,
        powerDrawW: null,
        performanceState: 'P2',
      ),
    );

    final snapshot = await repository.loadSnapshot();

    expect(snapshot.cpuPackagePowerW, 24.5);
    expect(snapshot.gpuIsDiscrete, isTrue);
    expect(snapshot.gpuPerformanceState, 'P2');
    verify(packagePower.readPackagePowerWatts).called(1);
  });

  test('propagates unavailable package power into the iGPU snapshot', () async {
    when(nvidia.readSnapshot).thenAnswer((_) async => null);
    when(sysfs.readGpuTempC).thenAnswer((_) async => 48);
    when(packagePower.readPackagePowerWatts).thenAnswer((_) async => null);

    final snapshot = await repository.loadSnapshot();

    expect(snapshot.cpuPackagePowerW, isNull);
    expect(snapshot.gpuIsDiscrete, isFalse);
    verify(packagePower.readPackagePowerWatts).called(1);
  });
}
