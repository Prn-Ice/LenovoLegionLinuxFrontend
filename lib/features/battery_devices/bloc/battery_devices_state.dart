import 'package:equatable/equatable.dart';

class BatteryDevicesState extends Equatable {
  const BatteryDevicesState({
    required this.batteryConservationEnabled,
    required this.rapidChargingEnabled,
    required this.alwaysOnUsbChargingEnabled,
    required this.touchpadEnabled,
    required this.winKeyEnabled,
    required this.cameraPowerEnabled,
    required this.isLoading,
    required this.isApplying,
    required this.errorMessage,
    required this.noticeMessage,
  });

  factory BatteryDevicesState.initial() => const BatteryDevicesState(
    batteryConservationEnabled: null,
    rapidChargingEnabled: null,
    alwaysOnUsbChargingEnabled: null,
    touchpadEnabled: null,
    winKeyEnabled: null,
    cameraPowerEnabled: null,
    isLoading: false,
    isApplying: false,
    errorMessage: null,
    noticeMessage: null,
  );

  static const _unset = Object();

  final bool? batteryConservationEnabled;
  final bool? rapidChargingEnabled;
  final bool? alwaysOnUsbChargingEnabled;
  final bool? touchpadEnabled;
  final bool? winKeyEnabled;
  final bool? cameraPowerEnabled;
  final bool isLoading;
  final bool isApplying;
  final String? errorMessage;
  final String? noticeMessage;

  bool get hasLoaded =>
      batteryConservationEnabled != null ||
      rapidChargingEnabled != null ||
      alwaysOnUsbChargingEnabled != null ||
      touchpadEnabled != null ||
      winKeyEnabled != null ||
      cameraPowerEnabled != null;

  BatteryDevicesState copyWith({
    Object? batteryConservationEnabled = _unset,
    Object? rapidChargingEnabled = _unset,
    Object? alwaysOnUsbChargingEnabled = _unset,
    Object? touchpadEnabled = _unset,
    Object? winKeyEnabled = _unset,
    Object? cameraPowerEnabled = _unset,
    bool? isLoading,
    bool? isApplying,
    Object? errorMessage = _unset,
    Object? noticeMessage = _unset,
  }) {
    return BatteryDevicesState(
      batteryConservationEnabled: batteryConservationEnabled == _unset
          ? this.batteryConservationEnabled
          : batteryConservationEnabled as bool?,
      rapidChargingEnabled: rapidChargingEnabled == _unset
          ? this.rapidChargingEnabled
          : rapidChargingEnabled as bool?,
      alwaysOnUsbChargingEnabled: alwaysOnUsbChargingEnabled == _unset
          ? this.alwaysOnUsbChargingEnabled
          : alwaysOnUsbChargingEnabled as bool?,
      touchpadEnabled: touchpadEnabled == _unset
          ? this.touchpadEnabled
          : touchpadEnabled as bool?,
      winKeyEnabled: winKeyEnabled == _unset
          ? this.winKeyEnabled
          : winKeyEnabled as bool?,
      cameraPowerEnabled: cameraPowerEnabled == _unset
          ? this.cameraPowerEnabled
          : cameraPowerEnabled as bool?,
      isLoading: isLoading ?? this.isLoading,
      isApplying: isApplying ?? this.isApplying,
      errorMessage: errorMessage == _unset
          ? this.errorMessage
          : errorMessage as String?,
      noticeMessage: noticeMessage == _unset
          ? this.noticeMessage
          : noticeMessage as String?,
    );
  }

  @override
  List<Object?> get props => [
    batteryConservationEnabled,
    rapidChargingEnabled,
    alwaysOnUsbChargingEnabled,
    touchpadEnabled,
    winKeyEnabled,
    cameraPowerEnabled,
    isLoading,
    isApplying,
    errorMessage,
    noticeMessage,
  ];
}
