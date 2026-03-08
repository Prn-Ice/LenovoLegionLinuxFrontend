import 'package:riverbloc/riverbloc.dart';

import '../repository/dgpu_repository.dart';
import 'dgpu_event.dart';
import 'dgpu_state.dart';

class DgpuBloc extends Bloc<DgpuEvent, DgpuState> {
  DgpuBloc({required DgpuRepository repository})
    : _repository = repository,
      super(DgpuState.initial()) {
    on<DgpuStarted>(_onStarted);
    on<DgpuRefreshRequested>(_onRefreshRequested);
    on<DgpuKillProcessesRequested>(_onKillProcessesRequested);
    on<DgpuRestartPciRequested>(_onRestartPciRequested);
  }

  final DgpuRepository _repository;

  Future<void> _onStarted(
    DgpuStarted event,
    Emitter<DgpuState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, errorMessage: null));
    await _reloadState(emit);
  }

  Future<void> _onRefreshRequested(
    DgpuRefreshRequested event,
    Emitter<DgpuState> emit,
  ) async {
    await _reloadState(emit);
  }

  Future<void> _onKillProcessesRequested(
    DgpuKillProcessesRequested event,
    Emitter<DgpuState> emit,
  ) async {
    if (state.isApplying) return;
    emit(state.copyWith(isApplying: true, errorMessage: null, noticeMessage: null));
    try {
      await _repository.killGpuProcesses();
      await _reloadState(emit, noticeMessage: 'GPU processes killed.');
    } on DgpuRepositoryException catch (error) {
      emit(state.copyWith(isApplying: false, errorMessage: error.message));
    }
  }

  Future<void> _onRestartPciRequested(
    DgpuRestartPciRequested event,
    Emitter<DgpuState> emit,
  ) async {
    if (state.isApplying) return;
    emit(state.copyWith(isApplying: true, errorMessage: null, noticeMessage: null));
    try {
      await _repository.restartPciDevice();
      await _reloadState(
        emit,
        noticeMessage: 'PCI device restarted. The GPU will reinitialise shortly.',
      );
    } on DgpuRepositoryException catch (error) {
      emit(state.copyWith(isApplying: false, errorMessage: error.message));
    }
  }

  Future<void> _reloadState(
    Emitter<DgpuState> emit, {
    String? noticeMessage,
  }) async {
    try {
      final snapshot = await _repository.loadSnapshot();
      emit(state.copyWith(
        isActive: snapshot.isActive,
        processes: snapshot.processes,
        pciAddress: snapshot.pciAddress,
        isLoading: false,
        isApplying: false,
        noticeMessage: noticeMessage,
      ));
    } catch (error) {
      emit(state.copyWith(
        isLoading: false,
        isApplying: false,
        errorMessage: 'Failed to load GPU status: $error',
      ));
    }
  }
}
