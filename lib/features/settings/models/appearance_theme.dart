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
  // White mode indicators need a dark interaction color on light surfaces.
  final lightAccent = accent == LegionAccent.balanced
      ? const Color(0xFF555555)
      : accent?.color;
  // Yaru interprets pure white as high contrast, including window controls and
  // dividers. Balanced needs a white-looking accent with normal dark chrome.
  final darkAccent = accent == LegionAccent.balanced
      ? const Color(0xFFFAFAFA)
      : accent?.color;
  return (
    theme: accent == null
        ? fallback.theme
        : createYaruLightTheme(primaryColor: lightAccent!),
    darkTheme: accent == null
        ? fallback.darkTheme
        : createYaruDarkTheme(primaryColor: darkAccent!),
  );
}
