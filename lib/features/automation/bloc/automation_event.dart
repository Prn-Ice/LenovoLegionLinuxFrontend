import 'package:equatable/equatable.dart';

class AutomationConservationLimitsUpdated extends AutomationEvent {
  const AutomationConservationLimitsUpdated({
    required this.lower,
    required this.upper,
  });

  final int lower;
  final int upper;

  @override
  List<Object?> get props => [lower, upper];
}

final class AutomationExternalCommandRuleToggled extends AutomationEvent {
  const AutomationExternalCommandRuleToggled(this.enabled);

  final bool enabled;

  @override
  List<Object?> get props => [enabled];
}

final class AutomationExternalCommandUpdated extends AutomationEvent {
  const AutomationExternalCommandUpdated(this.command);

  final String command;

  @override
  List<Object?> get props => [command];
}

final class AutomationExternalCommandTriggerUpdated extends AutomationEvent {
  const AutomationExternalCommandTriggerUpdated(this.onContextChange);

  final bool onContextChange;

  @override
  List<Object?> get props => [onContextChange];
}

sealed class AutomationEvent extends Equatable {
  const AutomationEvent();

  @override
  List<Object?> get props => const [];
}

final class AutomationStarted extends AutomationEvent {
  const AutomationStarted();
}

final class AutomationRunnerToggled extends AutomationEvent {
  const AutomationRunnerToggled(this.enabled);

  final bool enabled;

  @override
  List<Object?> get props => [enabled];
}

final class AutomationPollIntervalUpdated extends AutomationEvent {
  const AutomationPollIntervalUpdated(this.seconds);

  final int seconds;

  @override
  List<Object?> get props => [seconds];
}

final class AutomationFanPresetRuleToggled extends AutomationEvent {
  const AutomationFanPresetRuleToggled(this.enabled);

  final bool enabled;

  @override
  List<Object?> get props => [enabled];
}

final class AutomationTriggerOnProfileChangeToggled extends AutomationEvent {
  const AutomationTriggerOnProfileChangeToggled(this.enabled);

  final bool enabled;

  @override
  List<Object?> get props => [enabled];
}

final class AutomationTriggerOnPowerSourceChangeToggled
    extends AutomationEvent {
  const AutomationTriggerOnPowerSourceChangeToggled(this.enabled);

  final bool enabled;

  @override
  List<Object?> get props => [enabled];
}

final class AutomationConservationRuleToggled extends AutomationEvent {
  const AutomationConservationRuleToggled(this.enabled);

  final bool enabled;

  @override
  List<Object?> get props => [enabled];
}

final class AutomationRapidChargingPolicyToggled extends AutomationEvent {
  const AutomationRapidChargingPolicyToggled(this.enabled);

  final bool enabled;

  @override
  List<Object?> get props => [enabled];
}

final class AutomationRapidChargingTargetsUpdated extends AutomationEvent {
  const AutomationRapidChargingTargetsUpdated({
    required this.onAc,
    required this.onBattery,
  });

  final bool onAc;
  final bool onBattery;

  @override
  List<Object?> get props => [onAc, onBattery];
}

final class AutomationRunNowRequested extends AutomationEvent {
  const AutomationRunNowRequested();
}

final class AutomationTicked extends AutomationEvent {
  const AutomationTicked();
}
