import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:legion_frontend/features/battery/bloc/battery_bloc.dart';
import 'package:legion_frontend/features/battery/bloc/battery_event.dart';
import 'package:legion_frontend/features/battery/bloc/battery_state.dart';
import 'package:legion_frontend/features/battery/models/battery_snapshot.dart';
import 'package:legion_frontend/features/battery/repository/battery_repository.dart';
import 'package:legion_frontend/core/services/legion_frontend_bridge_service.dart';
import 'package:legion_frontend/core/services/legion_sysfs_service.dart';

class MockBatteryRepository extends Mock implements BatteryRepository {}

class MockBridgeService extends Mock implements LegionFrontendBridgeService {}

void main() {
  late MockBatteryRepository repo;
  setUp(() => repo = MockBatteryRepository());

  test(
    'empty sysfs completes the first read without inventing battery data',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'battery-unavailable-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final bridge = MockBridgeService();
      final bloc = BatteryBloc(
        repository: BatteryRepository(
          sysfsService: LegionSysfsService(sysRoot: directory.path),
          bridgeService: bridge,
        ),
      );
      addTearDown(bloc.close);
      final completed = bloc.stream.firstWhere((state) => !state.isLoading);
      bloc.add(const BatteryStarted());
      final state = await completed;
      expect(state.hasLoaded, isTrue);
      expect(state.batteryPercent, isNull);
      expect(state.batteryStatus, isNull);
      expect(state.batteryConservationSupported, isFalse);
      expect(state.errorMessage, isNull);
      verifyZeroInteractions(bridge);
    },
  );

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

  group('charging-mode readback', () {
    Future<BatteryBloc> start(BatterySnapshot initial) async {
      when(() => repo.loadSnapshot()).thenAnswer((_) async => initial);
      final bloc = BatteryBloc(
        repository: repo,
        pollInterval: const Duration(days: 1),
      );
      addTearDown(bloc.close);
      final loaded = bloc.stream.firstWhere((state) => state.hasLoaded);
      bloc.add(const BatteryStarted());
      await loaded;
      return bloc;
    }

    Future<BatteryState> apply(BatteryBloc bloc, BatteryEvent event) async {
      final completed = bloc.stream.firstWhere(
        (state) =>
            !state.isApplying &&
            (state.noticeMessage != null || state.errorMessage != null),
      );
      bloc.add(event);
      return completed;
    }

    test(
      'enabling conservation reads back rapid charging turning off',
      () async {
        final bloc = await start(
          _chargingSnapshot(conservation: false, rapid: true),
        );
        when(() => repo.setBatteryConservation(true)).thenAnswer((_) async {});
        when(() => repo.loadSnapshot()).thenAnswer(
          (_) async => _chargingSnapshot(conservation: true, rapid: false),
        );

        final state = await apply(
          bloc,
          const BatteryConservationSetRequested(true),
        );

        expect(state.batteryConservationEnabled, isTrue);
        expect(state.rapidChargingEnabled, isFalse);
        expect(state.errorMessage, isNull);
        verifyNever(() => repo.setRapidCharging(false));
      },
    );

    test(
      'enabling rapid charging reads back conservation turning off',
      () async {
        final bloc = await start(
          _chargingSnapshot(conservation: true, rapid: false),
        );
        when(() => repo.setRapidCharging(true)).thenAnswer((_) async {});
        when(() => repo.loadSnapshot()).thenAnswer(
          (_) async => _chargingSnapshot(conservation: false, rapid: true),
        );

        final state = await apply(bloc, const RapidChargingSetRequested(true));

        expect(state.batteryConservationEnabled, isFalse);
        expect(state.rapidChargingEnabled, isTrue);
        expect(state.errorMessage, isNull);
        verifyNever(() => repo.setBatteryConservation(false));
      },
    );

    test('disabling conservation preserves reported rapid charging', () async {
      final bloc = await start(
        _chargingSnapshot(conservation: true, rapid: true),
      );
      when(() => repo.setBatteryConservation(false)).thenAnswer((_) async {});
      when(() => repo.loadSnapshot()).thenAnswer(
        (_) async => _chargingSnapshot(conservation: false, rapid: true),
      );

      final state = await apply(
        bloc,
        const BatteryConservationSetRequested(false),
      );

      expect(state.batteryConservationEnabled, isFalse);
      expect(state.rapidChargingEnabled, isTrue);
      verifyNever(() => repo.setRapidCharging(false));
    });

    for (final reportedConservation in [false, null]) {
      test(
        'does not confirm conservation with $reportedConservation readback',
        () async {
          final bloc = await start(
            _chargingSnapshot(conservation: false, rapid: true),
          );
          when(() => repo.setBatteryConservation(true))
              .thenAnswer((_) async {});
          when(() => repo.loadSnapshot()).thenAnswer(
            (_) async => _chargingSnapshot(
              conservation: reportedConservation,
              rapid: false,
            ),
          );

          final state = await apply(
            bloc,
            const BatteryConservationSetRequested(true),
          );

          expect(state.batteryConservationEnabled, reportedConservation);
          expect(state.rapidChargingEnabled, isFalse);
          expect(state.noticeMessage, isNull);
          expect(state.errorMessage, isNotNull);
        },
      );
    }

    for (final reportedRapid in [true, false]) {
      test(
        'refreshes failed conservation with rapid charging $reportedRapid',
        () async {
          final bloc = await start(
            _chargingSnapshot(conservation: false, rapid: true),
          );
          final failure = Exception('firmware write failed');
          when(() => repo.setBatteryConservation(true)).thenThrow(failure);
          when(() => repo.loadSnapshot()).thenAnswer(
            (_) async =>
                _chargingSnapshot(conservation: false, rapid: reportedRapid),
          );

          final state = await apply(
            bloc,
            const BatteryConservationSetRequested(true),
          );

          expect(state.batteryConservationEnabled, isFalse);
          expect(state.rapidChargingEnabled, reportedRapid);
          expect(state.noticeMessage, isNull);
          expect(
            state.errorMessage.toString(),
            contains('firmware write failed'),
          );
        },
      );
    }
  });
}

BatterySnapshot _chargingSnapshot({
  required bool? conservation,
  required bool? rapid,
}) => BatterySnapshot(
  batteryConservationEnabled: conservation,
  batteryConservationSupported: conservation != null,
  rapidChargingEnabled: rapid,
  rapidChargingSupported: rapid != null,
  batteryPercent: null,
  batteryCharging: null,
  batteryPowerDrawW: null,
  cycleCounts: null,
  fullCapacityWh: null,
  designCapacityWh: null,
  currentCapacityWh: null,
  batteryTempC: null,
);
