import 'dart:async';

import 'package:riverbloc/riverbloc.dart';

import '../../../core/models/app_failure.dart';
import '../repository/lighting_repository.dart';
import 'lighting_event.dart';
import 'lighting_state.dart';

class LightingBloc extends Bloc<LightingEvent, LightingState> {
  LightingBloc({
    required LightingRepository repository,
    Duration pollInterval = const Duration(seconds: 5),
  }) : _repository = repository,
       _pollInterval = pollInterval,
       super(LightingState.initial()) {
    on<LightingEvent>(
      (event, emit) async {
        if (_closing) return;
        switch (event) {
          case LightingStarted():
            await _onStarted(event, emit);
          case LightingRefreshRequested():
            await _onRefreshRequested(event, emit);
          case LightingTicked():
            try {
              await _onTicked(event, emit);
            } finally {
              _tickPending = false;
            }
          case WhiteKeyboardBacklightSetRequested():
            await _onWhiteKeyboardBacklightSetRequested(event, emit);
          case YLogoLightSetRequested():
            await _onYLogoLightSetRequested(event, emit);
          case IoPortLightSetRequested():
            await _onIoPortLightSetRequested(event, emit);
        }
      },
      // One queue orders polling, writes, and each write's readback.
      transformer: (events, mapper) => events.asyncExpand(mapper),
    );
  }

  final LightingRepository _repository;
  final Duration _pollInterval;

  Timer? _pollTimer;
  bool _started = false;
  bool _closing = false;
  bool _tickPending = false;

  @override
  void add(LightingEvent event) {
    // Reject busy writes at arrival, before they can wait in the event queue.
    if (state.isApplying &&
        switch (event) {
          LightingStarted() ||
          LightingRefreshRequested() ||
          LightingTicked() => false,
          _ => true,
        }) {
      return;
    }
    super.add(event);
  }

  Future<void> _onStarted(
    LightingStarted event,
    Emitter<LightingState> emit,
  ) async {
    if (_started) return;
    _started = true;
    await _reloadState(emit, showLoading: true);
    if (_closing || emit.isDone) return;
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      if (_closing || _tickPending || state.isApplying) return;
      _tickPending = true;
      add(const LightingTicked());
    });
  }

  Future<void> _onTicked(
    LightingTicked event,
    Emitter<LightingState> emit,
  ) async {
    if (state.isApplying) return;
    await _reloadState(emit, showLoading: false);
  }

  Future<void> _onWhiteKeyboardBacklightSetRequested(
    WhiteKeyboardBacklightSetRequested event,
    Emitter<LightingState> emit,
  ) async {
    if (state.isApplying ||
        !state.whiteKeyboardBacklightSupported ||
        !state.whiteKeyboardBacklightWriteSupported) {
      return;
    }

    emit(
      state.copyWith(isApplying: true, errorMessage: null, noticeMessage: null),
    );

    try {
      await _repository.setWhiteKeyboardBacklight(event.enabled);
      final loaded = await _reloadState(emit, showLoading: false);
      if (_closing || emit.isDone) return;
      if (!loaded) {
        emit(state.copyWith(isApplying: false));
        return;
      }
      emit(
        state.copyWith(
          isApplying: false,
          noticeMessage:
              'White keyboard backlight ${event.enabled ? 'enabled' : 'disabled'}.',
        ),
      );
    } catch (error) {
      if (_closing || emit.isDone) return;
      emit(state.copyWith(isApplying: false, errorMessage: error));
    }
  }

  Future<void> _onYLogoLightSetRequested(
    YLogoLightSetRequested event,
    Emitter<LightingState> emit,
  ) async {
    if (state.isApplying || !state.yLogoLightSupported) {
      return;
    }

    emit(
      state.copyWith(isApplying: true, errorMessage: null, noticeMessage: null),
    );

    try {
      await _repository.setYLogoLight(event.enabled);
      final loaded = await _reloadState(emit, showLoading: false);
      if (_closing || emit.isDone) return;
      if (!loaded) {
        emit(state.copyWith(isApplying: false));
        return;
      }
      emit(
        state.copyWith(
          isApplying: false,
          noticeMessage:
              'Y-logo light ${event.enabled ? 'enabled' : 'disabled'}.',
        ),
      );
    } catch (error) {
      if (_closing || emit.isDone) return;
      emit(state.copyWith(isApplying: false, errorMessage: error));
    }
  }

  Future<void> _onIoPortLightSetRequested(
    IoPortLightSetRequested event,
    Emitter<LightingState> emit,
  ) async {
    if (state.isApplying || !state.ioPortLightSupported) {
      return;
    }

    emit(
      state.copyWith(isApplying: true, errorMessage: null, noticeMessage: null),
    );

    try {
      await _repository.setIoPortLight(event.enabled);
      final loaded = await _reloadState(emit, showLoading: false);
      if (_closing || emit.isDone) return;
      if (!loaded) {
        emit(state.copyWith(isApplying: false));
        return;
      }
      emit(
        state.copyWith(
          isApplying: false,
          noticeMessage:
              'IO-port light ${event.enabled ? 'enabled' : 'disabled'}.',
        ),
      );
    } catch (error) {
      if (_closing || emit.isDone) return;
      emit(state.copyWith(isApplying: false, errorMessage: error));
    }
  }

  Future<void> _onRefreshRequested(
    LightingRefreshRequested event,
    Emitter<LightingState> emit,
  ) async {
    await _reloadState(emit, showLoading: true);
  }

  Future<bool> _reloadState(
    Emitter<LightingState> emit, {
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
          whiteKeyboardBacklightEnabled: snapshot.whiteKeyboardBacklightEnabled,
          whiteKeyboardBacklightSupported:
              snapshot.whiteKeyboardBacklightSupported,
          whiteKeyboardBacklightWriteSupported:
              snapshot.whiteKeyboardBacklightWriteSupported,
          yLogoLightEnabled: snapshot.yLogoLightEnabled,
          yLogoLightSupported: snapshot.yLogoLightSupported,
          ioPortLightEnabled: snapshot.ioPortLightEnabled,
          ioPortLightSupported: snapshot.ioPortLightSupported,
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
            message: 'Failed to load lighting settings: $error',
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
