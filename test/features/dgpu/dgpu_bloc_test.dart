import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/models/app_failure.dart';
import 'package:legion_frontend/core/models/gpu_process.dart';
import 'package:legion_frontend/core/models/gpu_process_scan.dart';
import 'package:legion_frontend/features/dgpu/bloc/dgpu_bloc.dart';
import 'package:legion_frontend/features/dgpu/bloc/dgpu_event.dart';
import 'package:legion_frontend/features/dgpu/bloc/dgpu_state.dart';
import 'package:legion_frontend/features/dgpu/models/dgpu_snapshot.dart';
import 'package:legion_frontend/features/dgpu/models/graphics_mode.dart';
import 'package:legion_frontend/features/dgpu/repository/dgpu_repository.dart';
import 'package:mocktail/mocktail.dart';

class MockDgpuRepository extends Mock implements DgpuRepository {}

void main() {
  late MockDgpuRepository repo;

  setUp(() {
    repo = MockDgpuRepository();
    when(() => repo.loadProcessScan(any()))
        .thenAnswer((_) async => GpuProcessScan.noClients);
    when(() => repo.loadDeviceName(any())).thenAnswer((_) async => null);
    when(repo.loadSnapshot).thenAnswer((_) async => _hybridSnapshot);
    when(() => repo.loadGraphicsModeStatus(required: any(named: 'required')))
        .thenAnswer((_) async => _hybridStatus);
  });

  group('DgpuBloc DgpuTicked', () {
    blocTest<DgpuBloc, DgpuState>(
      'DgpuTicked reloads silently when not applying',
      build: () => DgpuBloc(repository: repo),
      seed: () => DgpuState.initial(),
      act: (bloc) => bloc.add(const DgpuTicked()),
      expect: () => [
        isA<DgpuState>().having((s) => s.isLoading, 'isLoading', false),
        isA<DgpuState>().having((s) => s.isLoading, 'isLoading', false),
        isA<DgpuState>().having(
          (s) => s.processScan,
          'process scan',
          GpuProcessScan.noClients,
        ),
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

  test('discards a pending process scan after the GPU is reattached', () async {
    final firstScan = Completer<GpuProcessScan?>();
    final secondScan = Completer<GpuProcessScan?>();
    final firstScanStarted = Completer<void>();
    final secondScanStarted = Completer<void>();
    var snapshot = _hybridSnapshot;
    when(repo.loadSnapshot).thenAnswer((_) async => snapshot);
    when(() => repo.loadProcessScan(_hybridSnapshot.pciAddress!))
        .thenAnswer((_) {
          if (!firstScanStarted.isCompleted) {
            firstScanStarted.complete();
            return firstScan.future;
          }
          secondScanStarted.complete();
          return secondScan.future;
        });
    final bloc = DgpuBloc(repository: repo);
    addTearDown(bloc.close);

    final opened = bloc.stream.firstWhere(
      (state) => state.hasCheckedPci && !state.isLoading,
    );
    bloc.add(const DgpuStarted());
    await firstScanStarted.future;
    await opened;
    expect(bloc.state.graphicsModeStatus, _hybridStatus);
    expect(bloc.state.isLoadingProcesses, isTrue);

    snapshot = const DgpuSnapshot(isActive: null, pciAddress: null);
    final detached = bloc.stream.firstWhere(
      (state) => state.pciAddress == null && !state.isLoading,
    );
    bloc.add(const DgpuRefreshRequested());
    await detached;
    expect(bloc.state.isLoadingProcesses, isFalse);

    snapshot = _hybridSnapshot;
    final reattached = bloc.stream.firstWhere(
      (state) => state.isLoadingProcesses,
    );
    bloc.add(const DgpuRefreshRequested());
    await reattached;

    firstScan.complete(
      const GpuProcessScan(
        processes: [GpuProcess(pid: 42, name: 'Old result')],
        reporting: GpuProcessReporting.reported,
      ),
    );
    await secondScanStarted.future;
    expect(bloc.state.processScan, isNull);
    expect(bloc.state.isLoadingProcesses, isTrue);

    final loaded = bloc.stream.firstWhere((state) => !state.isLoadingProcesses);
    secondScan.complete(GpuProcessScan.noClients);
    expect((await loaded).processScan, GpuProcessScan.noClients);
  });

  blocTest<DgpuBloc, DgpuState>(
    'passes the confirmed PID baseline to the repository',
    build: () {
      when(() => repo.killGpuProcesses([4242])).thenAnswer((_) async {});
      return DgpuBloc(repository: repo);
    },
    seed: () => DgpuState.initial().copyWith(isActive: true),
    act: (bloc) => bloc.add(const DgpuKillProcessesRequested([4242])),
    verify: (_) => verify(() => repo.killGpuProcesses([4242])).called(1),
  );

  blocTest<DgpuBloc, DgpuState>(
    'sets a graphics mode and reloads authoritative state',
    build: () {
      when(() => repo.setGraphicsMode(GraphicsMode.hybridIgpuOnly))
          .thenAnswer((_) async {});
      return DgpuBloc(repository: repo);
    },
    seed: _loadedState,
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
      verify(() => repo.loadGraphicsModeStatus(required: true)).called(1);
    },
  );

  blocTest<DgpuBloc, DgpuState>(
    'reloads authoritative state after a classified graphics failure',
    build: () {
      when(() => repo.setGraphicsMode(GraphicsMode.hybridIgpuOnly)).thenThrow(
        const DgpuRepositoryException(
          'The selected policy may have changed; restore Hybrid.',
          kind: AppFailureKind.graphicsPending,
        ),
      );
      return DgpuBloc(repository: repo);
    },
    seed: _loadedState,
    act: (bloc) => bloc.add(
      const DgpuGraphicsModeSetRequested(GraphicsMode.hybridIgpuOnly),
    ),
    expect: () => [
      isA<DgpuState>().having((state) => state.isApplying, 'applying', true),
      isA<DgpuState>()
          .having(
            (state) => state.errorMessage?.message,
            'error',
            contains('may have changed'),
          )
          .having(
            (state) => state.errorMessage?.kind,
            'kind',
            AppFailureKind.graphicsPending,
          ),
    ],
    verify: (_) =>
        verify(() => repo.loadGraphicsModeStatus(required: true)).called(1),
  );

  blocTest<DgpuBloc, DgpuState>(
    'passes the confirmed PCI baseline to the repository',
    build: () {
      when(() => repo.restartPciDevice('0000:01:00.0'))
          .thenAnswer((_) async {});
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

  blocTest<DgpuBloc, DgpuState>(
    'keeps the graphics consequence when authoritative reload also fails',
    build: () {
      when(() => repo.setGraphicsMode(GraphicsMode.hybridIgpuOnly)).thenThrow(
        const DgpuRepositoryException(
          'Policy accepted',
          kind: AppFailureKind.graphicsPending,
          details: 'write diagnostic',
        ),
      );
      when(() => repo.loadGraphicsModeStatus(required: true))
          .thenThrow(StateError('read failed'));
      return DgpuBloc(repository: repo);
    },
    act: (bloc) => bloc.add(
      const DgpuGraphicsModeSetRequested(GraphicsMode.hybridIgpuOnly),
    ),
    verify: (bloc) {
      final failure = bloc.state.errorMessage!;
      expect(failure.kind, AppFailureKind.graphicsPending);
      expect(failure.details, 'write diagnostic');
      expect(failure.message, contains('Policy accepted'));
      expect(failure.message, contains('read failed'));
    },
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
  pciAddress: '0000:01:00.0',
);

DgpuState _loadedState() => DgpuState.initial().copyWith(
  isActive: _hybridSnapshot.isActive,
  pciAddress: _hybridSnapshot.pciAddress,
  graphicsModeStatus: _hybridStatus,
  hasCheckedPci: true,
  hasLoadedGraphicsMode: true,
  processScan: GpuProcessScan.noClients,
);
