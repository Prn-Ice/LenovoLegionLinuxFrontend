import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';

import '../../../core/theme/legion_accent.dart';

/// Power mode owns the app accent. Older manual preferences are only a fallback
/// while the observed mode is unavailable, regardless of the legacy follow flag.
({ThemeData theme, ThemeData darkTheme}) appearanceThemes(
  String? mode,
  YaruThemeData fallback,
) {
  final accent = LegionAccent.fromPowerModeValue(mode?.trim());
  return (
    theme: accent == null
        ? fallback.theme
        : createYaruLightTheme(primaryColor: accent.color),
    darkTheme: accent == null
        ? fallback.darkTheme
        : createYaruDarkTheme(primaryColor: accent.color),
  );
}
