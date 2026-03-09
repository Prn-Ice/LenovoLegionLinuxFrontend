import 'dart:async';

import 'package:riverbloc/riverbloc.dart';

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
    on<BatteryStarted>(_onStarted);
    on<BatteryRefreshRequested>(_onRefreshRequested);
    on<BatteryTicked>(_onTicked);
    on<BatteryConservationSetRequested>(_onBatteryConservationSetRequested);
    on<RapidChargingSetRequested>(_onRapidChargingSetRequested);
  }

  final BatteryRepository _repository;
  final Duration _pollInterval;

  Timer? _pollTimer;
  bool _started = false;
  bool _refreshInFlight = false;

  Future<void> _onStarted(
    BatteryStarted event,
    Emitter<BatteryState> emit,
  ) async {
    if (_started) return;
    _started = true;
    await _reloadState(emit, showLoading: true);
    _pollTimer = Timer.periodic(_pollInterval, (_) {
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
      await _reloadState(emit, showLoading: false);
      emit(state.copyWith(isApplying: false, noticeMessage: successMessage));
    } catch (error) {
      emit(state.copyWith(isApplying: false, errorMessage: '$error'));
    }
  }

  Future<void> _reloadState(
    Emitter<BatteryState> emit, {
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
          isLoading: false,
          errorMessage: null,
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          isLoading: false,
          errorMessage: 'Failed to load battery settings: $error',
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
