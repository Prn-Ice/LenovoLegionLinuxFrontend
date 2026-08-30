import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:legion_frontend/features/sensors/bloc/live_sensor_bloc.dart';
import 'package:legion_frontend/features/sensors/bloc/live_sensor_event.dart';
import 'package:legion_frontend/features/sensors/bloc/live_sensor_state.dart';
import 'package:legion_frontend/features/sensors/models/live_sensor_snapshot.dart';
import 'package:legion_frontend/features/sensors/repository/live_sensor_repository.dart';

class MockLiveSensorRepository extends Mock implements LiveSensorRepository {}

void main() {
  late MockLiveSensorRepository repository;

  setUp(() {
    repository = MockLiveSensorRepository();
  });

  group('LiveSensorBloc', () {
    final snapshot = LiveSensorSnapshot(
      cpuName: 'Ryzen 7',
      cpuTempC: 61.0,
      cpuUtilPercent: 12.0,
      cpuClockGhz: 3.1,
      cpuPackagePowerW: 24.5,
      fan1Rpm: 1800,
      fan2Rpm: 1500,
      gpuName: null,
      gpuTempC: null,
      gpuUtilPercent: null,
      gpuClockGhz: null,
      gpuVramUsedGb: null,
      gpuVramTotalGb: null,
      gpuFanPercent: null,
      gpuPowerDrawW: null,
      gpuIsDiscrete: false,
      motherboardTempC: null,
      batteryPercent: 78,
      batteryCharging: true,
      batteryPowerDrawW: -18.0,
      diskTempC: null,
    );

    test('initial state has initial snapshot', () {
      final bloc = LiveSensorBloc(
        repository: repository,
        pollInterval: const Duration(seconds: 60),
      );
      expect(bloc.state.snapshot, LiveSensorSnapshot.initial());
      bloc.close();
    });

    blocTest<LiveSensorBloc, LiveSensorState>(
      'emits loaded snapshot on LiveSensorStarted',
      build: () {
        when(() => repository.loadSnapshot()).thenAnswer((_) async => snapshot);
        return LiveSensorBloc(
          repository: repository,
          pollInterval: const Duration(seconds: 60),
        );
      },
      act: (bloc) => bloc.add(const LiveSensorStarted()),
      wait: const Duration(milliseconds: 100),
      expect: () => [LiveSensorState(snapshot: snapshot, isLoading: false)],
    );

    blocTest<LiveSensorBloc, LiveSensorState>(
      'emits error state when loadSnapshot throws',
      build: () {
        when(
          () => repository.loadSnapshot(),
        ).thenThrow(Exception('sysfs error'));
        return LiveSensorBloc(
          repository: repository,
          pollInterval: const Duration(seconds: 60),
        );
      },
      act: (bloc) => bloc.add(const LiveSensorStarted()),
      wait: const Duration(milliseconds: 100),
      expect: () => [
        isA<LiveSensorState>().having(
          (s) => s.errorMessage,
          'error',
          isNotNull,
        ),
      ],
    );
  });
}
