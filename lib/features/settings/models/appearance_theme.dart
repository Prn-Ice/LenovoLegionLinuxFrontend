import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';

import '../../../core/theme/legion_accent.dart';
import '../bloc/settings_state.dart';

/// Follow only known observed modes; never discard the saved manual choice.
LegionAccent? appearancePowerAccent(SettingsState settings, String? mode) =>
    settings.accentFollowsPowerMode
    ? LegionAccent.fromPowerModeValue(mode)
    : null;

({ThemeData theme, ThemeData darkTheme}) appearanceThemes(
  SettingsState settings,
  String? mode,
  YaruThemeData fallback,
) {
  final accent = appearancePowerAccent(settings, mode);
  return (
    theme: accent == null
        ? fallback.theme
        : createYaruLightTheme(primaryColor: accent.color),
    darkTheme: accent == null
        ? fallback.darkTheme
        : createYaruDarkTheme(primaryColor: accent.color),
  );
}
