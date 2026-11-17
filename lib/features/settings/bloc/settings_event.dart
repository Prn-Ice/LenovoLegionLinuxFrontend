import 'package:equatable/equatable.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yaru/yaru.dart';

sealed class SettingsEvent extends Equatable {
  const SettingsEvent();

  @override
  List<Object?> get props => const [];
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
