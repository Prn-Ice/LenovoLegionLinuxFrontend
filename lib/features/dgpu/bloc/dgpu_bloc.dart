import 'dart:async';

import 'package:riverbloc/riverbloc.dart';

import '../../../core/models/app_failure.dart';
import '../../../core/models/gpu_process_scan.dart';
import '../models/graphics_mode.dart';
import '../repository/dgpu_repository.dart';
import 'dgpu_event.dart';
import 'dgpu_state.dart';

class DgpuBloc extends Bloc<DgpuEvent, DgpuState> {
  DgpuBloc({
    required this._repository,
    this._pollInterval = const Duration(seconds: 5),
  }) : super(DgpuState.initial()) {
    on<DgpuStarted>(_onStarted);
    on<DgpuRefreshRequested>(_onRefreshRequested);
    on<DgpuTicked>(_onTicked);
    on<DgpuDeviceDetailsRequested>(_onDeviceDetailsRequested);
    on<DgpuGraphicsModeSetRequested>(_onGraphicsModeSetRequested);
    on<DgpuGraphicsBootSupportSetRequested>(_onGraphicsBootSupportSetRequested);
    on<DgpuKillProcessesRequested>(_onKillProcessesRequested);
    on<DgpuRestartPciRequested>(_onRestartPciRequested);
  }

  final DgpuRepository _repository;
  final Duration _pollInterval;

  Timer? _pollTimer;
  bool _started = false;
  bool _refreshInFlight = false;
  Completer<void>? _refreshCompleter;
  bool _deviceDetailsInFlight = false;
  int _pciRevision = 0;

  Future<void> _onStarted(DgpuStarted event, Emitter<DgpuState> emit) async {
    if (_started) return;
    _started = true;
    await _reloadState(emit, showLoading: true);
    if (isClosed || emit.isDone) return;
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

  Future<void> _onDeviceDetailsRequested(
    DgpuDeviceDetailsRequested event,
    Emitter<DgpuState> emit,
  ) async {
    final address = state.pciAddress;
    if (address == null || _deviceDetailsInFlight) return;

    final revision = _pciRevision;
    _deviceDetailsInFlight = true;
    try {
      await Future.wait([
        _loadProcessScan(address, revision, emit),
        if (state.name == null) _loadDeviceName(address, revision, emit),
      ]);
    } finally {
      _deviceDetailsInFlight = false;
    }
    if (revision != _pciRevision && !isClosed && !emit.isDone) {
      add(const DgpuDeviceDetailsRequested());
    }
  }

  Future<void> _loadProcessScan(
    String address,
    int revision,
    Emitter<DgpuState> emit,
  ) async {
    GpuProcessScan? scan;
    try {
      scan = await _repository.loadProcessScan(address);
    } on Exception {
      scan = null;
    }
    if (!isClosed && !emit.isDone && revision == _pciRevision) {
      emit(state.copyWith(processScan: scan, isLoadingProcesses: false));
    }
  }

  Future<void> _loadDeviceName(
    String address,
    int revision,
    Emitter<DgpuState> emit,
  ) async {
    String? name;
    try {
      name = await _repository.loadDeviceName(address);
    } on Exception {
      name = null;
    }
    if (!isClosed && !emit.isDone && revision == _pciRevision) {
      emit(state.copyWith(name: name));
    }
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

    AppFailure? actionErrorMessage;
    try {
      await _repository.setGraphicsMode(event.mode);
    } on DgpuRepositoryException catch (error) {
      actionErrorMessage = error;
    }
    await _reloadState(
      emit,
      showLoading: false,
      actionErrorMessage: actionErrorMessage,
      requireGraphicsModeStatus: true,
      force: true,
    );
  }

  Future<void> _onGraphicsBootSupportSetRequested(
    DgpuGraphicsBootSupportSetRequested event,
    Emitter<DgpuState> emit,
  ) async {
    if (state.isApplying) return;
    emit(state.copyWith(isApplying: true, errorMessage: null));
    AppFailure? failure;
    try {
      await _repository.setGraphicsBootSupport(event.enabled);
    } on DgpuRepositoryException catch (error) {
      failure = error;
    }
    await _reloadState(
      emit,
      showLoading: false,
      actionErrorMessage: failure,
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
      emit(state.copyWith(isApplying: false, errorMessage: error));
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
      emit(state.copyWith(isApplying: false, errorMessage: error));
    }
  }

  Future<void> _reloadState(
    Emitter<DgpuState> emit, {
    required bool showLoading,
    String? noticeMessage,
    AppFailure? actionErrorMessage,
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
      await Future.wait([
        _reloadDevice(emit),
        _reloadGraphicsMode(emit, afterWrite: requireGraphicsModeStatus),
      ]);
      if (isClosed || emit.isDone) return;
      emit(
        state.copyWith(
          isLoading: false,
          isApplying: false,
          applyingGraphicsMode: null,
          errorMessage: actionErrorMessage,
          noticeMessage: noticeMessage,
        ),
      );
    } catch (error) {
      if (isClosed || emit.isDone) return;
      emit(
        state.copyWith(
          isLoading: false,
          isApplying: false,
          applyingGraphicsMode: null,
          hasCheckedPci: true,
          hasLoadedGraphicsMode: true,
          errorMessage: AppFailure.from(
            actionErrorMessage ?? error,
            message: actionErrorMessage == null
                ? 'Failed to load GPU status: $error'
                : '$actionErrorMessage\n\nThe app also could not reload the '
                      'graphics mode and NVIDIA GPU status: $error',
          ),
        ),
      );
    } finally {
      _refreshInFlight = false;
      _refreshCompleter?.complete();
      _refreshCompleter = null;
    }
  }

  Future<void> _reloadDevice(Emitter<DgpuState> emit) async {
    final snapshot = await _repository.loadSnapshot();
    if (isClosed || emit.isDone) return;

    final deviceChanged = snapshot.pciAddress != state.pciAddress;
    if (deviceChanged) _pciRevision++;
    emit(
      state.copyWith(
        isActive: snapshot.isActive,
        pciAddress: snapshot.pciAddress,
        hasCheckedPci: true,
        name: deviceChanged ? null : state.name,
        processScan: deviceChanged ? null : state.processScan,
        isLoadingProcesses: deviceChanged
            ? snapshot.pciAddress != null
            : state.isLoadingProcesses,
      ),
    );
    if (snapshot.pciAddress != null) {
      add(const DgpuDeviceDetailsRequested());
    }
  }

  Future<void> _reloadGraphicsMode(
    Emitter<DgpuState> emit, {
    required bool afterWrite,
  }) async {
    final status = await _repository.loadGraphicsModeStatus(
      required: afterWrite,
    );
    if (isClosed || emit.isDone) return;
    emit(
      state.copyWith(graphicsModeStatus: status, hasLoadedGraphicsMode: true),
    );
  }

  @override
  Future<void> close() {
    _pollTimer?.cancel();
    return super.close();
  }
}
