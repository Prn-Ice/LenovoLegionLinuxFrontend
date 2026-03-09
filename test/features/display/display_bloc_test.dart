import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:legion_frontend/features/display/bloc/display_bloc.dart';
import 'package:legion_frontend/features/display/bloc/display_event.dart';
import 'package:legion_frontend/features/display/bloc/display_state.dart';
import 'package:legion_frontend/features/display/models/display_snapshot.dart';
import 'package:legion_frontend/features/display/repository/display_repository.dart';

class MockDisplayRepository extends Mock implements DisplayRepository {}

void main() {
  late MockDisplayRepository repo;

  setUp(() => repo = MockDisplayRepository());

  final snapshot = DisplaySnapshot(
    overdriveEnabled: false,
    overdriveSupported: true,
    xrandrOutputName: 'eDP-1',
    availableRefreshRates: const [60.0, 165.0],
    currentRefreshRate: 165.0,
  );

  blocTest<DisplayBloc, DisplayState>(
    'emits loaded snapshot on DisplayStarted',
    build: () {
      when(() => repo.loadSnapshot()).thenAnswer((_) async => snapshot);
      return DisplayBloc(
        repository: repo,
        pollInterval: const Duration(seconds: 60),
      );
    },
    act: (bloc) => bloc.add(const DisplayStarted()),
    wait: const Duration(milliseconds: 100),
    expect: () => [
      isA<DisplayState>().having((s) => s.isLoading, 'isLoading', true),
      DisplayState(
        overdriveEnabled: false,
        overdriveSupported: true,
        xrandrOutputName: 'eDP-1',
        availableRefreshRates: const [60.0, 165.0],
        currentRefreshRate: 165.0,
        isLoading: false,
      ),
    ],
  );
}
