import 'package:riverbloc/riverbloc.dart';

import '../repository/fans_repository.dart';
import 'fans_event.dart';
import 'fans_state.dart';

class FansBloc extends Bloc<FansEvent, FansState> {
  FansBloc({required FansRepository repository})
    : _repository = repository,
      super(FansState.initial()) {
    on<FansStarted>(_onStarted);
    on<FansRefreshRequested>(_onRefreshRequested);
    on<FansPresetSelectionChanged>(_onPresetSelectionChanged);
    on<FansApplyCurrentPresetRequested>(_onApplyCurrentPresetRequested);
    on<FansApplySelectedPresetRequested>(_onApplySelectedPresetRequested);
    on<MiniFanCurveSetRequested>(_onMiniFanCurveSetRequested);
    on<LockFanControllerSetRequested>(_onLockFanControllerSetRequested);
    on<MaximumFanSpeedSetRequested>(_onMaximumFanSpeedSetRequested);
    on<FanCurvePointUpdated>(_onFanCurvePointUpdated);
    on<FanCurveSaveRequested>(_onFanCurveSaveRequested);
  }

  final FansRepository _repository;

  Future<void> _onStarted(FansStarted event, Emitter<FansState> emit) async {
    await _reloadState(emit, showLoading: true);
  }

  Future<void> _onRefreshRequested(
    FansRefreshRequested event,
    Emitter<FansState> emit,
  ) async {
    await _reloadState(emit, showLoading: true);
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
    if (current == null || event.index < 0 || event.index >= 10) {
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
      await _reloadState(emit, showLoading: false);
      emit(
        state.copyWith(
          isApplying: false,
          fanCurveDirty: false,
          noticeMessage: 'Fan curve applied to hardware.',
        ),
      );
    } catch (error) {
      emit(state.copyWith(isApplying: false, errorMessage: '$error'));
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
      await _reloadState(emit, showLoading: false);
      emit(state.copyWith(isApplying: false, noticeMessage: successMessage));
    } catch (error) {
      emit(state.copyWith(isApplying: false, errorMessage: '$error'));
    }
  }

  Future<void> _reloadState(
    Emitter<FansState> emit, {
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

      final selectedPreset = _resolveSelectedPreset(
        currentSelected: state.selectedPreset,
        recommendedPreset: snapshot.recommendedPreset,
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
    } catch (error) {
      emit(
        state.copyWith(
          isLoading: false,
          errorMessage: 'Failed to load fan settings: $error',
        ),
      );
    }
  }

  String? _resolveSelectedPreset({
    required String? currentSelected,
    required String? recommendedPreset,
    required List<String> availablePresets,
  }) {
    if (currentSelected != null && availablePresets.contains(currentSelected)) {
      return currentSelected;
    }

    if (recommendedPreset != null &&
        availablePresets.contains(recommendedPreset)) {
      return recommendedPreset;
    }

    return availablePresets.isEmpty ? null : availablePresets.first;
  }
}
