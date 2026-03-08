import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/power/bloc/power_bloc.dart';
import 'package:legion_frontend/features/power/bloc/power_event.dart';
import 'package:legion_frontend/features/power/bloc/power_state.dart';
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
}
