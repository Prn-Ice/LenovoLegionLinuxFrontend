import 'dart:async';

import 'package:riverbloc/riverbloc.dart';

import '../repository/display_repository.dart';
import 'display_event.dart';
import 'display_state.dart';

class DisplayBloc extends Bloc<DisplayEvent, DisplayState> {
  DisplayBloc({
    required DisplayRepository repository,
    Duration pollInterval = const Duration(seconds: 5),
  }) : _repository = repository,
       _pollInterval = pollInterval,
       super(DisplayState.initial()) {
    on<DisplayStarted>(_onStarted);
    on<DisplayRefreshRequested>(_onRefreshRequested);
    on<DisplayTicked>(_onTicked);
    on<OverdriveModeSetRequested>(_onOverdriveModeSetRequested);
    on<RefreshRateSetRequested>(_onRefreshRateSetRequested);
  }

  final DisplayRepository _repository;
  final Duration _pollInterval;

  Timer? _pollTimer;
  bool _started = false;
  bool _refreshInFlight = false;

  Future<void> _onStarted(
    DisplayStarted event,
    Emitter<DisplayState> emit,
  ) async {
    if (_started) return;
    _started = true;
    await _reloadState(emit, showLoading: true);
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      add(const DisplayTicked());
    });
  }

  Future<void> _onRefreshRequested(
    DisplayRefreshRequested event,
    Emitter<DisplayState> emit,
  ) async {
    await _reloadState(emit, showLoading: true);
  }

  Future<void> _onTicked(
    DisplayTicked event,
    Emitter<DisplayState> emit,
  ) async {
    if (state.isApplying) return;
    await _reloadState(emit, showLoading: false);
  }

  Future<void> _onOverdriveModeSetRequested(
    OverdriveModeSetRequested event,
    Emitter<DisplayState> emit,
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

  Future<void> _onRefreshRateSetRequested(
    RefreshRateSetRequested event,
    Emitter<DisplayState> emit,
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
    Emitter<DisplayState> emit, {
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
          overdriveEnabled: snapshot.overdriveEnabled,
          overdriveSupported: snapshot.overdriveSupported,
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
