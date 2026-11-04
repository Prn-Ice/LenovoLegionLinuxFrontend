import 'dart:async';

import 'package:riverbloc/riverbloc.dart';

import '../../../core/models/app_failure.dart';
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
    on<DisplayEvent>(
      (event, emit) async {
        if (_closing) return;
        switch (event) {
          case DisplayStarted():
            await _onStarted(event, emit);
          case DisplayRefreshRequested():
            await _onRefreshRequested(event, emit);
          case DisplayTicked():
            try {
              await _onTicked(event, emit);
            } finally {
              _tickPending = false;
            }
          case OverdriveModeSetRequested():
            await _onOverdriveModeSetRequested(event, emit);
          case RefreshRateSetRequested():
            await _onRefreshRateSetRequested(event, emit);
        }
      },
      // One queue orders polling, writes, and each write's readback.
      transformer: (events, mapper) => events.asyncExpand(mapper),
    );
  }

  final DisplayRepository _repository;
  final Duration _pollInterval;

  Timer? _pollTimer;
  bool _started = false;
  bool _closing = false;
  bool _tickPending = false;

  @override
  void add(DisplayEvent event) {
    // Reject busy writes at arrival, before they can wait in the event queue.
    if (state.isApplying &&
        switch (event) {
          DisplayStarted() ||
          DisplayRefreshRequested() ||
          DisplayTicked() => false,
          _ => true,
        }) {
      return;
    }
    super.add(event);
  }

  Future<void> _onStarted(
    DisplayStarted event,
    Emitter<DisplayState> emit,
  ) async {
    if (_started) return;
    _started = true;
    await _reloadState(emit, showLoading: true);
    if (_closing || emit.isDone) return;
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      if (_closing || _tickPending || state.isApplying) return;
      _tickPending = true;
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
      final loaded = await _reloadState(emit, showLoading: false);
      if (_closing || emit.isDone) return;
      if (!loaded) {
        emit(state.copyWith(isApplying: false));
        return;
      }
      emit(
        state.copyWith(isApplying: false, noticeMessage: 'Overdrive updated.'),
      );
    } catch (error) {
      if (_closing || emit.isDone) return;
      emit(state.copyWith(isApplying: false, errorMessage: error));
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
      final loaded = await _reloadState(emit, showLoading: false);
      if (_closing || emit.isDone) return;
      if (!loaded) {
        emit(state.copyWith(isApplying: false));
        return;
      }
      emit(
        state.copyWith(
          isApplying: false,
          noticeMessage: 'Refresh rate set to ${event.rate.round()} Hz.',
        ),
      );
    } catch (error) {
      if (_closing || emit.isDone) return;
      emit(state.copyWith(isApplying: false, errorMessage: error));
    }
  }

  Future<bool> _reloadState(
    Emitter<DisplayState> emit, {
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
          overdriveEnabled: snapshot.overdriveEnabled,
          overdriveSupported: snapshot.overdriveSupported,
          xrandrOutputName: snapshot.xrandrOutputName,
          availableRefreshRates: snapshot.availableRefreshRates,
          currentRefreshRate: snapshot.currentRefreshRate,
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
            message: 'Failed to load display settings: $error',
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
