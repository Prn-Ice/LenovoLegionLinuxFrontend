import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/models/gpu_process.dart';
import 'package:legion_frontend/core/models/gpu_process_scan.dart';
import 'package:legion_frontend/core/models/gpu_reading.dart';
import 'package:legion_frontend/core/services/igpu_sysfs_service.dart';
import 'package:legion_frontend/core/services/legion_sysfs_service.dart';
import 'package:legion_frontend/core/services/nvidia_smi_service.dart';
import 'package:legion_frontend/core/services/package_power_telemetry_service.dart';
import 'package:legion_frontend/features/sensors/repository/live_sensor_repository.dart';
import 'package:mocktail/mocktail.dart';

class _MockSysfs extends Mock implements LegionSysfsService {}

class _MockNvidia extends Mock implements NvidiaSmiService {}

class _MockIgpu extends Mock implements IgpuSysfsService {}

class _MockPackagePower extends Mock implements PackagePowerTelemetryClient {}

void main() {
  late _MockSysfs sysfs;
  late _MockNvidia nvidia;
  late _MockIgpu igpu;
  late _MockPackagePower packagePower;
  late LiveSensorRepository repository;

  setUp(() {
    sysfs = _MockSysfs();
    nvidia = _MockNvidia();
    igpu = _MockIgpu();
    packagePower = _MockPackagePower();
    repository = LiveSensorRepository(
      sysfsService: sysfs,
      nvidiaSmiService: nvidia,
      igpuSysfsService: igpu,
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
    when(sysfs.readFan3Rpm).thenAnswer((_) async => null);
    when(sysfs.readFan3MaxRpm).thenAnswer((_) async => null);
    when(sysfs.readMotherboardTempC).thenAnswer((_) async => null);
    when(sysfs.readBatteryPowerDrawW).thenAnswer((_) async => null);
    when(sysfs.readDiskTempC).thenAnswer((_) async => null);
    when(sysfs.readBatteryPercent).thenAnswer((_) async => null);
    when(sysfs.readBatteryStatus).thenAnswer((_) async => null);
    when(igpu.readSnapshot)
        .thenAnswer((_) async => const GpuReading(usagePercent: 12, tempC: 48));
    when(igpu.readProcesses).thenAnswer((_) async => null);
    when(packagePower.readPackagePowerWatts).thenAnswer((_) async => 24.5);
  });

  test('propagates package power into the dGPU snapshot', () async {
    when(nvidia.readSnapshot).thenAnswer(
      (_) async => const GpuReading(
        name: 'Test GPU',
        usagePercent: 65,
        tempC: 62,
        performanceState: 'P2',
      ),
    );

    final snapshot = await repository.loadSnapshot();

    expect(snapshot.cpuPackagePowerW, 24.5);
    expect(snapshot.fan3Rpm, isNull);
    expect(snapshot.dgpu?.performanceState, 'P2');
    expect(snapshot.dgpu?.usagePercent, 65);
    expect(snapshot.dgpu?.tempC, 62);
    expect(snapshot.igpu?.usagePercent, 12);
    expect(snapshot.igpu?.tempC, 48);
    verify(packagePower.readPackagePowerWatts).called(1);
  });

  test(
    'publishes CPU temperature while the GPU process scan is pending',
    () async {
      final pendingProcesses = Completer<GpuProcessScan?>();
      final temperature = Completer<double>();
      when(nvidia.readSnapshot).thenAnswer((_) async => null);
      when(igpu.readProcesses).thenAnswer((_) => pendingProcesses.future);
      final readings = repository.loadSnapshot(
        onReading: (snapshot) {
          final cpuTemp = snapshot.cpuTempC;
          if (cpuTemp != null && !temperature.isCompleted) {
            temperature.complete(cpuTemp);
          }
        },
      );

      expect(await temperature.future, 62);
      pendingProcesses.complete(GpuProcessScan.noClients);
      expect((await readings).igpuProcesses, GpuProcessScan.noClients);
    },
  );

  test(
    'propagates optional third fan telemetry without inventing a value',
    () async {
      when(nvidia.readSnapshot).thenAnswer((_) async => null);
      when(sysfs.readFan3Rpm).thenAnswer((_) async => 2300);
      when(sysfs.readFan3MaxRpm).thenAnswer((_) async => 6500);

      final snapshot = await repository.loadSnapshot();

      expect(snapshot.fan3Rpm, 2300);
      expect(snapshot.fan3MaxRpm, 6500);
    },
  );

  test('propagates unavailable package power into the iGPU snapshot', () async {
    when(nvidia.readSnapshot).thenAnswer((_) async => null);
    when(packagePower.readPackagePowerWatts).thenAnswer((_) async => null);

    final snapshot = await repository.loadSnapshot();

    expect(snapshot.cpuPackagePowerW, isNull);
    expect(snapshot.dgpu, isNull);
    expect(snapshot.igpu?.usagePercent, 12);
    verifyNever(sysfs.readGpuTempC);
    verify(packagePower.readPackagePowerWatts).called(1);
  });

  test('propagates integrated GPU process use from the same scan', () async {
    when(nvidia.readSnapshot).thenAnswer((_) async => null);
    when(igpu.readProcesses).thenAnswer(
      (_) async => const GpuProcessScan(
        processes: [GpuProcess(pid: 77, name: 'browser', usedMemoryMib: 96)],
        reporting: GpuProcessReporting.reported,
      ),
    );

    final snapshot = await repository.loadSnapshot();

    expect(snapshot.igpuProcesses?.processes.single.pid, 77);
    expect(snapshot.igpuProcesses?.reporting, GpuProcessReporting.reported);
    verify(igpu.readProcesses).called(1);
  });

  test('missing iGPU does not hide or replace discrete GPU readings', () async {
    when(igpu.readSnapshot).thenAnswer((_) async => null);
    when(nvidia.readSnapshot)
        .thenAnswer((_) async => const GpuReading(usagePercent: 0));
    final snapshot = await repository.loadSnapshot();
    expect(snapshot.igpu, isNull);
    expect(snapshot.dgpu?.usagePercent, 0);
  });

  test('an iGPU-only usage change produces a new snapshot', () async {
    when(nvidia.readSnapshot).thenAnswer((_) async => null);
    final before = await repository.loadSnapshot();
    when(igpu.readSnapshot)
        .thenAnswer((_) async => const GpuReading(usagePercent: 25, tempC: 48));
    final after = await repository.loadSnapshot();
    expect(after, isNot(before));
    expect(after.igpu?.usagePercent, 25);
  });
}
