import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:legion_frontend/features/battery/bloc/battery_bloc.dart';
import 'package:legion_frontend/features/battery/bloc/battery_event.dart';
import 'package:legion_frontend/features/battery/bloc/battery_state.dart';
import 'package:legion_frontend/features/battery/models/battery_snapshot.dart';
import 'package:legion_frontend/features/battery/repository/battery_repository.dart';

class MockBatteryRepository extends Mock implements BatteryRepository {}

void main() {
  late MockBatteryRepository repo;
  setUp(() => repo = MockBatteryRepository());

  const snapshot = BatterySnapshot(
    batteryConservationEnabled: false,
    batteryConservationSupported: true,
    rapidChargingEnabled: false,
    rapidChargingSupported: true,
    batteryPercent: 80,
    batteryCharging: false,
    batteryPowerDrawW: 15.0,
    cycleCounts: null,
    fullCapacityWh: null,
    designCapacityWh: null,
    currentCapacityWh: null,
    batteryTempC: null,
  );

  blocTest<BatteryBloc, BatteryState>(
    'emits loading then loaded state on BatteryStarted',
    build: () {
      when(() => repo.loadSnapshot()).thenAnswer((_) async => snapshot);
      return BatteryBloc(
        repository: repo,
        pollInterval: const Duration(seconds: 60),
      );
    },
    act: (bloc) => bloc.add(const BatteryStarted()),
    wait: const Duration(milliseconds: 100),
    expect: () => [
      isA<BatteryState>().having((s) => s.isLoading, 'isLoading', true),
      isA<BatteryState>().having(
        (s) => s.batteryConservationEnabled,
        'conservation',
        false,
      ),
    ],
  );

  blocTest<BatteryBloc, BatteryState>(
    'emits loading then error on repository failure',
    build: () {
      when(() => repo.loadSnapshot()).thenThrow(Exception('sysfs error'));
      return BatteryBloc(
        repository: repo,
        pollInterval: const Duration(seconds: 60),
      );
    },
    act: (bloc) => bloc.add(const BatteryStarted()),
    wait: const Duration(milliseconds: 100),
    expect: () => [
      isA<BatteryState>().having((s) => s.isLoading, 'isLoading', true),
      isA<BatteryState>().having((s) => s.errorMessage, 'error', isNotNull),
    ],
  );

  group('BatteryBloc BatteryTicked', () {
    blocTest<BatteryBloc, BatteryState>(
      'BatteryTicked reloads silently when not applying',
      build: () {
        // snapshot has non-null fields so the emitted state differs from initial
        when(() => repo.loadSnapshot()).thenAnswer((_) async => snapshot);
        return BatteryBloc(
          repository: repo,
          pollInterval: const Duration(seconds: 60),
        );
      },
      seed: () => BatteryState.initial(),
      act: (bloc) => bloc.add(const BatteryTicked()),
      expect: () => [
        isA<BatteryState>().having((s) => s.isLoading, 'isLoading', false),
      ],
    );

    blocTest<BatteryBloc, BatteryState>(
      'BatteryTicked is skipped when isApplying',
      build: () {
        when(() => repo.loadSnapshot()).thenAnswer((_) async => snapshot);
        return BatteryBloc(
          repository: repo,
          pollInterval: const Duration(seconds: 60),
        );
      },
      seed: () => BatteryState.initial().copyWith(isApplying: true),
      act: (bloc) => bloc.add(const BatteryTicked()),
      expect: () => isEmpty,
    );
  });
}
