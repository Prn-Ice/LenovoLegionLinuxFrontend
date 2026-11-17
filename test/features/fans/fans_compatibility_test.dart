import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/models/control_capabilities.dart';
import 'package:legion_frontend/core/services/legion_cli_service.dart';
import 'package:legion_frontend/core/services/legion_control_client.dart';
import 'package:legion_frontend/core/services/legion_frontend_bridge_service.dart';
import 'package:legion_frontend/core/services/legion_sysfs_service.dart';
import 'package:legion_frontend/features/fans/bloc/fans_bloc.dart';
import 'package:legion_frontend/features/fans/bloc/fans_event.dart';
import 'package:legion_frontend/features/fans/bloc/fans_state.dart';
import 'package:legion_frontend/features/fans/models/fan_curve.dart';
import 'package:legion_frontend/features/fans/models/fans_snapshot.dart';
import 'package:legion_frontend/features/fans/repository/fans_repository.dart';
import 'package:mocktail/mocktail.dart';

class _MockFansRepository extends Mock implements FansRepository {}

class _MockSysfsService extends Mock implements LegionSysfsService {}

class _MockCliService extends Mock implements LegionCliService {}

class _RecordingTransport extends LegionControlTransport {
  final calls = <String>[];

  @override
  Future<ControlCapabilities> getCapabilities() async => ControlCapabilities(
    protocolVersion: ControlCapabilities.currentProtocolVersion,
    supported: ControlCapability.values,
  );

  @override
  Future<void> authorize() async {}

  @override
  Future<void> call(String method, List<Object> arguments) async {
    calls.add(method);
  }

  @override
  Future<void> close() async {}
}

FanCurve _fullCurve({int firstRpm = 1200}) => FanCurve(
  name: 'compatibility-test',
  fan1MaxRpm: 6000,
  fan2MaxRpm: 6000,
  points: [
    FanCurvePoint(
      fan1Rpm: firstRpm,
      fan2Rpm: 1300,
      cpuLowerTemp: 40,
      cpuUpperTemp: 50,
      gpuLowerTemp: 42,
      gpuUpperTemp: 52,
      icLowerTemp: 44,
      icUpperTemp: 54,
      accel: 5,
      decel: 6,
    ),
    const FanCurvePoint(
      fan1Rpm: 2400,
      fan2Rpm: 2500,
      cpuLowerTemp: 55,
      cpuUpperTemp: 65,
      gpuLowerTemp: 57,
      gpuUpperTemp: 67,
      icLowerTemp: 59,
      icUpperTemp: 69,
      accel: 7,
      decel: 8,
    ),
  ],
);

const _speedOnlyCurve = FanCurve(
  name: 'speed-only',
  schema: FanCurveSchema.speedOnly,
  writeStatus: FanCurveWriteStatus.unvalidated,
  points: [FanCurvePoint(fan1Level: 1, fan2Level: 1)],
);

FansSnapshot _snapshot(FanCurve? curve) => FansSnapshot(
  platformProfile: 'balanced',
  onPowerSupply: true,
  recommendedPreset: 'balanced-ac',
  availablePresets: curve?.canEdit == true
      ? FansRepository.defaultPresets
      : const [],
  miniFanCurveEnabled: true,
  lockFanControllerEnabled: false,
  maximumFanSpeedEnabled: true,
  fanCurve: curve,
);

Future<FansState> _nextState(
  FansBloc bloc,
  bool Function(FansState) predicate,
) => bloc.stream.firstWhere(predicate);

