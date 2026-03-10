import 'package:equatable/equatable.dart';
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

final class ThemeModeChanged extends SettingsEvent {
  const ThemeModeChanged(this.themeMode);
  final ThemeMode themeMode;
  @override
  List<Object?> get props => [themeMode];
}

final class YaruVariantChanged extends SettingsEvent {
  const YaruVariantChanged(this.variant);
  final YaruVariant? variant;
  @override
  List<Object?> get props => [variant];
}
