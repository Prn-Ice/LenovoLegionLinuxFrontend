import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:legion_frontend/features/lighting/bloc/lighting_bloc.dart';
import 'package:legion_frontend/features/lighting/bloc/lighting_event.dart';
import 'package:legion_frontend/features/lighting/bloc/lighting_state.dart';
import 'package:legion_frontend/features/lighting/models/lighting_snapshot.dart';
import 'package:legion_frontend/features/lighting/repository/lighting_repository.dart';

class MockLightingRepository extends Mock implements LightingRepository {}

void main() {
  late MockLightingRepository repo;

  setUp(() => repo = MockLightingRepository());

  final snapshot = LightingSnapshot(
    whiteKeyboardBacklightEnabled: false,
    whiteKeyboardBacklightSupported: true,
    yLogoLightEnabled: false,
    yLogoLightSupported: true,
    ioPortLightEnabled: false,
    ioPortLightSupported: true,
  );

  blocTest<LightingBloc, LightingState>(
    'emits loaded snapshot on LightingStarted',
    build: () {
      when(() => repo.loadSnapshot()).thenAnswer((_) async => snapshot);
      return LightingBloc(
        repository: repo,
        pollInterval: const Duration(seconds: 60),
      );
    },
    act: (bloc) => bloc.add(const LightingStarted()),
    wait: const Duration(milliseconds: 100),
    expect: () => [
      isA<LightingState>().having((s) => s.isLoading, 'isLoading', true),
      LightingState(
        whiteKeyboardBacklightEnabled: false,
        whiteKeyboardBacklightSupported: true,
        yLogoLightEnabled: false,
        yLogoLightSupported: true,
        ioPortLightEnabled: false,
        ioPortLightSupported: true,
        isLoading: false,
      ),
    ],
  );
}