void main() {
  test(
    'mismatching post-save readback keeps the draft dirty and reports error',
    () async {
      final repo = _MockFansRepository();
      final original = _fullCurve();
      final draft = original.copyWithPoint(
        0,
        original.points[0].copyWith(fan1Rpm: 3000),
      );
      var reads = 0;
      when(repo.loadSnapshot).thenAnswer((_) async {
        reads++;
        return _snapshot(reads == 1 ? original : original);
      });
      when(() => repo.writeFanCurveToHardware(draft)).thenAnswer((_) async {});
      final bloc = FansBloc(repository: repo);
      addTearDown(bloc.close);

      final loaded = _nextState(bloc, (state) => !state.isLoading);
      bloc.add(const FansStarted());
      await loaded;
      final edited = _nextState(bloc, (state) => state.fanCurveDirty);
      bloc.add(FanCurvePointUpdated(index: 0, point: draft.points[0]));
      await edited;
      final failed = _nextState(
        bloc,
        (state) => !state.isApplying && state.errorMessage != null,
      );
      bloc.add(const FanCurveSaveRequested());
      final state = await failed;

      expect(state.fanCurve, draft);
      expect(state.authoritativeFanCurve, original);
      expect(state.fanCurveDirty, isTrue);
      expect(state.errorMessage?.message, contains('does not match'));
    },
  );

  test(
    'matching post-save readback clears dirty and renders authoritative curve',
    () async {
      final repo = _MockFansRepository();
      final original = _fullCurve();
      final draft = original.copyWithPoint(
        0,
        original.points[0].copyWith(fan1Rpm: 3000),
      );
      final readback = _fullCurve(firstRpm: 3000);
      var reads = 0;
      when(repo.loadSnapshot).thenAnswer((_) async {
        reads++;
        return _snapshot(reads == 1 ? original : readback);
      });
      when(() => repo.writeFanCurveToHardware(draft)).thenAnswer((_) async {});
      final bloc = FansBloc(repository: repo);
      addTearDown(bloc.close);

      final loaded = _nextState(bloc, (state) => !state.isLoading);
      bloc.add(const FansStarted());
      await loaded;
      final edited = _nextState(bloc, (state) => state.fanCurveDirty);
      bloc.add(FanCurvePointUpdated(index: 0, point: draft.points[0]));
      await edited;
      final saved = _nextState(
        bloc,
        (state) => !state.isApplying && !state.fanCurveDirty,
      );
      bloc.add(const FanCurveSaveRequested());
      final state = await saved;

      expect(state.fanCurve, readback);
      expect(state.authoritativeFanCurve, readback);
      expect(state.fanCurveDirty, isFalse);
    },
  );

  for (final unavailable in <FanCurve?>[null, _speedOnlyCurve]) {
    test(
      'stale draft blocks writes after ${unavailable == null ? 'null' : 'speed-only'} readback and discard restores authority',
      () async {
        final repo = _MockFansRepository();
        final original = _fullCurve();
        final draft = original.copyWithPoint(
          0,
          original.points[0].copyWith(fan1Rpm: 3000),
        );
        var reads = 0;
        when(repo.loadSnapshot).thenAnswer((_) async {
          reads++;
          return _snapshot(reads == 1 ? original : unavailable);
        });
        final bloc = FansBloc(repository: repo);
        addTearDown(bloc.close);

        final loaded = _nextState(bloc, (state) => !state.isLoading);
        bloc.add(const FansStarted());
        await loaded;
        final edited = _nextState(bloc, (state) => state.fanCurveDirty);
        bloc.add(FanCurvePointUpdated(index: 0, point: draft.points[0]));
        await edited;
        final stale = _nextState(
          bloc,
          (state) => state.fanCurveCapabilityStale,
        );
        bloc.add(const FansRefreshRequested());
        final staleState = await stale;

        expect(staleState.fanCurve, draft);
        expect(staleState.authoritativeFanCurve, unavailable);
        expect(staleState.fanCurveDirty, isTrue);
        bloc.add(const FanCurveSaveRequested());
        final selected = _nextState(
          bloc,
          (state) => state.selectedPreset == 'quiet-ac',
        );
        bloc.add(const FansPresetSelectionChanged('quiet-ac'));
        bloc.add(const FansApplySelectedPresetRequested());
        await selected;
        await Future<void>.value();
        verifyNever(() => repo.writeFanCurveToHardware(draft));
        verifyNever(() => repo.applyPreset('quiet-ac'));

        final discarded = _nextState(bloc, (state) => !state.fanCurveDirty);
        bloc.add(const FanCurveDraftDiscarded());
        final state = await discarded;
        expect(state.fanCurve, unavailable);
        expect(state.authoritativeFanCurve, unavailable);
        expect(state.fanCurveCapabilityStale, isFalse);
      },
    );
  }

  test(
    'repository rechecks current curve before every blocked dispatch',
    () async {
      final sysfs = _MockSysfsService();
      final cli = _MockCliService();
      final transport = _RecordingTransport();
      final client = LegionControlClient(transport: transport);
      addTearDown(client.close);
      final bridge = LegionFrontendBridgeService(
        cliService: cli,
        controlClient: client,
      );
      final repository = FansRepository(
        sysfsService: sysfs,
        bridgeService: bridge,
      );
      when(() => sysfs.readPlatformProfile())
          .thenAnswer((_) async => 'balanced');
      when(() => sysfs.readOnPowerSupplyMode()).thenAnswer((_) async => true);
      when(() => sysfs.readMiniFanCurveMode()).thenAnswer((_) async => true);
      when(() => sysfs.readLockFanControllerMode())
          .thenAnswer((_) async => false);
      when(() => sysfs.readMaximumFanSpeedMode()).thenAnswer((_) async => true);
      when(() => sysfs.readFanCurve()).thenAnswer((_) async => _speedOnlyCurve);

      await expectLater(
        repository.applyCurrentContextPreset(),
        throwsA(isA<LegionControlNotSupportedException>()),
      );
      await expectLater(
        repository.applyPreset('quiet-ac'),
        throwsA(isA<LegionControlNotSupportedException>()),
      );
      await expectLater(
        repository.writeFanCurveToHardware(_fullCurve()),
        throwsA(isA<LegionControlNotSupportedException>()),
      );

      verify(() => sysfs.readFanCurve()).called(3);
      expect(transport.calls, isEmpty);
    },
  );
}
