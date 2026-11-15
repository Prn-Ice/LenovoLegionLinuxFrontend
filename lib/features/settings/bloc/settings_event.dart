import 'package:equatable/equatable.dart';
import '../../../core/models/control_mode.dart';
import '../../../core/models/app_failure.dart';
import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';

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

sealed class AppearanceChanged extends SettingsEvent {
  const AppearanceChanged();
}

final class AccentFollowsPowerModeChanged extends AppearanceChanged {
  const AccentFollowsPowerModeChanged(this.enabled);
  final bool enabled;
  @override
  List<Object?> get props => [enabled];
}

final class ThemeModeChanged extends AppearanceChanged {
  const ThemeModeChanged(this.themeMode);
  final ThemeMode themeMode;
  @override
  List<Object?> get props => [themeMode];
}

final class YaruVariantChanged extends AppearanceChanged {
  const YaruVariantChanged(this.variant);
  final YaruVariant? variant;
  @override
  List<Object?> get props => [variant];
}

final class ControlModeChanged extends SettingsEvent {
  const ControlModeChanged(this.mode);
  final ControlMode mode;
  @override
  List<Object?> get props => [mode];
}

final class ControlModeErrorDismissed extends SettingsEvent {
  const ControlModeErrorDismissed(this.error);
  final AppFailure error;
  @override
  List<Object?> get props => [error];
}
