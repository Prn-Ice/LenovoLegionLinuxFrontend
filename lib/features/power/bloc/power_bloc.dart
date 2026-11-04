import 'dart:async';

import 'package:riverbloc/riverbloc.dart';

import '../../../core/models/app_failure.dart';
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
    on<PowerEvent>(
      (event, emit) async {
        if (_closing) return;
        switch (event) {
          case PowerStarted():
            await _onStarted(event, emit);
          case PowerRefreshRequested():
            await _onRefreshRequested(event, emit);
          case PowerTicked():
            try {
              await _onTicked(event, emit);
            } finally {
              _tickPending = false;
            }
          case PowerModeSetRequested():
            await _onModeSetRequested(event, emit);
          case PowerLimitSetRequested():
            await _onLimitSetRequested(event, emit);
          case PowerLimitsApplyRequested():
            await _onLimitsApplyRequested(event, emit);
          case CpuOverclockSetRequested():
            await _onCpuOverclockSetRequested(event, emit);
          case GpuOverclockSetRequested():
            await _onGpuOverclockSetRequested(event, emit);
        }
      },
      // One queue orders polling, writes, and each write's readback.
      transformer: (events, mapper) => events.asyncExpand(mapper),
    );
  }

  final PowerRepository _repository;
  final Duration _pollInterval;

  Timer? _pollTimer;
  bool _started = false;
  bool _closing = false;
  bool _tickPending = false;

  @override
  void add(PowerEvent event) {
    // Reject busy writes at arrival, before they can wait in the event queue.
    if (state.isApplying &&
        switch (event) {
          PowerStarted() || PowerRefreshRequested() || PowerTicked() => false,
          _ => true,
        }) {
      return;
    }
    super.add(event);
  }

  Future<void> _onStarted(PowerStarted event, Emitter<PowerState> emit) async {
    if (_started) return;
    _started = true;
    await _reloadState(emit, showLoading: true);
    if (_closing || emit.isDone) return;
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      if (_closing || _tickPending || state.isApplying) return;
      _tickPending = true;
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
      final loaded = await _reloadState(emit, showLoading: false);
      if (_closing || emit.isDone) return;
      if (!loaded) {
        emit(state.copyWith(isApplying: false));
        return;
      }
      emit(
        state.copyWith(
          isApplying: false,
          noticeMessage: 'Power mode set to ${event.mode.label}.',
        ),
      );
    } catch (error) {
      if (_closing || emit.isDone) return;
      emit(state.copyWith(isApplying: false, errorMessage: error));
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
      final loaded = await _reloadState(emit, showLoading: false);
      if (_closing || emit.isDone) return;
      if (!loaded) {
        emit(state.copyWith(isApplying: false));
        return;
      }
      emit(
        state.copyWith(
          isApplying: false,
          noticeMessage: '${event.limit.label} set to ${event.value}.',
        ),
      );
    } catch (error) {
      if (_closing || emit.isDone) return;
      emit(state.copyWith(isApplying: false, errorMessage: error));
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
              '${event.readings.length} power ${event.readings.length == 1 ? 'limit' : 'limits'} applied.',
        ),
      );
    } catch (error) {
      await _reloadState(emit, showLoading: false);
      if (_closing || emit.isDone) return;
      emit(state.copyWith(isApplying: false, errorMessage: error));
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
              'CPU overclock ${event.enabled ? 'enabled' : 'disabled'}.',
        ),
      );
    } catch (error) {
      if (_closing || emit.isDone) return;
      emit(state.copyWith(isApplying: false, errorMessage: error));
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
              'GPU overclock ${event.enabled ? 'enabled' : 'disabled'}.',
        ),
      );
    } catch (error) {
      if (_closing || emit.isDone) return;
      emit(state.copyWith(isApplying: false, errorMessage: error));
    }
  }

  Future<bool> _reloadState(
    Emitter<PowerState> emit, {
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
      return true;
    } catch (error) {
      if (_closing || emit.isDone) return false;
      emit(
        state.copyWith(
          isLoading: false,
          errorMessage: AppFailure.from(
            error,
            message: 'Failed to load power settings: $error',
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
