import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/dgpu/bloc/dgpu_bloc.dart';
import 'package:legion_frontend/features/dgpu/bloc/dgpu_event.dart';
import 'package:legion_frontend/features/dgpu/bloc/dgpu_state.dart';
import 'package:legion_frontend/features/dgpu/models/dgpu_snapshot.dart';
import 'package:legion_frontend/features/dgpu/repository/dgpu_repository.dart';
import 'package:mocktail/mocktail.dart';

class MockDgpuRepository extends Mock implements DgpuRepository {}

void main() {
  late MockDgpuRepository repo;

  setUp(() {
    repo = MockDgpuRepository();
    when(() => repo.loadSnapshot()).thenAnswer(
      (_) async => const DgpuSnapshot(
        isActive: true,
        processes: [],
        pciAddress: '0000:01:00.0',
        hybridModeEnabled: null,
        hybridModeSupported: false,
      ),
    );
  });

  group('DgpuBloc DgpuTicked', () {
    blocTest<DgpuBloc, DgpuState>(
      'DgpuTicked reloads silently when not applying',
      build: () => DgpuBloc(repository: repo),
      seed: () => DgpuState.initial(),
      act: (bloc) => bloc.add(const DgpuTicked()),
      expect: () => [
        isA<DgpuState>().having((s) => s.isLoading, 'isLoading', false),
      ],
    );

    blocTest<DgpuBloc, DgpuState>(
      'DgpuTicked is skipped when isApplying',
      build: () => DgpuBloc(repository: repo),
      seed: () => DgpuState.initial().copyWith(isApplying: true),
      act: (bloc) => bloc.add(const DgpuTicked()),
      expect: () => isEmpty,
    );
  });
}
