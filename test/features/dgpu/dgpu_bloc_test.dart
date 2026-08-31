import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/dgpu/bloc/dgpu_bloc.dart';
import 'package:legion_frontend/features/dgpu/bloc/dgpu_event.dart';
import 'package:legion_frontend/features/dgpu/bloc/dgpu_state.dart';
import 'package:legion_frontend/features/dgpu/models/dgpu_snapshot.dart';
import 'package:legion_frontend/features/dgpu/models/dgpu_process.dart';
import 'package:legion_frontend/features/dgpu/models/graphics_mode.dart';
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
        graphicsModeStatus: null,
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

  blocTest<DgpuBloc, DgpuState>(
    'passes the confirmed PID baseline to the repository',
    build: () {
      when(() => repo.killGpuProcesses([4242])).thenAnswer((_) async {});
      return DgpuBloc(repository: repo);
    },
    seed: () => DgpuState.initial().copyWith(
      isActive: true,
      processes: const [
        DgpuProcess(pid: 4242, name: 'blender', usedMemoryMib: 1024),
      ],
    ),
    act: (bloc) => bloc.add(const DgpuKillProcessesRequested([4242])),
    verify: (_) => verify(() => repo.killGpuProcesses([4242])).called(1),
  );

  blocTest<DgpuBloc, DgpuState>(
    'sets a graphics mode and reloads authoritative state',
    build: () {
      when(
        () => repo.setGraphicsMode(GraphicsMode.hybridIgpuOnly),
      ).thenAnswer((_) async {});
      when(
        repo.loadSnapshotAfterGraphicsWrite,
      ).thenAnswer((_) async => _hybridSnapshot);
      return DgpuBloc(repository: repo);
    },
    seed: () => DgpuState.initial().copyWith(
      graphicsModeStatus: _hybridStatus,
      hasLoaded: true,
    ),
    act: (bloc) => bloc.add(
      const DgpuGraphicsModeSetRequested(GraphicsMode.hybridIgpuOnly),
    ),
    expect: () => [
      isA<DgpuState>().having((state) => state.isApplying, 'applying', true),
      isA<DgpuState>()
          .having((state) => state.isApplying, 'applying', false)
          .having((state) => state.errorMessage, 'error', isNull),
    ],
    verify: (_) {
      verify(() => repo.setGraphicsMode(GraphicsMode.hybridIgpuOnly)).called(1);
      verify(repo.loadSnapshotAfterGraphicsWrite).called(1);
    },
  );

  blocTest<DgpuBloc, DgpuState>(
    'reloads authoritative state after a classified graphics failure',
    build: () {
      when(() => repo.setGraphicsMode(GraphicsMode.hybridIgpuOnly)).thenThrow(
        const DgpuRepositoryException(
          'The selected policy may have changed; restore Hybrid.',
        ),
      );
      when(
        repo.loadSnapshotAfterGraphicsWrite,
      ).thenAnswer((_) async => _hybridSnapshot);
      return DgpuBloc(repository: repo);
    },
    seed: () => DgpuState.initial().copyWith(
      graphicsModeStatus: _hybridStatus,
      hasLoaded: true,
    ),
    act: (bloc) => bloc.add(
      const DgpuGraphicsModeSetRequested(GraphicsMode.hybridIgpuOnly),
    ),
    expect: () => [
      isA<DgpuState>().having((state) => state.isApplying, 'applying', true),
      isA<DgpuState>().having(
        (state) => state.errorMessage,
        'error',
        contains('may have changed'),
      ),
    ],
    verify: (_) => verify(repo.loadSnapshotAfterGraphicsWrite).called(1),
  );

  blocTest<DgpuBloc, DgpuState>(
    'passes the confirmed PCI baseline to the repository',
    build: () {
      when(
        () => repo.restartPciDevice('0000:01:00.0'),
      ).thenAnswer((_) async {});
      return DgpuBloc(repository: repo);
    },
    seed: () => DgpuState.initial().copyWith(
      isActive: true,
      pciAddress: '0000:01:00.0',
    ),
    act: (bloc) => bloc.add(const DgpuRestartPciRequested('0000:01:00.0')),
    verify: (_) =>
        verify(() => repo.restartPciDevice('0000:01:00.0')).called(1),
  );
}

const _hybridStatus = GraphicsModeStatus(
  selectedMode: GraphicsMode.hybrid,
  effectiveState: DgpuTopology.attached,
  expectedState: DgpuTopology.attached,
  reconciliation: GraphicsReconciliation.settled,
  clientInspectionComplete: false,
  activeClients: [],
  availableModes: GraphicsMode.values,
  reconciliationAttempts: null,
);

const _hybridSnapshot = DgpuSnapshot(
  isActive: true,
  processes: [],
  pciAddress: '0000:01:00.0',
  graphicsModeStatus: _hybridStatus,
);
