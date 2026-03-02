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
