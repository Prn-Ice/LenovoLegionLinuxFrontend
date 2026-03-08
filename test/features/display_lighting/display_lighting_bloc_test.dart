import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/display_lighting/bloc/display_lighting_bloc.dart';
import 'package:legion_frontend/features/display_lighting/bloc/display_lighting_event.dart';
import 'package:legion_frontend/features/display_lighting/bloc/display_lighting_state.dart';
import 'package:legion_frontend/features/display_lighting/models/display_lighting_snapshot.dart';
import 'package:legion_frontend/features/display_lighting/repository/display_lighting_repository.dart';
import 'package:mocktail/mocktail.dart';

class MockDisplayLightingRepository extends Mock
    implements DisplayLightingRepository {}

void main() {
  late MockDisplayLightingRepository repo;

  setUp(() {
    repo = MockDisplayLightingRepository();
    when(() => repo.loadSnapshot()).thenAnswer(
      (_) async => const DisplayLightingSnapshot(
        hybridModeEnabled: true,
        hybridModeSupported: false,
        overdriveEnabled: null,
        overdriveSupported: false,
        whiteKeyboardBacklightEnabled: null,
        whiteKeyboardBacklightSupported: false,
        yLogoLightEnabled: null,
        yLogoLightSupported: false,
        ioPortLightEnabled: null,
        ioPortLightSupported: false,
        xrandrOutputName: null,
        availableRefreshRates: null,
        currentRefreshRate: null,
      ),
    );
  });

  group('DisplayLightingBloc DisplayLightingTicked', () {
    blocTest<DisplayLightingBloc, DisplayLightingState>(
      'DisplayLightingTicked reloads silently when not applying',
      build: () => DisplayLightingBloc(repository: repo),
      seed: () => DisplayLightingState.initial(),
      act: (bloc) => bloc.add(const DisplayLightingTicked()),
      expect: () => [
        isA<DisplayLightingState>().having(
          (s) => s.isLoading,
          'isLoading',
          false,
        ),
      ],
    );

    blocTest<DisplayLightingBloc, DisplayLightingState>(
      'DisplayLightingTicked is skipped when isApplying',
      build: () => DisplayLightingBloc(repository: repo),
      seed: () => DisplayLightingState.initial().copyWith(isApplying: true),
      act: (bloc) => bloc.add(const DisplayLightingTicked()),
      expect: () => isEmpty,
    );
  });
}
