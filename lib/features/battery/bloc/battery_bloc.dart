import 'dart:async';

import 'package:riverbloc/riverbloc.dart';

import '../../../core/models/app_failure.dart';
import '../repository/battery_repository.dart';
import 'battery_event.dart';
import 'battery_state.dart';

class BatteryBloc extends Bloc<BatteryEvent, BatteryState> {
  BatteryBloc({
    required BatteryRepository repository,
    Duration pollInterval = const Duration(seconds: 5),
  }) : _repository = repository,
       _pollInterval = pollInterval,
       super(BatteryState.initial()) {
    on<BatteryEvent>(
      (event, emit) async {
        if (_closing) return;
        switch (event) {
          case BatteryStarted():
            await _onStarted(event, emit);
          case BatteryRefreshRequested():
            await _onRefreshRequested(event, emit);
          case BatteryTicked():
            try {
              await _onTicked(event, emit);
            } finally {
              _tickPending = false;
            }
          case BatteryConservationSetRequested():
            await _onBatteryConservationSetRequested(event, emit);
          case RapidChargingSetRequested():
            await _onRapidChargingSetRequested(event, emit);
          case AlwaysOnUsbSetRequested():
            await _onAlwaysOnUsbSetRequested(event, emit);
        }
      },
      // One queue orders polling, writes, and each write's readback.
      transformer: (events, mapper) => events.asyncExpand(mapper),
    );
  }

  final BatteryRepository _repository;
  final Duration _pollInterval;

  Timer? _pollTimer;
  bool _started = false;
  bool _closing = false;
  bool _tickPending = false;

  @override
  void add(BatteryEvent event) {
    // Reject busy writes at arrival, before they can wait in the event queue.
    if (state.isApplying &&
        switch (event) {
          BatteryStarted() ||
          BatteryRefreshRequested() ||
          BatteryTicked() => false,
          _ => true,
        }) {
      return;
    }
    super.add(event);
  }

  Future<void> _onStarted(
    BatteryStarted event,
    Emitter<BatteryState> emit,
  ) async {
    if (_started) return;
    _started = true;
    await _reloadState(emit, showLoading: true);
    if (_closing || emit.isDone) return;
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      if (_closing || _tickPending || state.isApplying) return;
      _tickPending = true;
      add(const BatteryTicked());
    });
  }

  Future<void> _onRefreshRequested(
    BatteryRefreshRequested event,
    Emitter<BatteryState> emit,
  ) async {
    await _reloadState(emit, showLoading: true);
  }

  Future<void> _onTicked(
    BatteryTicked event,
    Emitter<BatteryState> emit,
  ) async {
    if (state.isApplying) return;
    await _reloadState(emit, showLoading: false);
  }

  Future<void> _onBatteryConservationSetRequested(
    BatteryConservationSetRequested event,
    Emitter<BatteryState> emit,
  ) async {
    await _apply(
      emit,
      action: () => _repository.setBatteryConservation(event.enabled),
      successMessage:
          'Battery conservation ${event.enabled ? 'enabled' : 'disabled'}.',
    );
  }

  Future<void> _onRapidChargingSetRequested(
    RapidChargingSetRequested event,
    Emitter<BatteryState> emit,
  ) async {
    await _apply(
      emit,
      action: () => _repository.setRapidCharging(event.enabled),
      successMessage:
          'Rapid charging ${event.enabled ? 'enabled' : 'disabled'}.',
    );
  }

  Future<void> _onAlwaysOnUsbSetRequested(
    AlwaysOnUsbSetRequested event,
    Emitter<BatteryState> emit,
  ) async {
    if (!state.alwaysOnUsbSupported) return;
    await _apply(
      emit,
      action: () => _repository.setAlwaysOnUsb(event.enabled),
      successMessage:
          'Always-on USB charging ${event.enabled ? 'enabled' : 'disabled'}.',
    );
  }

  Future<void> _apply(
    Emitter<BatteryState> emit, {
    required Future<void> Function() action,
    required String successMessage,
  }) async {
    if (state.isApplying) return;

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
    Emitter<BatteryState> emit, {
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
          batteryConservationEnabled: snapshot.batteryConservationEnabled,
          batteryConservationSupported: snapshot.batteryConservationSupported,
          rapidChargingEnabled: snapshot.rapidChargingEnabled,
          rapidChargingSupported: snapshot.rapidChargingSupported,
          batteryPercent: snapshot.batteryPercent,
          batteryCharging: snapshot.batteryCharging,
          batteryPowerDrawW: snapshot.batteryPowerDrawW,
          cycleCounts: snapshot.cycleCounts,
          fullCapacityWh: snapshot.fullCapacityWh,
          designCapacityWh: snapshot.designCapacityWh,
          currentCapacityWh: snapshot.currentCapacityWh,
          batteryTempC: snapshot.batteryTempC,
          batteryStatus: snapshot.batteryStatus,
          alwaysOnUsbEnabled: snapshot.alwaysOnUsbEnabled,
          alwaysOnUsbSupported: snapshot.alwaysOnUsbSupported,
          voltageV: snapshot.voltageV,
          manufacturer: snapshot.manufacturer,
          modelName: snapshot.modelName,
          serialNumber: snapshot.serialNumber,
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
            message: 'Failed to load battery settings: $error',
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
