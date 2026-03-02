import 'package:equatable/equatable.dart';

class AutomationConfig extends Equatable {
  const AutomationConfig({
    required this.runnerEnabled,
    required this.pollIntervalSeconds,
    required this.applyFanPresetOnContextChange,
    required this.applyCustomConservation,
    required this.conservationLowerLimit,
    required this.conservationUpperLimit,
  });

  factory AutomationConfig.defaults() => const AutomationConfig(
    runnerEnabled: false,
    pollIntervalSeconds: 10,
    applyFanPresetOnContextChange: true,
    applyCustomConservation: false,
    conservationLowerLimit: 60,
    conservationUpperLimit: 80,
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
      applyCustomConservation:
          _asBool(json['applyCustomConservation']) ??
          defaults.applyCustomConservation,
      conservationLowerLimit: lower.clamp(0, 100),
      conservationUpperLimit: upper.clamp(0, 100),
    );
  }

  final bool runnerEnabled;
  final int pollIntervalSeconds;
  final bool applyFanPresetOnContextChange;
  final bool applyCustomConservation;
  final int conservationLowerLimit;
  final int conservationUpperLimit;

  Map<String, dynamic> toJson() {
    return {
      'runnerEnabled': runnerEnabled,
      'pollIntervalSeconds': pollIntervalSeconds,
      'applyFanPresetOnContextChange': applyFanPresetOnContextChange,
      'applyCustomConservation': applyCustomConservation,
      'conservationLowerLimit': conservationLowerLimit,
      'conservationUpperLimit': conservationUpperLimit,
    };
  }

  AutomationConfig copyWith({
    bool? runnerEnabled,
    int? pollIntervalSeconds,
    bool? applyFanPresetOnContextChange,
    bool? applyCustomConservation,
    int? conservationLowerLimit,
    int? conservationUpperLimit,
  }) {
    return AutomationConfig(
      runnerEnabled: runnerEnabled ?? this.runnerEnabled,
      pollIntervalSeconds: (pollIntervalSeconds ?? this.pollIntervalSeconds)
          .clamp(2, 300),
      applyFanPresetOnContextChange:
          applyFanPresetOnContextChange ?? this.applyFanPresetOnContextChange,
      applyCustomConservation:
          applyCustomConservation ?? this.applyCustomConservation,
      conservationLowerLimit:
          (conservationLowerLimit ?? this.conservationLowerLimit).clamp(0, 100),
      conservationUpperLimit:
          (conservationUpperLimit ?? this.conservationUpperLimit).clamp(0, 100),
    );
  }

  bool get hasValidConservationRange =>
      conservationLowerLimit <= conservationUpperLimit;

  @override
  List<Object?> get props => [
    runnerEnabled,
    pollIntervalSeconds,
    applyFanPresetOnContextChange,
    applyCustomConservation,
    conservationLowerLimit,
    conservationUpperLimit,
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
}
