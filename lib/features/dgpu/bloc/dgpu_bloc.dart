import 'dart:async';

import 'package:riverbloc/riverbloc.dart';

import '../repository/dgpu_repository.dart';
import 'dgpu_event.dart';
import 'dgpu_state.dart';

class DgpuBloc extends Bloc<DgpuEvent, DgpuState> {
  DgpuBloc({
    required DgpuRepository repository,
    Duration pollInterval = const Duration(seconds: 5),
  }) : _repository = repository,
       _pollInterval = pollInterval,
       super(DgpuState.initial()) {
    on<DgpuStarted>(_onStarted);
    on<DgpuRefreshRequested>(_onRefreshRequested);
    on<DgpuTicked>(_onTicked);
    on<DgpuKillProcessesRequested>(_onKillProcessesRequested);
    on<DgpuRestartPciRequested>(_onRestartPciRequested);
  }

  final DgpuRepository _repository;
  final Duration _pollInterval;

  Timer? _pollTimer;
  bool _started = false;
  bool _refreshInFlight = false;

  Future<void> _onStarted(DgpuStarted event, Emitter<DgpuState> emit) async {
    if (_started) return;
    _started = true;
    await _reloadState(emit, showLoading: true);
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      add(const DgpuTicked());
    });
  }

  Future<void> _onRefreshRequested(
    DgpuRefreshRequested event,
    Emitter<DgpuState> emit,
  ) async {
    await _reloadState(emit, showLoading: true);
  }

  Future<void> _onTicked(DgpuTicked event, Emitter<DgpuState> emit) async {
    if (state.isApplying) return;
    await _reloadState(emit, showLoading: false);
  }

  Future<void> _onKillProcessesRequested(
    DgpuKillProcessesRequested event,
    Emitter<DgpuState> emit,
  ) async {
    if (state.isApplying) return;
    emit(
      state.copyWith(isApplying: true, errorMessage: null, noticeMessage: null),
    );
    try {
      await _repository.killGpuProcesses();
      await _reloadState(
        emit,
        showLoading: false,
        noticeMessage: 'GPU processes killed.',
      );
    } on DgpuRepositoryException catch (error) {
      emit(state.copyWith(isApplying: false, errorMessage: error.message));
    }
  }

  Future<void> _onRestartPciRequested(
    DgpuRestartPciRequested event,
    Emitter<DgpuState> emit,
  ) async {
    if (state.isApplying) return;
    emit(
      state.copyWith(isApplying: true, errorMessage: null, noticeMessage: null),
    );
    try {
      await _repository.restartPciDevice();
      await _reloadState(
        emit,
        showLoading: false,
        noticeMessage:
            'PCI device restarted. The GPU will reinitialise shortly.',
      );
    } on DgpuRepositoryException catch (error) {
      emit(state.copyWith(isApplying: false, errorMessage: error.message));
    }
  }

  Future<void> _reloadState(
    Emitter<DgpuState> emit, {
    required bool showLoading,
    String? noticeMessage,
  }) async {
    if (_refreshInFlight) return;
    _refreshInFlight = true;

    if (showLoading) {
      emit(state.copyWith(isLoading: true, errorMessage: null));
    }
    try {
      final snapshot = await _repository.loadSnapshot();
      emit(
        state.copyWith(
          isActive: snapshot.isActive,
          processes: snapshot.processes,
          pciAddress: snapshot.pciAddress,
          isLoading: false,
          isApplying: false,
          noticeMessage: noticeMessage,
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          isLoading: false,
          isApplying: false,
          errorMessage: 'Failed to load GPU status: $error',
        ),
      );
    } finally {
      _refreshInFlight = false;
    }
  }

  @override
  Future<void> close() {
    _pollTimer?.cancel();
    return super.close();
  }
}
