import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/power/bloc/power_bloc.dart';
import 'package:legion_frontend/features/power/bloc/power_event.dart';
import 'package:legion_frontend/features/power/bloc/power_state.dart';
import 'package:legion_frontend/features/power/models/power_limit.dart';
import 'package:legion_frontend/features/power/models/power_mode.dart';
import 'package:legion_frontend/features/power/models/power_snapshot.dart';
import 'package:legion_frontend/features/power/repository/power_repository.dart';
import 'package:mocktail/mocktail.dart';

class MockPowerRepository extends Mock implements PowerRepository {}

void main() {
  late MockPowerRepository repo;

  setUp(() {
    repo = MockPowerRepository();
    when(() => repo.loadSnapshot()).thenAnswer(
      (_) async => const PowerSnapshot(
        currentMode: null,
        availableModes: [PowerMode('quiet')],
        powerLimits: [],
        cpuOverclockEnabled: null,
        gpuOverclockEnabled: null,
      ),
    );
  });

  group('PowerBloc PowerTicked', () {
    blocTest<PowerBloc, PowerState>(
      'PowerTicked reloads silently when not applying',
      build: () => PowerBloc(repository: repo),
      seed: () => PowerState.initial(),
      act: (bloc) => bloc.add(const PowerTicked()),
      expect: () => [
        isA<PowerState>().having((s) => s.isLoading, 'isLoading', false),
      ],
    );

    blocTest<PowerBloc, PowerState>(
      'PowerTicked is skipped when isApplying',
      build: () => PowerBloc(repository: repo),
      seed: () => PowerState.initial().copyWith(isApplying: true),
      act: (bloc) => bloc.add(const PowerTicked()),
      expect: () => isEmpty,
    );
  });

  test(
    'failed readback reloads the authoritative value without success',
    () async {
      final spec = PowerRepository.allPowerLimits.first;
      final actual = PowerLimitReading(spec: spec, value: 55);
      final requested = PowerLimitReading(spec: spec, value: 60);
      when(() => repo.setPowerLimits(any())).thenThrow(
        PowerLimitReadbackException(limit: spec, requested: 60, actual: 55),
      );
      when(() => repo.loadSnapshot()).thenAnswer(
        (_) async => PowerSnapshot(
          currentMode: const PowerMode('custom'),
          availableModes: const [PowerMode('custom')],
          powerLimits: [actual],
          cpuOverclockEnabled: null,
          gpuOverclockEnabled: null,
          onPowerSupply: true,
        ),
      );
      final bloc = PowerBloc(repository: repo);
      addTearDown(bloc.close);

      final states = <PowerState>[];
      final subscription = bloc.stream.listen(states.add);
      addTearDown(subscription.cancel);
      bloc.add(PowerLimitsApplyRequested([requested]));
      await bloc.stream.firstWhere(
        (state) => !state.isApplying && state.errorMessage != null,
      );

      expect(states, hasLength(3));
      expect(states[0].isApplying, isTrue);
      expect(states[1].powerLimits.single.value, 55);
      expect(states[1].errorMessage, isNull);
      expect(states[1].noticeMessage, isNull);
      expect(states[2].powerLimits.single.value, 55);
      expect(states[2].isApplying, isFalse);
      expect(states[2].errorMessage?.message, contains('did not accept'));
      expect(states[2].noticeMessage, isNull);
    },
  );
}
