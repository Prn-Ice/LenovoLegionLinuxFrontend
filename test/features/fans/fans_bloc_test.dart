import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/fans/bloc/fans_bloc.dart';
import 'package:legion_frontend/features/fans/bloc/fans_event.dart';
import 'package:legion_frontend/features/fans/bloc/fans_state.dart';
import 'package:legion_frontend/features/fans/models/fan_curve.dart';

import '../../helpers/fake_fans_repository.dart';

FanCurve _tenPointCurve() => FanCurve(
  name: 'test',
  points: List.generate(
    10,
    (_) => const FanCurvePoint(
      fan1Rpm: 1200,
      fan2Rpm: 1200,
      cpuLowerTemp: 40,
      cpuUpperTemp: 50,
      gpuLowerTemp: 40,
      gpuUpperTemp: 50,
      icLowerTemp: 40,
      icUpperTemp: 50,
      accel: 5,
      decel: 5,
    ),
  ),
);

void main() {
  group('FansBloc.FansPresetSelectionChanged', () {
    late FakeFansRepository repo;

    setUp(() {
      repo = FakeFansRepository();
    });

    blocTest<FansBloc, FansState>(
      'updates selectedPreset to the new value',
      build: () => FansBloc(repository: repo),
      act: (bloc) => bloc.add(const FansPresetSelectionChanged('quiet-ac')),
      expect: () => [
        isA<FansState>().having(
          (s) => s.selectedPreset,
          'selectedPreset',
          equals('quiet-ac'),
        ),
      ],
    );

    blocTest<FansBloc, FansState>(
      'clears errorMessage when preset changes',
      build: () => FansBloc(repository: repo),
      seed: () => FansState.initial().copyWith(errorMessage: 'old error'),
      act: (bloc) => bloc.add(const FansPresetSelectionChanged('balanced-ac')),
      expect: () => [
        isA<FansState>()
            .having((s) => s.selectedPreset, 'selectedPreset', 'balanced-ac')
            .having((s) => s.errorMessage, 'errorMessage', isNull),
      ],
    );

    blocTest<FansBloc, FansState>(
      'subsequent selections each emit a new state',
      build: () => FansBloc(repository: repo),
      act: (bloc) {
        bloc.add(const FansPresetSelectionChanged('quiet-ac'));
        bloc.add(const FansPresetSelectionChanged('performance-ac'));
      },
      expect: () => [
        isA<FansState>().having(
          (s) => s.selectedPreset,
          'selectedPreset',
          'quiet-ac',
        ),
        isA<FansState>().having(
          (s) => s.selectedPreset,
          'selectedPreset',
          'performance-ac',
        ),
      ],
    );
  });

  group('FansBloc.FanCurvePointUpdated', () {
    late FakeFansRepository repo;

    setUp(() {
      repo = FakeFansRepository();
    });

    blocTest<FansBloc, FansState>(
      'emits state with updated curve point and fanCurveDirty: true',
      build: () => FansBloc(repository: repo),
      seed: () => FansState.initial().copyWith(fanCurve: _tenPointCurve()),
      act: (bloc) => bloc.add(
        const FanCurvePointUpdated(
          index: 0,
          point: FanCurvePoint(
            fan1Rpm: 2000,
            fan2Rpm: 2000,
            cpuLowerTemp: 50,
            cpuUpperTemp: 60,
            gpuLowerTemp: 50,
            gpuUpperTemp: 60,
            icLowerTemp: 50,
            icUpperTemp: 60,
            accel: 5,
            decel: 5,
          ),
        ),
      ),
      expect: () => [
        isA<FansState>()
            .having((s) => s.fanCurveDirty, 'fanCurveDirty', isTrue)
            .having(
              (s) => s.fanCurve?.points[0].fan1Rpm,
              'fan1Rpm at index 0',
              equals(2000),
            ),
      ],
    );

    blocTest<FansBloc, FansState>(
      'does nothing when fanCurve is null',
      build: () => FansBloc(repository: repo),
      act: (bloc) => bloc.add(
        const FanCurvePointUpdated(
          index: 0,
          point: FanCurvePoint(
            fan1Rpm: 9999,
            fan2Rpm: 9999,
            cpuLowerTemp: 99,
            cpuUpperTemp: 99,
            gpuLowerTemp: 99,
            gpuUpperTemp: 99,
            icLowerTemp: 99,
            icUpperTemp: 99,
            accel: 5,
            decel: 5,
          ),
        ),
      ),
      expect: () => [],
    );

    blocTest<FansBloc, FansState>(
      'does nothing when index is out of bounds',
      build: () => FansBloc(repository: repo),
      seed: () => FansState.initial().copyWith(fanCurve: _tenPointCurve()),
      act: (bloc) => bloc.add(
        const FanCurvePointUpdated(
          index: 10,
          point: FanCurvePoint(
            fan1Rpm: 1,
            fan2Rpm: 1,
            cpuLowerTemp: 1,
            cpuUpperTemp: 1,
            gpuLowerTemp: 1,
            gpuUpperTemp: 1,
            icLowerTemp: 1,
            icUpperTemp: 1,
            accel: 1,
            decel: 1,
          ),
        ),
      ),
      expect: () => [],
    );
  });
}
