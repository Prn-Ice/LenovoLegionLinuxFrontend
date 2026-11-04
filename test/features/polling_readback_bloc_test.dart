import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/models/app_failure.dart';
import 'package:mocktail/mocktail.dart';
import 'package:riverbloc/riverbloc.dart';
import 'package:legion_frontend/features/devices/bloc/devices_bloc.dart';
import 'package:legion_frontend/features/devices/bloc/devices_event.dart';
import 'package:legion_frontend/features/devices/models/devices_snapshot.dart';
import 'package:legion_frontend/features/devices/repository/devices_repository.dart';
import 'package:legion_frontend/features/display/bloc/display_bloc.dart';
import 'package:legion_frontend/features/display/bloc/display_event.dart';
import 'package:legion_frontend/features/display/models/display_snapshot.dart';
import 'package:legion_frontend/features/display/repository/display_repository.dart';
import 'package:legion_frontend/features/battery/bloc/battery_bloc.dart';
import 'package:legion_frontend/features/battery/bloc/battery_event.dart';
import 'package:legion_frontend/features/battery/models/battery_snapshot.dart';
import 'package:legion_frontend/features/battery/repository/battery_repository.dart';
import 'package:legion_frontend/features/power/bloc/power_bloc.dart';
import 'package:legion_frontend/features/power/bloc/power_event.dart';
import 'package:legion_frontend/features/power/models/power_snapshot.dart';
import 'package:legion_frontend/features/power/repository/power_repository.dart';
import 'package:legion_frontend/features/fans/bloc/fans_bloc.dart';
import 'package:legion_frontend/features/fans/bloc/fans_event.dart';
import 'package:legion_frontend/features/fans/models/fans_snapshot.dart';
import 'package:legion_frontend/features/fans/repository/fans_repository.dart';
import 'package:legion_frontend/features/lighting/bloc/lighting_bloc.dart';
import 'package:legion_frontend/features/lighting/bloc/lighting_event.dart';
import 'package:legion_frontend/features/lighting/models/lighting_snapshot.dart';
import 'package:legion_frontend/features/lighting/repository/lighting_repository.dart';

class _DevicesRepository extends Mock implements DevicesRepository {}

class _DisplayRepository extends Mock implements DisplayRepository {}

class _BatteryRepository extends Mock implements BatteryRepository {}

class _PowerRepository extends Mock implements PowerRepository {}

class _FansRepository extends Mock implements FansRepository {}

class _LightingRepository extends Mock implements LightingRepository {}

