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

final class AutomationConservationRuleToggled extends AutomationEvent {
  const AutomationConservationRuleToggled(this.enabled);

  final bool enabled;

  @override
  List<Object?> get props => [enabled];
}

final class AutomationRunNowRequested extends AutomationEvent {
  const AutomationRunNowRequested();
}

final class AutomationTicked extends AutomationEvent {
  const AutomationTicked();
}
