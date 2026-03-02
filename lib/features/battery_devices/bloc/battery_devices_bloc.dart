import 'package:riverbloc/riverbloc.dart';

import '../repository/battery_devices_repository.dart';
import 'battery_devices_event.dart';
import 'battery_devices_state.dart';

class BatteryDevicesBloc
    extends Bloc<BatteryDevicesEvent, BatteryDevicesState> {
  BatteryDevicesBloc({required BatteryDevicesRepository repository})
    : _repository = repository,
      super(BatteryDevicesState.initial()) {
    on<BatteryDevicesStarted>(_onStarted);
    on<BatteryDevicesRefreshRequested>(_onRefreshRequested);
    on<BatteryConservationSetRequested>(_onBatteryConservationSetRequested);
    on<RapidChargingSetRequested>(_onRapidChargingSetRequested);
    on<AlwaysOnUsbChargingSetRequested>(_onAlwaysOnUsbChargingSetRequested);
    on<TouchpadSetRequested>(_onTouchpadSetRequested);
    on<WinKeySetRequested>(_onWinKeySetRequested);
  }

  final BatteryDevicesRepository _repository;

  Future<void> _onStarted(
    BatteryDevicesStarted event,
    Emitter<BatteryDevicesState> emit,
  ) async {
    await _reloadState(emit, showLoading: true);
  }

  Future<void> _onRefreshRequested(
    BatteryDevicesRefreshRequested event,
    Emitter<BatteryDevicesState> emit,
  ) async {
    await _reloadState(emit, showLoading: true);
  }

  Future<void> _onBatteryConservationSetRequested(
    BatteryConservationSetRequested event,
    Emitter<BatteryDevicesState> emit,
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
    Emitter<BatteryDevicesState> emit,
  ) async {
    await _apply(
      emit,
      action: () => _repository.setRapidCharging(event.enabled),
      successMessage:
          'Rapid charging ${event.enabled ? 'enabled' : 'disabled'}.',
    );
  }

  Future<void> _onAlwaysOnUsbChargingSetRequested(
    AlwaysOnUsbChargingSetRequested event,
    Emitter<BatteryDevicesState> emit,
  ) async {
    await _apply(
      emit,
      action: () => _repository.setAlwaysOnUsbCharging(event.enabled),
      successMessage:
          'Always-on USB charging ${event.enabled ? 'enabled' : 'disabled'}.',
    );
  }

  Future<void> _onTouchpadSetRequested(
    TouchpadSetRequested event,
    Emitter<BatteryDevicesState> emit,
  ) async {
    await _apply(
      emit,
      action: () => _repository.setTouchpad(event.enabled),
      successMessage: 'Touchpad ${event.enabled ? 'enabled' : 'disabled'}.',
    );
  }

  Future<void> _onWinKeySetRequested(
    WinKeySetRequested event,
    Emitter<BatteryDevicesState> emit,
  ) async {
    await _apply(
      emit,
      action: () => _repository.setWinKey(event.enabled),
      successMessage: 'Win key ${event.enabled ? 'enabled' : 'disabled'}.',
    );
  }

  Future<void> _apply(
    Emitter<BatteryDevicesState> emit, {
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
    Emitter<BatteryDevicesState> emit, {
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
          batteryConservationEnabled: snapshot.batteryConservationEnabled,
          rapidChargingEnabled: snapshot.rapidChargingEnabled,
          alwaysOnUsbChargingEnabled: snapshot.alwaysOnUsbChargingEnabled,
          alwaysOnUsbWriteSupported: snapshot.alwaysOnUsbWriteSupported,
          touchpadEnabled: snapshot.touchpadEnabled,
          winKeyEnabled: snapshot.winKeyEnabled,
          cameraPowerEnabled: snapshot.cameraPowerEnabled,
          isLoading: false,
          errorMessage: null,
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          isLoading: false,
          errorMessage: 'Failed to load battery/device settings: $error',
        ),
      );
    }
  }
}
