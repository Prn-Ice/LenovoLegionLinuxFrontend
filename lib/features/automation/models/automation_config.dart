import 'package:equatable/equatable.dart';

class AutomationConfig extends Equatable {
  const AutomationConfig({
    required this.runnerEnabled,
    required this.pollIntervalSeconds,
    required this.applyFanPresetOnContextChange,
    required this.triggerOnProfileChange,
    required this.triggerOnPowerSourceChange,
    required this.applyCustomConservation,
    required this.applyRapidChargingPolicy,
    required this.rapidChargingOnAc,
    required this.rapidChargingOnBattery,
    required this.conservationLowerLimit,
    required this.conservationUpperLimit,
    required this.runExternalCommand,
    required this.externalCommand,
    required this.externalCommandOnContextChange,
  });

  factory AutomationConfig.defaults() => const AutomationConfig(
    runnerEnabled: false,
    pollIntervalSeconds: 10,
    applyFanPresetOnContextChange: true,
    triggerOnProfileChange: true,
    triggerOnPowerSourceChange: true,
    applyCustomConservation: false,
    applyRapidChargingPolicy: false,
    rapidChargingOnAc: true,
    rapidChargingOnBattery: false,
    conservationLowerLimit: 60,
    conservationUpperLimit: 80,
    runExternalCommand: false,
    externalCommand: '',
    externalCommandOnContextChange: true,
  );

  factory AutomationConfig.fromJson(Map<String, dynamic> json) {
    final defaults = AutomationConfig.defaults();
    final poll =
        _asInt(json['pollIntervalSeconds']) ?? defaults.pollIntervalSeconds;
    final lower =
        _asInt(json['conservationLowerLimit']) ??
        defaults.conservationLowerLimit;
    final upper =
        _asInt(json['conservationUpperLimit']) ??
        defaults.conservationUpperLimit;

    return AutomationConfig(
      runnerEnabled: _asBool(json['runnerEnabled']) ?? defaults.runnerEnabled,
      pollIntervalSeconds: poll.clamp(2, 300),
      applyFanPresetOnContextChange:
          _asBool(json['applyFanPresetOnContextChange']) ??
          defaults.applyFanPresetOnContextChange,
      triggerOnProfileChange:
          _asBool(json['triggerOnProfileChange']) ??
          defaults.triggerOnProfileChange,
      triggerOnPowerSourceChange:
          _asBool(json['triggerOnPowerSourceChange']) ??
          defaults.triggerOnPowerSourceChange,
      applyCustomConservation:
          _asBool(json['applyCustomConservation']) ??
          defaults.applyCustomConservation,
      applyRapidChargingPolicy:
          _asBool(json['applyRapidChargingPolicy']) ??
          defaults.applyRapidChargingPolicy,
      rapidChargingOnAc:
          _asBool(json['rapidChargingOnAc']) ?? defaults.rapidChargingOnAc,
      rapidChargingOnBattery:
          _asBool(json['rapidChargingOnBattery']) ??
          defaults.rapidChargingOnBattery,
      conservationLowerLimit: lower.clamp(0, 100),
      conservationUpperLimit: upper.clamp(0, 100),
      runExternalCommand:
          _asBool(json['runExternalCommand']) ?? defaults.runExternalCommand,
      externalCommand:
          _asString(json['externalCommand']) ?? defaults.externalCommand,
      externalCommandOnContextChange:
          _asBool(json['externalCommandOnContextChange']) ??
          defaults.externalCommandOnContextChange,
    );
  }

  final bool runnerEnabled;
  final int pollIntervalSeconds;
  final bool applyFanPresetOnContextChange;
  final bool triggerOnProfileChange;
  final bool triggerOnPowerSourceChange;
  final bool applyCustomConservation;
  final bool applyRapidChargingPolicy;
  final bool rapidChargingOnAc;
  final bool rapidChargingOnBattery;
  final int conservationLowerLimit;
  final int conservationUpperLimit;
  final bool runExternalCommand;
  final String externalCommand;
  final bool externalCommandOnContextChange;

