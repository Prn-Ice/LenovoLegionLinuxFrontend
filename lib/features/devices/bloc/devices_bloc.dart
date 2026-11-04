import 'dart:async';

import 'package:riverbloc/riverbloc.dart';

import '../../../core/models/app_failure.dart';
import '../repository/devices_repository.dart';
import 'devices_event.dart';
import 'devices_state.dart';

class DevicesBloc extends Bloc<DevicesEvent, DevicesState> {
  DevicesBloc({
    required DevicesRepository repository,
    Duration pollInterval = const Duration(seconds: 5),
  }) : _repository = repository,
       _pollInterval = pollInterval,
       super(DevicesState.initial()) {
    on<DevicesEvent>(
      (event, emit) async {
        if (_closing) return;
        switch (event) {
          case DevicesStarted():
            await _onStarted(event, emit);
          case DevicesRefreshRequested():
            await _onRefreshRequested(event, emit);
          case DevicesTicked():
            try {
              await _onTicked(event, emit);
            } finally {
              _tickPending = false;
            }
          case TouchpadSetRequested():
            await _onTouchpadSetRequested(event, emit);
          case WinKeySetRequested():
            await _onWinKeySetRequested(event, emit);
          case FnLockSetRequested():
            await _onFnLockSetRequested(event, emit);
          case CameraSetRequested():
            await _onCameraSetRequested(event, emit);
        }
      },
      // One queue orders polling, writes, and each write's readback.
      transformer: (events, mapper) => events.asyncExpand(mapper),
    );
  }

  final DevicesRepository _repository;
  final Duration _pollInterval;

  Timer? _pollTimer;
  bool _started = false;
  bool _closing = false;
  bool _tickPending = false;

  @override
  void add(DevicesEvent event) {
    // Reject busy writes at arrival, before they can wait in the event queue.
    if (state.isApplying &&
        switch (event) {
          DevicesStarted() ||
          DevicesRefreshRequested() ||
          DevicesTicked() => false,
          _ => true,
        }) {
      return;
    }
    super.add(event);
  }

  Future<void> _onStarted(
    DevicesStarted event,
    Emitter<DevicesState> emit,
  ) async {
    if (_started) return;
    _started = true;
    await _reloadState(emit, showLoading: true);
    if (_closing || emit.isDone) return;
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      if (_closing || _tickPending || state.isApplying) return;
      _tickPending = true;
      add(const DevicesTicked());
    });
  }

  Future<void> _onRefreshRequested(
    DevicesRefreshRequested event,
    Emitter<DevicesState> emit,
  ) async {
    await _reloadState(emit, showLoading: true);
  }

  Future<void> _onTicked(
    DevicesTicked event,
    Emitter<DevicesState> emit,
  ) async {
    if (state.isApplying) return;
    await _reloadState(emit, showLoading: false);
  }

  Future<void> _onTouchpadSetRequested(
    TouchpadSetRequested event,
    Emitter<DevicesState> emit,
  ) async {
    await _apply(
      emit,
      action: () => _repository.setTouchpad(event.enabled),
      successMessage: 'Touchpad ${event.enabled ? 'enabled' : 'disabled'}.',
    );
  }

  Future<void> _onWinKeySetRequested(
    WinKeySetRequested event,
    Emitter<DevicesState> emit,
  ) async {
    await _apply(
      emit,
      action: () => _repository.setWinKey(event.enabled),
      successMessage: 'Win key ${event.enabled ? 'enabled' : 'disabled'}.',
    );
  }

  Future<void> _onFnLockSetRequested(
    FnLockSetRequested event,
    Emitter<DevicesState> emit,
  ) async {
    await _apply(
      emit,
      action: () => _repository.setFnLock(event.enabled),
      successMessage: 'Fn lock ${event.enabled ? 'enabled' : 'disabled'}.',
    );
  }

  Future<void> _onCameraSetRequested(
    CameraSetRequested event,
    Emitter<DevicesState> emit,
  ) async {
    if (state.isApplying ||
        !state.cameraSupported ||
        !state.cameraWriteSupported) {
      return;
    }
    await _apply(
      emit,
      action: () => _repository.setCamera(event.enabled),
      successMessage: 'Camera ${event.enabled ? 'enabled' : 'disabled'}.',
    );
  }

  Future<void> _apply(
    Emitter<DevicesState> emit, {
    required Future<void> Function() action,
    required String successMessage,
  }) async {
    if (state.isApplying) return;

    emit(
      state.copyWith(isApplying: true, errorMessage: null, noticeMessage: null),
    );

    try {
      await action();
      final loaded = await _reloadState(emit, showLoading: false);
      if (_closing || emit.isDone) return;
      if (!loaded) {
        emit(state.copyWith(isApplying: false));
        return;
      }
      emit(state.copyWith(isApplying: false, noticeMessage: successMessage));
    } catch (error) {
      if (_closing || emit.isDone) return;
      emit(state.copyWith(isApplying: false, errorMessage: error));
    }
  }

  Future<bool> _reloadState(
    Emitter<DevicesState> emit, {
    required bool showLoading,
  }) async {
    if (_closing || emit.isDone) return false;

    if (showLoading) {
      emit(
        state.copyWith(
          isLoading: true,
          errorMessage: null,
          noticeMessage: null,
        ),
      );
    }

    try {
      final snapshot = await _repository.loadSnapshot();
      if (_closing || emit.isDone) return false;
      emit(
        state.copyWith(
          touchpadEnabled: snapshot.touchpadEnabled,
          touchpadSupported: snapshot.touchpadSupported,
          winKeyEnabled: snapshot.winKeyEnabled,
          winKeySupported: snapshot.winKeySupported,
          fnLockEnabled: snapshot.fnLockEnabled,
          fnLockSupported: snapshot.fnLockSupported,
          cameraEnabled: snapshot.cameraEnabled,
          cameraSupported: snapshot.cameraSupported,
          cameraWriteSupported: snapshot.cameraWriteSupported,
          isLoading: false,
          errorMessage: null,
        ),
      );
      return true;
    } catch (error) {
      if (_closing || emit.isDone) return false;
      emit(
        state.copyWith(
          isLoading: false,
          errorMessage: AppFailure.from(
            error,
            message: 'Failed to load device settings: $error',
          ),
        ),
      );
      return false;
    }
  }

  @override
  Future<void> close() {
    _closing = true;
    _pollTimer?.cancel();
    return super.close();
  }
}
