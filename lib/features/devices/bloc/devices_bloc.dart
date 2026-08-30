import 'dart:async';

import 'package:riverbloc/riverbloc.dart';

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
    on<DevicesStarted>(_onStarted);
    on<DevicesRefreshRequested>(_onRefreshRequested);
    on<DevicesTicked>(_onTicked);
    on<TouchpadSetRequested>(_onTouchpadSetRequested);
    on<WinKeySetRequested>(_onWinKeySetRequested);
    on<FnLockSetRequested>(_onFnLockSetRequested);
    on<CameraSetRequested>(_onCameraSetRequested);
  }

  final DevicesRepository _repository;
  final Duration _pollInterval;

  Timer? _pollTimer;
  bool _started = false;
  bool _refreshInFlight = false;

  Future<void> _onStarted(
    DevicesStarted event,
    Emitter<DevicesState> emit,
  ) async {
    if (_started) return;
    _started = true;
    await _reloadState(emit, showLoading: true);
    _pollTimer = Timer.periodic(_pollInterval, (_) {
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
      await _reloadState(emit, showLoading: false);
      emit(state.copyWith(isApplying: false, noticeMessage: successMessage));
    } catch (error) {
      emit(state.copyWith(isApplying: false, errorMessage: '$error'));
    }
  }

  Future<void> _reloadState(
    Emitter<DevicesState> emit, {
    required bool showLoading,
  }) async {
    if (_refreshInFlight) return;
    _refreshInFlight = true;

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
          isLoading: false,
          errorMessage: null,
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          isLoading: false,
          errorMessage: 'Failed to load device settings: $error',
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
