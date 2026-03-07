import 'package:riverbloc/riverbloc.dart';

import '../repository/display_lighting_repository.dart';
import 'display_lighting_event.dart';
import 'display_lighting_state.dart';

class DisplayLightingBloc
    extends Bloc<DisplayLightingEvent, DisplayLightingState> {
  DisplayLightingBloc({required DisplayLightingRepository repository})
    : _repository = repository,
      super(DisplayLightingState.initial()) {
    on<DisplayLightingStarted>(_onStarted);
    on<DisplayLightingRefreshRequested>(_onRefreshRequested);
    on<HybridModeSetRequested>(_onHybridModeSetRequested);
    on<OverdriveModeSetRequested>(_onOverdriveModeSetRequested);
    on<WhiteKeyboardBacklightSetRequested>(
      _onWhiteKeyboardBacklightSetRequested,
    );
    on<YLogoLightSetRequested>(_onYLogoLightSetRequested);
    on<IoPortLightSetRequested>(_onIoPortLightSetRequested);
    on<RefreshRateSetRequested>(_onRefreshRateSetRequested);
  }

  final DisplayLightingRepository _repository;

  Future<void> _onStarted(
    DisplayLightingStarted event,
    Emitter<DisplayLightingState> emit,
  ) async {
    await _reloadState(emit, showLoading: true);
  }

  Future<void> _onRefreshRequested(
    DisplayLightingRefreshRequested event,
    Emitter<DisplayLightingState> emit,
  ) async {
    await _reloadState(emit, showLoading: true);
  }

  Future<void> _onHybridModeSetRequested(
    HybridModeSetRequested event,
    Emitter<DisplayLightingState> emit,
  ) async {
    if (state.isApplying || !state.hybridModeSupported) {
      return;
    }

    emit(
      state.copyWith(isApplying: true, errorMessage: null, noticeMessage: null),
    );

    try {
      await _repository.setHybridMode(event.enabled);
      await _reloadState(emit, showLoading: false);
      emit(
        state.copyWith(
          isApplying: false,
          noticeMessage:
              'Hybrid mode updated. Reboot is required for full effect.',
        ),
      );
    } catch (error) {
      emit(state.copyWith(isApplying: false, errorMessage: '$error'));
    }
  }

  Future<void> _onOverdriveModeSetRequested(
    OverdriveModeSetRequested event,
    Emitter<DisplayLightingState> emit,
  ) async {
    if (state.isApplying || !state.overdriveSupported) {
      return;
    }

    emit(
      state.copyWith(isApplying: true, errorMessage: null, noticeMessage: null),
    );

    try {
      await _repository.setOverdriveMode(event.enabled);
      await _reloadState(emit, showLoading: false);
      emit(
        state.copyWith(isApplying: false, noticeMessage: 'Overdrive updated.'),
      );
    } catch (error) {
      emit(state.copyWith(isApplying: false, errorMessage: '$error'));
    }
  }

  Future<void> _onWhiteKeyboardBacklightSetRequested(
    WhiteKeyboardBacklightSetRequested event,
    Emitter<DisplayLightingState> emit,
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
    Emitter<DisplayLightingState> emit,
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
    Emitter<DisplayLightingState> emit,
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

  Future<void> _onRefreshRateSetRequested(
    RefreshRateSetRequested event,
    Emitter<DisplayLightingState> emit,
  ) async {
    final outputName = state.xrandrOutputName;
    if (state.isApplying || outputName == null) {
      return;
    }

    emit(
      state.copyWith(isApplying: true, errorMessage: null, noticeMessage: null),
    );

    try {
      await _repository.setRefreshRate(outputName, event.rate);
      await _reloadState(emit, showLoading: false);
      emit(
        state.copyWith(
          isApplying: false,
          noticeMessage: 'Refresh rate set to ${event.rate.round()} Hz.',
        ),
      );
    } catch (error) {
      emit(state.copyWith(isApplying: false, errorMessage: '$error'));
    }
  }

  Future<void> _reloadState(
    Emitter<DisplayLightingState> emit, {
    required bool showLoading,
  }) async {
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
          hybridModeEnabled: snapshot.hybridModeEnabled,
          hybridModeSupported: snapshot.hybridModeSupported,
          overdriveEnabled: snapshot.overdriveEnabled,
          overdriveSupported: snapshot.overdriveSupported,
          whiteKeyboardBacklightEnabled: snapshot.whiteKeyboardBacklightEnabled,
          whiteKeyboardBacklightSupported:
              snapshot.whiteKeyboardBacklightSupported,
          yLogoLightEnabled: snapshot.yLogoLightEnabled,
          yLogoLightSupported: snapshot.yLogoLightSupported,
          ioPortLightEnabled: snapshot.ioPortLightEnabled,
          ioPortLightSupported: snapshot.ioPortLightSupported,
          xrandrOutputName: snapshot.xrandrOutputName,
          availableRefreshRates: snapshot.availableRefreshRates,
          currentRefreshRate: snapshot.currentRefreshRate,
          isLoading: false,
          errorMessage: null,
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          isLoading: false,
          errorMessage: 'Failed to load display settings: $error',
        ),
      );
    }
  }
}
