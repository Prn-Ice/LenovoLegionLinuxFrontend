import 'dart:async';

import 'package:riverbloc/riverbloc.dart';

import '../repository/power_repository.dart';
import 'power_event.dart';
import 'power_state.dart';

class PowerBloc extends Bloc<PowerEvent, PowerState> {
  PowerBloc({
    required PowerRepository repository,
    Duration pollInterval = const Duration(seconds: 5),
  }) : _repository = repository,
       _pollInterval = pollInterval,
       super(PowerState.initial()) {
    on<PowerStarted>(_onStarted);
    on<PowerRefreshRequested>(_onRefreshRequested);
    on<PowerTicked>(_onTicked);
    on<PowerModeSetRequested>(_onModeSetRequested);
    on<PowerLimitSetRequested>(_onLimitSetRequested);
    on<PowerLimitsApplyRequested>(_onLimitsApplyRequested);
    on<CpuOverclockSetRequested>(_onCpuOverclockSetRequested);
    on<GpuOverclockSetRequested>(_onGpuOverclockSetRequested);
  }

  final PowerRepository _repository;
  final Duration _pollInterval;

  Timer? _pollTimer;
  bool _started = false;
  bool _refreshInFlight = false;

  Future<void> _onStarted(PowerStarted event, Emitter<PowerState> emit) async {
    if (_started) return;
    _started = true;
    await _reloadState(emit, showLoading: true);
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      add(const PowerTicked());
    });
  }

  Future<void> _onRefreshRequested(
    PowerRefreshRequested event,
    Emitter<PowerState> emit,
  ) async {
    await _reloadState(emit, showLoading: true);
  }

  Future<void> _onTicked(PowerTicked event, Emitter<PowerState> emit) async {
    if (state.isApplying) return;
    await _reloadState(emit, showLoading: false);
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

  Future<void> _onLimitsApplyRequested(
    PowerLimitsApplyRequested event,
    Emitter<PowerState> emit,
  ) async {
    if (state.isApplying || event.readings.isEmpty) return;

    emit(
      state.copyWith(isApplying: true, errorMessage: null, noticeMessage: null),
    );
    try {
      await _repository.setPowerLimits(event.readings);
      await _reloadState(emit, showLoading: false);
      emit(
        state.copyWith(
          isApplying: false,
          noticeMessage:
              '${event.readings.length} power ${event.readings.length == 1 ? 'limit' : 'limits'} applied.',
        ),
      );
    } catch (error) {
      await _reloadState(emit, showLoading: false);
      emit(state.copyWith(isApplying: false, errorMessage: '$error'));
    }
  }

  Future<void> _onCpuOverclockSetRequested(
    CpuOverclockSetRequested event,
    Emitter<PowerState> emit,
  ) async {
    if (state.isApplying || state.cpuOverclockEnabled == null) {
      return;
    }

    emit(
      state.copyWith(isApplying: true, errorMessage: null, noticeMessage: null),
    );

    try {
      await _repository.setCpuOverclock(event.enabled);
      await _reloadState(emit, showLoading: false);
      emit(
        state.copyWith(
          isApplying: false,
          noticeMessage:
              'CPU overclock ${event.enabled ? 'enabled' : 'disabled'}.',
        ),
      );
    } catch (error) {
      emit(state.copyWith(isApplying: false, errorMessage: '$error'));
    }
  }

  Future<void> _onGpuOverclockSetRequested(
    GpuOverclockSetRequested event,
    Emitter<PowerState> emit,
  ) async {
    if (state.isApplying || state.gpuOverclockEnabled == null) {
      return;
    }

    emit(
      state.copyWith(isApplying: true, errorMessage: null, noticeMessage: null),
    );

    try {
      await _repository.setGpuOverclock(event.enabled);
      await _reloadState(emit, showLoading: false);
      emit(
        state.copyWith(
          isApplying: false,
          noticeMessage:
              'GPU overclock ${event.enabled ? 'enabled' : 'disabled'}.',
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
          currentMode: snapshot.currentMode,
          availableModes: snapshot.availableModes,
          powerLimits: snapshot.powerLimits,
          cpuOverclockEnabled: snapshot.cpuOverclockEnabled,
          gpuOverclockEnabled: snapshot.gpuOverclockEnabled,
          onPowerSupply: snapshot.onPowerSupply,
          daemonSnapshot: snapshot.daemonSnapshot,
          cpuPolicy: snapshot.cpuPolicy,
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
