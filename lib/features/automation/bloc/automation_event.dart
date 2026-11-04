import 'package:equatable/equatable.dart';
import '../models/automation_config.dart';

sealed class AutomationEvent extends Equatable {
  const AutomationEvent();
  @override
  List<Object?> get props => [];
}

final class AutomationStarted extends AutomationEvent {
  const AutomationStarted();
}

final class KeyboardProfileAssigned extends AutomationEvent {
  const KeyboardProfileAssigned(this.mode, this.profile);
  final KeyboardPowerMode mode;
  final String? profile;
  @override
  List<Object?> get props => [mode, profile];
}
