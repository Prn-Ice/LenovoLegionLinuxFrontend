import 'dart:async';

import 'package:riverbloc/riverbloc.dart';

import '../models/graphics_mode.dart';
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
    on<DgpuGraphicsModeSetRequested>(_onGraphicsModeSetRequested);
    on<DgpuKillProcessesRequested>(_onKillProcessesRequested);
    on<DgpuRestartPciRequested>(_onRestartPciRequested);
  }

  final DgpuRepository _repository;
  final Duration _pollInterval;

  Timer? _pollTimer;
  bool _started = false;
  bool _refreshInFlight = false;
  Completer<void>? _refreshCompleter;

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

  Future<void> _onGraphicsModeSetRequested(
    DgpuGraphicsModeSetRequested event,
    Emitter<DgpuState> emit,
  ) async {
    if (state.isApplying || event.mode == GraphicsMode.hybridAuto) return;
    emit(
      state.copyWith(
        isApplying: true,
        applyingGraphicsMode: event.mode,
        errorMessage: null,
        noticeMessage: null,
      ),
    );

    String? actionErrorMessage;
    try {
      await _repository.setGraphicsMode(event.mode);
    } on DgpuRepositoryException catch (error) {
      actionErrorMessage = error.message;
    }
    await _reloadState(
      emit,
      showLoading: false,
      actionErrorMessage: actionErrorMessage,
      requireGraphicsModeStatus: true,
      force: true,
    );
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
      await _repository.killGpuProcesses(event.expectedPids);
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
      await _repository.restartPciDevice(event.expectedPciAddress);
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
    String? actionErrorMessage,
    bool requireGraphicsModeStatus = false,
    bool force = false,
  }) async {
    if (_refreshInFlight) {
      await _refreshCompleter?.future;
      if (!force) return;
    }
    _refreshInFlight = true;
    _refreshCompleter = Completer<void>();

    if (showLoading) {
      emit(state.copyWith(isLoading: true, errorMessage: null));
    }
    try {
      final snapshot = requireGraphicsModeStatus
          ? await _repository.loadSnapshotAfterGraphicsWrite()
          : await _repository.loadSnapshot();
      emit(
        state.copyWith(
          isActive: snapshot.isActive,
          processes: snapshot.processes,
          pciAddress: snapshot.pciAddress,
          isLoading: false,
          isApplying: false,
          applyingGraphicsMode: null,
          hasLoaded: true,
          errorMessage: actionErrorMessage,
          noticeMessage: noticeMessage,
          graphicsModeStatus: snapshot.graphicsModeStatus,
          name: snapshot.name,
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          isLoading: false,
          isApplying: false,
          applyingGraphicsMode: null,
          hasLoaded: true,
          errorMessage: actionErrorMessage == null
              ? 'Failed to load GPU status: $error'
              : '$actionErrorMessage\n\nAuthoritative graphics status also '
                    'could not be reloaded: $error',
        ),
      );
    } finally {
      _refreshInFlight = false;
      _refreshCompleter?.complete();
      _refreshCompleter = null;
    }
  }

  @override
  Future<void> close() {
    _pollTimer?.cancel();
    return super.close();
  }
}