  Map<String, dynamic> toJson() {
    return {
      'runnerEnabled': runnerEnabled,
      'pollIntervalSeconds': pollIntervalSeconds,
      'applyFanPresetOnContextChange': applyFanPresetOnContextChange,
      'triggerOnProfileChange': triggerOnProfileChange,
      'triggerOnPowerSourceChange': triggerOnPowerSourceChange,
      'applyCustomConservation': applyCustomConservation,
      'applyRapidChargingPolicy': applyRapidChargingPolicy,
      'rapidChargingOnAc': rapidChargingOnAc,
      'rapidChargingOnBattery': rapidChargingOnBattery,
      'conservationLowerLimit': conservationLowerLimit,
      'conservationUpperLimit': conservationUpperLimit,
      'runExternalCommand': runExternalCommand,
      'externalCommand': externalCommand,
      'externalCommandOnContextChange': externalCommandOnContextChange,
    };
  }

  AutomationConfig copyWith({
    bool? runnerEnabled,
    int? pollIntervalSeconds,
    bool? applyFanPresetOnContextChange,
    bool? triggerOnProfileChange,
    bool? triggerOnPowerSourceChange,
    bool? applyCustomConservation,
    bool? applyRapidChargingPolicy,
    bool? rapidChargingOnAc,
    bool? rapidChargingOnBattery,
    int? conservationLowerLimit,
    int? conservationUpperLimit,
    bool? runExternalCommand,
    String? externalCommand,
    bool? externalCommandOnContextChange,
  }) {
    return AutomationConfig(
      runnerEnabled: runnerEnabled ?? this.runnerEnabled,
      pollIntervalSeconds: (pollIntervalSeconds ?? this.pollIntervalSeconds)
          .clamp(2, 300),
      applyFanPresetOnContextChange:
          applyFanPresetOnContextChange ?? this.applyFanPresetOnContextChange,
      triggerOnProfileChange:
          triggerOnProfileChange ?? this.triggerOnProfileChange,
      triggerOnPowerSourceChange:
          triggerOnPowerSourceChange ?? this.triggerOnPowerSourceChange,
      applyCustomConservation:
          applyCustomConservation ?? this.applyCustomConservation,
      applyRapidChargingPolicy:
          applyRapidChargingPolicy ?? this.applyRapidChargingPolicy,
      rapidChargingOnAc: rapidChargingOnAc ?? this.rapidChargingOnAc,
      rapidChargingOnBattery:
          rapidChargingOnBattery ?? this.rapidChargingOnBattery,
      conservationLowerLimit:
          (conservationLowerLimit ?? this.conservationLowerLimit).clamp(0, 100),
      conservationUpperLimit:
          (conservationUpperLimit ?? this.conservationUpperLimit).clamp(0, 100),
      runExternalCommand: runExternalCommand ?? this.runExternalCommand,
      externalCommand: externalCommand ?? this.externalCommand,
      externalCommandOnContextChange:
          externalCommandOnContextChange ?? this.externalCommandOnContextChange,
    );
  }

  bool get hasValidConservationRange =>
      conservationLowerLimit <= conservationUpperLimit;

  @override
  List<Object?> get props => [
    runnerEnabled,
    pollIntervalSeconds,
    applyFanPresetOnContextChange,
    triggerOnProfileChange,
    triggerOnPowerSourceChange,
    applyCustomConservation,
    applyRapidChargingPolicy,
    rapidChargingOnAc,
    rapidChargingOnBattery,
    conservationLowerLimit,
    conservationUpperLimit,
    runExternalCommand,
    externalCommand,
    externalCommandOnContextChange,
  ];

  static bool? _asBool(dynamic value) {
    if (value is bool) {
      return value;
    }
    return null;
  }

  static int? _asInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  static String? _asString(dynamic value) {
    if (value is String) {
      return value;
    }
    return null;
  }
}
