import 'dart:async';

import 'package:riverbloc/riverbloc.dart';

import '../../../core/models/app_failure.dart';
import '../repository/fans_repository.dart';
import 'fans_event.dart';
import 'fans_state.dart';

class FansBloc extends Bloc<FansEvent, FansState> {
  FansBloc({
    required FansRepository repository,
    Duration pollInterval = const Duration(seconds: 5),
  }) : _repository = repository,
       _pollInterval = pollInterval,
       super(FansState.initial()) {
    on<FansEvent>(
      (event, emit) async {
        if (_closing) return;
        switch (event) {
          case FansStarted():
            await _onStarted(event, emit);
          case FansRefreshRequested():
            await _onRefreshRequested(event, emit);
          case FansTicked():
            try {
              await _onTicked(event, emit);
            } finally {
              _tickPending = false;
            }
          case FansPresetSelectionChanged():
            _onPresetSelectionChanged(event, emit);
          case FansApplyCurrentPresetRequested():
            await _onApplyCurrentPresetRequested(event, emit);
          case FansApplySelectedPresetRequested():
            await _onApplySelectedPresetRequested(event, emit);
          case MiniFanCurveSetRequested():
            await _onMiniFanCurveSetRequested(event, emit);
          case LockFanControllerSetRequested():
            await _onLockFanControllerSetRequested(event, emit);
          case MaximumFanSpeedSetRequested():
            await _onMaximumFanSpeedSetRequested(event, emit);
          case FanCurvePointUpdated():
            _onFanCurvePointUpdated(event, emit);
          case FanCurveSaveRequested():
            await _onFanCurveSaveRequested(event, emit);
        }
      },
      // One queue orders polling, writes, and each write's readback.
      transformer: (events, mapper) => events.asyncExpand(mapper),
    );
  }

  final FansRepository _repository;
  final Duration _pollInterval;

  Timer? _pollTimer;
  bool _started = false;
  bool _closing = false;
  bool _tickPending = false;

  @override
  void add(FansEvent event) {
    // Keep edits, but reject busy writes before they wait in the event queue.
    if (state.isApplying &&
        switch (event) {
          FansStarted() ||
          FansRefreshRequested() ||
          FansTicked() ||
          FansPresetSelectionChanged() ||
          FanCurvePointUpdated() => false,
          _ => true,
        }) {
      return;
    }
    super.add(event);
  }

