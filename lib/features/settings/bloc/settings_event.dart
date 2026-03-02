import 'package:equatable/equatable.dart';

sealed class SettingsEvent extends Equatable {
  const SettingsEvent();

  @override
  List<Object?> get props => const [];
}

final class SettingsStarted extends SettingsEvent {
  const SettingsStarted();
}

final class SettingsRefreshRequested extends SettingsEvent {
  const SettingsRefreshRequested();
}

final class SettingsServiceToggled extends SettingsEvent {
  const SettingsServiceToggled({
    required this.serviceId,
    required this.enabled,
  });

  final String serviceId;
  final bool enabled;

  @override
  List<Object?> get props => [serviceId, enabled];
}