void main() {
  _pollingContract(
    'devices',
    build: (read, write, interval) {
      final repo = _DevicesRepository();
      when(repo.loadSnapshot).thenAnswer((_) => read());
      when(() => repo.setTouchpad(true)).thenAnswer((_) => write());
      return DevicesBloc(repository: repo, pollInterval: interval);
    },
    snapshot: (enabled) => DevicesSnapshot(
      touchpadEnabled: enabled,
      touchpadSupported: true,
      winKeyEnabled: null,
      winKeySupported: false,
      fnLockEnabled: null,
      fnLockSupported: false,
      cameraEnabled: null,
      cameraSupported: false,
    ),
    start: const DevicesStarted(),
    tick: const DevicesTicked(),
    write: const TouchpadSetRequested(true),
    value: (s) => s.touchpadEnabled,
    busy: (s) => s.isApplying,
    notice: (s) => s.noticeMessage,
    error: (s) => s.errorMessage,
  );
  _pollingContract(
    'display',
    build: (read, write, interval) {
      final repo = _DisplayRepository();
      when(repo.loadSnapshot).thenAnswer((_) => read());
      when(() => repo.setOverdriveMode(true)).thenAnswer((_) => write());
      return DisplayBloc(repository: repo, pollInterval: interval);
    },
    snapshot: (enabled) => DisplaySnapshot(
      overdriveEnabled: enabled,
      overdriveSupported: true,
      xrandrOutputName: null,
      availableRefreshRates: null,
      currentRefreshRate: null,
    ),
    start: const DisplayStarted(),
    tick: const DisplayTicked(),
    write: const OverdriveModeSetRequested(true),
    value: (s) => s.overdriveEnabled,
    busy: (s) => s.isApplying,
    notice: (s) => s.noticeMessage,
    error: (s) => s.errorMessage,
  );
  _pollingContract(
    'battery',
    build: (read, write, interval) {
      final repo = _BatteryRepository();
      when(repo.loadSnapshot).thenAnswer((_) => read());
      when(() => repo.setBatteryConservation(true)).thenAnswer((_) => write());
      return BatteryBloc(repository: repo, pollInterval: interval);
    },
    snapshot: (enabled) => BatterySnapshot(
      batteryConservationEnabled: enabled,
      batteryConservationSupported: true,
      rapidChargingEnabled: null,
      rapidChargingSupported: false,
      batteryPercent: null,
      batteryCharging: null,
      batteryPowerDrawW: null,
      cycleCounts: null,
      fullCapacityWh: null,
      designCapacityWh: null,
      currentCapacityWh: null,
      batteryTempC: null,
    ),
    start: const BatteryStarted(),
    tick: const BatteryTicked(),
    write: const BatteryConservationSetRequested(true),
    value: (s) => s.batteryConservationEnabled,
    busy: (s) => s.isApplying,
    notice: (s) => s.noticeMessage,
    error: (s) => s.errorMessage,
  );
  _pollingContract(
    'power',
    build: (read, write, interval) {
      final repo = _PowerRepository();
      when(repo.loadSnapshot).thenAnswer((_) => read());
      when(() => repo.setCpuOverclock(true)).thenAnswer((_) => write());
      return PowerBloc(repository: repo, pollInterval: interval);
    },
    snapshot: (enabled) => PowerSnapshot(
      currentMode: null,
      availableModes: const [],
      powerLimits: const [],
      cpuOverclockEnabled: enabled,
      gpuOverclockEnabled: null,
    ),
    start: const PowerStarted(),
    tick: const PowerTicked(),
    write: const CpuOverclockSetRequested(true),
    value: (s) => s.cpuOverclockEnabled,
    busy: (s) => s.isApplying,
    notice: (s) => s.noticeMessage,
    error: (s) => s.errorMessage,
  );
  _pollingContract(
    'fans',
    build: (read, write, interval) {
      final repo = _FansRepository();
      when(repo.loadSnapshot).thenAnswer((_) => read());
      when(() => repo.setMiniFanCurve(true)).thenAnswer((_) => write());
      return FansBloc(repository: repo, pollInterval: interval);
    },
    snapshot: (enabled) => FansSnapshot(
      platformProfile: null,
      onPowerSupply: null,
      recommendedPreset: null,
      availablePresets: const [],
      miniFanCurveEnabled: enabled,
      lockFanControllerEnabled: null,
      maximumFanSpeedEnabled: null,
      fanCurve: null,
    ),
    start: const FansStarted(),
    tick: const FansTicked(),
    write: const MiniFanCurveSetRequested(true),
    value: (s) => s.miniFanCurveEnabled,
    busy: (s) => s.isApplying,
    notice: (s) => s.noticeMessage,
    error: (s) => s.errorMessage,
  );
  _pollingContract(
    'lighting',
    build: (read, write, interval) {
      final repo = _LightingRepository();
      when(repo.loadSnapshot).thenAnswer((_) => read());
      when(() => repo.setYLogoLight(true)).thenAnswer((_) => write());
      return LightingBloc(repository: repo, pollInterval: interval);
    },
    snapshot: (enabled) => LightingSnapshot(
      whiteKeyboardBacklightEnabled: null,
      whiteKeyboardBacklightSupported: false,
      yLogoLightEnabled: enabled,
      yLogoLightSupported: true,
      ioPortLightEnabled: null,
      ioPortLightSupported: false,
    ),
    start: const LightingStarted(),
    tick: const LightingTicked(),
    write: const YLogoLightSetRequested(true),
    value: (s) => s.yLogoLightEnabled,
    busy: (s) => s.isApplying,
    notice: (s) => s.noticeMessage,
    error: (s) => s.errorMessage,
  );
}

