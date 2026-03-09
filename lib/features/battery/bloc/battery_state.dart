import 'package:equatable/equatable.dart';

class BatteryState extends Equatable {
  const BatteryState({
    required this.batteryConservationEnabled,
    required this.batteryConservationSupported,
    required this.rapidChargingEnabled,
    required this.rapidChargingSupported,
    required this.batteryPercent,
    required this.batteryCharging,
    required this.batteryPowerDrawW,
    required this.cycleCounts,
    required this.fullCapacityWh,
    required this.designCapacityWh,
    required this.currentCapacityWh,
    required this.batteryTempC,
    required this.isLoading,
    required this.isApplying,
    required this.errorMessage,
    required this.noticeMessage,
  });

  factory BatteryState.initial() => const BatteryState(
    batteryConservationEnabled: null,
    batteryConservationSupported: false,
    rapidChargingEnabled: null,
    rapidChargingSupported: false,
    batteryPercent: null,
    batteryCharging: null,
    batteryPowerDrawW: null,
    cycleCounts: null,
    fullCapacityWh: null,
    designCapacityWh: null,
    currentCapacityWh: null,
    batteryTempC: null,
    isLoading: false,
    isApplying: false,
    errorMessage: null,
    noticeMessage: null,
  );

  static const _unset = Object();

  final bool? batteryConservationEnabled;
  final bool batteryConservationSupported;
  final bool? rapidChargingEnabled;
  final bool rapidChargingSupported;
  final int? batteryPercent;
  final bool? batteryCharging;
  final double? batteryPowerDrawW;
  final int? cycleCounts;
  final double? fullCapacityWh;
  final double? designCapacityWh;
  final double? currentCapacityWh;
  final double? batteryTempC;
  final bool isLoading;
  final bool isApplying;
  final String? errorMessage;
  final String? noticeMessage;

  bool get hasLoaded =>
      batteryConservationEnabled != null ||
      rapidChargingEnabled != null ||
      batteryPercent != null;

  BatteryState copyWith({
    Object? batteryConservationEnabled = _unset,
    bool? batteryConservationSupported,
    Object? rapidChargingEnabled = _unset,
    bool? rapidChargingSupported,
    Object? batteryPercent = _unset,
    Object? batteryCharging = _unset,
    Object? batteryPowerDrawW = _unset,
    Object? cycleCounts = _unset,
    Object? fullCapacityWh = _unset,
    Object? designCapacityWh = _unset,
    Object? currentCapacityWh = _unset,
    Object? batteryTempC = _unset,
    bool? isLoading,
    bool? isApplying,
    Object? errorMessage = _unset,
    Object? noticeMessage = _unset,
  }) {
    return BatteryState(
      batteryConservationEnabled: batteryConservationEnabled == _unset
          ? this.batteryConservationEnabled
          : batteryConservationEnabled as bool?,
      batteryConservationSupported:
          batteryConservationSupported ?? this.batteryConservationSupported,
      rapidChargingEnabled: rapidChargingEnabled == _unset
          ? this.rapidChargingEnabled
          : rapidChargingEnabled as bool?,
      rapidChargingSupported:
          rapidChargingSupported ?? this.rapidChargingSupported,
      batteryPercent: batteryPercent == _unset
          ? this.batteryPercent
          : batteryPercent as int?,
      batteryCharging: batteryCharging == _unset
          ? this.batteryCharging
          : batteryCharging as bool?,
      batteryPowerDrawW: batteryPowerDrawW == _unset
          ? this.batteryPowerDrawW
          : batteryPowerDrawW as double?,
      cycleCounts: cycleCounts == _unset
          ? this.cycleCounts
          : cycleCounts as int?,
      fullCapacityWh: fullCapacityWh == _unset
          ? this.fullCapacityWh
          : fullCapacityWh as double?,
      designCapacityWh: designCapacityWh == _unset
          ? this.designCapacityWh
          : designCapacityWh as double?,
      currentCapacityWh: currentCapacityWh == _unset
          ? this.currentCapacityWh
          : currentCapacityWh as double?,
      batteryTempC: batteryTempC == _unset
          ? this.batteryTempC
          : batteryTempC as double?,
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
    batteryConservationSupported,
    rapidChargingEnabled,
    rapidChargingSupported,
    batteryPercent,
    batteryCharging,
    batteryPowerDrawW,
    cycleCounts,
    fullCapacityWh,
    designCapacityWh,
    currentCapacityWh,
    batteryTempC,
    isLoading,
    isApplying,
    errorMessage,
    noticeMessage,
  ];
}
