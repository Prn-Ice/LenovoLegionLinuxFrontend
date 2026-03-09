import 'dart:async';

import 'package:riverbloc/riverbloc.dart';

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
    on<LightingStarted>(_onStarted);
    on<LightingTicked>(_onTicked);
    on<WhiteKeyboardBacklightSetRequested>(
      _onWhiteKeyboardBacklightSetRequested,
    );
    on<YLogoLightSetRequested>(_onYLogoLightSetRequested);
    on<IoPortLightSetRequested>(_onIoPortLightSetRequested);
  }

  final LightingRepository _repository;
  final Duration _pollInterval;

  Timer? _pollTimer;
  bool _started = false;
  bool _refreshInFlight = false;

  Future<void> _onStarted(
    LightingStarted event,
    Emitter<LightingState> emit,
  ) async {
    if (_started) return;
    _started = true;
    await _reloadState(emit, showLoading: true);
    _pollTimer = Timer.periodic(_pollInterval, (_) {
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
    if (state.isApplying || !state.whiteKeyboardBacklightSupported) {
      return;
    }

    emit(
      state.copyWith(isApplying: true, errorMessage: null, noticeMessage: null),
    );

    try {
      await _repository.setWhiteKeyboardBacklight(event.enabled);
      await _reloadState(emit, showLoading: false);
      emit(
        state.copyWith(
          isApplying: false,
          noticeMessage:
              'White keyboard backlight ${event.enabled ? 'enabled' : 'disabled'}.',
        ),
      );
    } catch (error) {
      emit(state.copyWith(isApplying: false, errorMessage: '$error'));
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
      await _reloadState(emit, showLoading: false);
      emit(
        state.copyWith(
          isApplying: false,
          noticeMessage:
              'Y-logo light ${event.enabled ? 'enabled' : 'disabled'}.',
        ),
      );
    } catch (error) {
      emit(state.copyWith(isApplying: false, errorMessage: '$error'));
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
      await _reloadState(emit, showLoading: false);
      emit(
        state.copyWith(
          isApplying: false,
          noticeMessage:
              'IO-port light ${event.enabled ? 'enabled' : 'disabled'}.',
        ),
      );
    } catch (error) {
      emit(state.copyWith(isApplying: false, errorMessage: '$error'));
    }
  }

  Future<void> _reloadState(
    Emitter<LightingState> emit, {
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
          whiteKeyboardBacklightEnabled: snapshot.whiteKeyboardBacklightEnabled,
          whiteKeyboardBacklightSupported:
              snapshot.whiteKeyboardBacklightSupported,
          yLogoLightEnabled: snapshot.yLogoLightEnabled,
          yLogoLightSupported: snapshot.yLogoLightSupported,
          ioPortLightEnabled: snapshot.ioPortLightEnabled,
          ioPortLightSupported: snapshot.ioPortLightSupported,
          isLoading: false,
          errorMessage: null,
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          isLoading: false,
          errorMessage: 'Failed to load lighting settings: $error',
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