// Same externally observable ordering promise for each real feature Bloc.
void _pollingContract<E, S, T>(
  String feature, {
  required Bloc<E, S> Function(
    Future<T> Function() read,
    Future<void> Function() write,
    Duration interval,
  )
  build,
  required T Function(bool enabled) snapshot,
  required E start,
  required E tick,
  required E write,
  required bool? Function(S) value,
  required bool Function(S) busy,
  required String? Function(S) notice,
  required AppFailure? Function(S) error,
}) {
  group(feature, () {
    testWidgets('poll completes before write and mandatory readback', (
      tester,
    ) async {
      final poll = Completer<T>();
      final readback = Completer<T>();
      final writing = Completer<void>();
      final calls = <String>[];
      var reads = 0;
      final bloc = build(
        () {
          calls.add('read');
          reads++;
          return switch (reads) {
            1 => Future.value(snapshot(false)),
            2 => poll.future,
            _ => readback.future,
          };
        },
        () {
          calls.add('write');
          return writing.future;
        },
        const Duration(days: 1),
      );
      bloc.add(start);
      await tester.pump();
      bloc.add(tick);
      await tester.pump();
      bloc.add(write);
      await tester.pump();
      expect(calls, ['read', 'read']);
      poll.complete(snapshot(false));
      await tester.pump();
      expect(calls, ['read', 'read', 'write']);
      writing.complete();
      await tester.pump();
      expect(calls, ['read', 'read', 'write', 'read']);
      expect(busy(bloc.state), isTrue);
      expect(notice(bloc.state), isNull);
      // A repeated request while readback is pending must not become a later write.
      bloc.add(write);
      readback.complete(snapshot(true));
      await tester.pump();
      expect(value(bloc.state), isTrue);
      expect(busy(bloc.state), isFalse);
      expect(notice(bloc.state), isNotNull);
      expect(calls, ['read', 'read', 'write', 'read']);
      await tester.runAsync(bloc.close);
    });

    testWidgets('failed write preserves its typed failure without success', (
      tester,
    ) async {
      const failure = AppFailure(
        'Write rejected',
        kind: AppFailureKind.permissionDenied,
        details: 'Authorization was denied.',
      );
      var reads = 0;
      final bloc = build(
        () async {
          reads++;
          return snapshot(false);
        },
        () async => throw failure,
        const Duration(days: 1),
      );
      bloc.add(start);
      await tester.pump();
      bloc.add(write);
      await tester.pump();
      expect(busy(bloc.state), isFalse);
      expect(error(bloc.state), failure);
      expect(notice(bloc.state), isNull);
      expect(value(bloc.state), isFalse);
      expect(reads, 1);
      await tester.runAsync(bloc.close);
    });

    testWidgets('failed write readback reports failure without success', (
      tester,
    ) async {
      final readback = Completer<T>();
      var reads = 0;
      final bloc = build(
        () => ++reads == 1 ? Future.value(snapshot(false)) : readback.future,
        () async {},
        const Duration(days: 1),
      );
      bloc.add(start);
      await tester.pump();
      bloc.add(write);
      await tester.pump();
      expect(reads, 2);
      expect(busy(bloc.state), isTrue);
      readback.completeError(
        const AppFailure(
          'readback failed',
          kind: AppFailureKind.unavailable,
          details: 'Device disconnected.',
        ),
      );
      await tester.pump();
      expect(busy(bloc.state), isFalse);
      expect(error(bloc.state)?.message, contains('readback failed'));
      expect(error(bloc.state)?.kind, AppFailureKind.unavailable);
      expect(error(bloc.state)?.details, 'Device disconnected.');
      expect(notice(bloc.state), isNull);
      expect(value(bloc.state), isFalse);
      await tester.runAsync(bloc.close);
    });

    testWidgets(
      'close during initial read cannot start a timer or queued write',
      (tester) async {
        final initial = Completer<T>();
        var reads = 0;
        var writes = 0;
        final bloc = build(
          () {
            reads++;
            return initial.future;
          },
          () async {
            writes++;
          },
          const Duration(seconds: 1),
        );
        bloc.add(start);
        await tester.pump();
        bloc.add(write);
        late Future<void> closed;
        await tester.runAsync(() async {
          closed = bloc.close();
        });
        initial.complete(snapshot(false));
        await tester.pump();
        await tester.runAsync(() => closed);
        await tester.pump(const Duration(seconds: 10));
        expect(reads, 1);
        expect(writes, 0);
        // testWidgets also rejects any leaked periodic timer.
      },
    );

    testWidgets('slow polling does not accumulate periodic ticks', (
      tester,
    ) async {
      final poll = Completer<T>();
      var reads = 0;
      final bloc = build(
        () {
          reads++;
          return reads == 2 ? poll.future : Future.value(snapshot(false));
        },
        () async {},
        const Duration(seconds: 1),
      );
      bloc.add(start);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(reads, 2);
      await tester.pump(const Duration(seconds: 20));
      expect(reads, 2);
      poll.complete(snapshot(false));
      await tester.pump();
      expect(reads, 2);
      await tester.pump(const Duration(seconds: 1));
      expect(reads, 3);
      await tester.runAsync(bloc.close);
    });
  });
}
