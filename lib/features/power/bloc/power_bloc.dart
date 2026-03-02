import 'package:riverbloc/riverbloc.dart';

import '../repository/power_repository.dart';
import 'power_event.dart';
import 'power_state.dart';

class PowerBloc extends Bloc<PowerEvent, PowerState> {
  PowerBloc({required PowerRepository repository})
    : _repository = repository,
      super(PowerState.initial()) {
    on<PowerStarted>(_onStarted);
    on<PowerRefreshRequested>(_onRefreshRequested);
    on<PowerModeSetRequested>(_onModeSetRequested);
    on<PowerLimitSetRequested>(_onLimitSetRequested);
  }

  final PowerRepository _repository;

  Future<void> _onStarted(PowerStarted event, Emitter<PowerState> emit) async {
    await _reloadState(emit, showLoading: true);
  }

  Future<void> _onRefreshRequested(
    PowerRefreshRequested event,
    Emitter<PowerState> emit,
  ) async {
    await _reloadState(emit, showLoading: true);
  }

  Future<void> _onModeSetRequested(
    PowerModeSetRequested event,
    Emitter<PowerState> emit,
  ) async {
    if (state.isApplying) {
      return;
    }

    emit(
      state.copyWith(isApplying: true, errorMessage: null, noticeMessage: null),
    );

    try {
      await _repository.setPowerMode(event.mode);
      await _reloadState(emit, showLoading: false);
      emit(
        state.copyWith(
          isApplying: false,
          noticeMessage: 'Power mode set to ${event.mode.label}.',
        ),
      );
    } catch (error) {
      emit(state.copyWith(isApplying: false, errorMessage: '$error'));
    }
  }

  Future<void> _onLimitSetRequested(
    PowerLimitSetRequested event,
    Emitter<PowerState> emit,
  ) async {
    if (state.isApplying) {
      return;
    }

    emit(
      state.copyWith(isApplying: true, errorMessage: null, noticeMessage: null),
    );

    try {
      await _repository.setPowerLimit(event.limit, event.value);
      await _reloadState(emit, showLoading: false);
      emit(
        state.copyWith(
          isApplying: false,
          noticeMessage: '${event.limit.label} set to ${event.value}.',
        ),
      );
    } catch (error) {
      emit(state.copyWith(isApplying: false, errorMessage: '$error'));
    }
  }

  Future<void> _reloadState(
    Emitter<PowerState> emit, {
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
          currentMode: snapshot.currentMode,
          availableModes: snapshot.availableModes,
          powerLimits: snapshot.powerLimits,
          isLoading: false,
          errorMessage: null,
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          isLoading: false,
          errorMessage: 'Failed to load power settings: $error',
        ),
      );
    }
  }
}