  Future<void> _onStarted(FansStarted event, Emitter<FansState> emit) async {
    if (_started) return;
    _started = true;
    await _reloadState(emit, showLoading: true);
    if (_closing || emit.isDone) return;
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      if (_closing || _tickPending || state.isApplying) return;
      _tickPending = true;
      add(const FansTicked());
    });
  }

  Future<void> _onRefreshRequested(
    FansRefreshRequested event,
    Emitter<FansState> emit,
  ) async {
    await _reloadState(emit, showLoading: true);
  }

  Future<void> _onTicked(FansTicked event, Emitter<FansState> emit) async {
    if (state.isApplying) return;
    await _reloadState(emit, showLoading: false);
  }

  void _onPresetSelectionChanged(
    FansPresetSelectionChanged event,
    Emitter<FansState> emit,
  ) {
    emit(state.copyWith(selectedPreset: event.preset, errorMessage: null));
  }

  Future<void> _onApplyCurrentPresetRequested(
    FansApplyCurrentPresetRequested event,
    Emitter<FansState> emit,
  ) async {
    await _apply(
      emit,
      action: _repository.applyCurrentContextPreset,
      successMessage: 'Applied current-context fan preset.',
    );
  }

  Future<void> _onApplySelectedPresetRequested(
    FansApplySelectedPresetRequested event,
    Emitter<FansState> emit,
  ) async {
    final selected = state.selectedPreset;
    if (selected == null || selected.isEmpty) {
      emit(
        state.copyWith(
          errorMessage: 'Select a preset before applying.',
          noticeMessage: null,
        ),
      );
      return;
    }

    await _apply(
      emit,
      action: () => _repository.applyPreset(selected),
      successMessage: 'Applied fan preset "$selected".',
    );
  }

  Future<void> _onMiniFanCurveSetRequested(
    MiniFanCurveSetRequested event,
    Emitter<FansState> emit,
  ) async {
    await _apply(
      emit,
      action: () => _repository.setMiniFanCurve(event.enabled),
      successMessage:
          'Mini fan curve ${event.enabled ? 'enabled' : 'disabled'}.',
    );
  }

  Future<void> _onLockFanControllerSetRequested(
    LockFanControllerSetRequested event,
    Emitter<FansState> emit,
  ) async {
    await _apply(
      emit,
      action: () => _repository.setLockFanController(event.enabled),
      successMessage:
          'Lock fan controller ${event.enabled ? 'enabled' : 'disabled'}.',
    );
  }

  Future<void> _onMaximumFanSpeedSetRequested(
    MaximumFanSpeedSetRequested event,
    Emitter<FansState> emit,
  ) async {
    await _apply(
      emit,
      action: () => _repository.setMaximumFanSpeed(event.enabled),
      successMessage:
          'Maximum fan speed ${event.enabled ? 'enabled' : 'disabled'}.',
    );
  }

  void _onFanCurvePointUpdated(
    FanCurvePointUpdated event,
    Emitter<FansState> emit,
  ) {
    final current = state.fanCurve;
    if (current == null ||
        event.index < 0 ||
        event.index >= current.points.length) {
      return;
    }

    emit(
      state.copyWith(
        fanCurve: current.copyWithPoint(event.index, event.point),
        fanCurveDirty: true,
        errorMessage: null,
      ),
    );
  }

  Future<void> _onFanCurveSaveRequested(
    FanCurveSaveRequested event,
    Emitter<FansState> emit,
  ) async {
    final curve = state.fanCurve;
    if (curve == null || state.isApplying) {
      return;
    }

    emit(
      state.copyWith(isApplying: true, errorMessage: null, noticeMessage: null),
    );

    try {
      await _repository.writeFanCurveToHardware(curve);
      final loaded = await _reloadState(emit, showLoading: false);
      if (_closing || emit.isDone) return;
      if (!loaded) {
        emit(state.copyWith(isApplying: false));
        return;
      }
      emit(
        state.copyWith(
          isApplying: false,
          fanCurveDirty: false,
          noticeMessage: 'Fan curve applied to hardware.',
        ),
      );
    } catch (error) {
      if (_closing || emit.isDone) return;
      emit(state.copyWith(isApplying: false, errorMessage: error));
    }
  }

  Future<void> _apply(
    Emitter<FansState> emit, {
    required Future<void> Function() action,
    required String successMessage,
  }) async {
    if (state.isApplying) {
      return;
    }

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
    Emitter<FansState> emit, {
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

      final selectedPreset = _resolveSelectedPreset(
        currentSelected: state.selectedPreset,
        availablePresets: snapshot.availablePresets,
      );

      emit(
        state.copyWith(
          platformProfile: snapshot.platformProfile,
          onPowerSupply: snapshot.onPowerSupply,
          recommendedPreset: snapshot.recommendedPreset,
          availablePresets: snapshot.availablePresets,
          selectedPreset: selectedPreset,
          miniFanCurveEnabled: snapshot.miniFanCurveEnabled,
          lockFanControllerEnabled: snapshot.lockFanControllerEnabled,
          maximumFanSpeedEnabled: snapshot.maximumFanSpeedEnabled,
          fanCurve: state.fanCurveDirty ? state.fanCurve : snapshot.fanCurve,
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
            message: 'Failed to load fan settings: $error',
          ),
        ),
      );
      return false;
    }
  }

  String? _resolveSelectedPreset({
    required String? currentSelected,
    required List<String> availablePresets,
  }) {
    if (currentSelected != null && availablePresets.contains(currentSelected)) {
      return currentSelected;
    }

    return null;
  }

  @override
  Future<void> close() {
    _closing = true;
    _pollTimer?.cancel();
    return super.close();
  }
}
