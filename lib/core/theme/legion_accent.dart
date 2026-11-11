import 'package:flutter/material.dart';

/// Mode colors approximated from photos of a Legion laptop's power button.
/// [custom] includes the `balanced-performance` profile, shown as "Custom".
enum LegionAccentMode { quiet, balanced, performance, custom }

/// Colors and labels used to show power modes.
///
/// Does not depend on feature code. Pass a platform profile to
/// [fromPowerModeValue]; unknown profiles return null.
class LegionAccent {
  const LegionAccent({
    required this.mode,
    required this.color,
    required this.label,
  });

  final LegionAccentMode mode;
  final Color color;
  final String label;

  static const LegionAccent quiet = LegionAccent(
    mode: LegionAccentMode.quiet,
    color: Color(0xFF1677FF),
    label: 'Quiet',
  );

  static const LegionAccent balanced = LegionAccent(
    mode: LegionAccentMode.balanced,
    color: Color(0xFFFFFFFF),
    label: 'Balanced',
  );

  static const LegionAccent performance = LegionAccent(
    mode: LegionAccentMode.performance,
    color: Color(0xFFFF6675),
    label: 'Performance',
  );

  static const LegionAccent custom = LegionAccent(
    mode: LegionAccentMode.custom,
    color: Color(0xFFC65CFF),
    label: 'Custom',
  );

  static const List<LegionAccent> all = [quiet, balanced, performance, custom];

  /// Maps a platform power-profile value (`PowerMode.value`) to its accent.
  ///
  /// Returns null for unknown or absent values so callers can fall back to the
  /// theme's primary color rather than guessing an accent.
  static LegionAccent? fromPowerModeValue(String? value) {
    switch (value) {
      case 'quiet':
      case 'low-power':
      case 'power-saver':
        return quiet;
      case 'balanced':
        return balanced;
      case 'performance':
      case 'max-power':
        return performance;
      case 'balanced-performance':
      case 'custom':
        return custom;
      default:
        return null;
    }
  }

  /// An opaque, softly tinted background — the accent blended over the theme
  /// surface at [alpha]. Safe to use directly as a card/panel background.
  Color soft(ColorScheme scheme, {double alpha = 0.14}) =>
      Color.alphaBlend(color.withValues(alpha: alpha), scheme.surface);

  /// The foreground color to use on top of [soft] (the accent itself).
  Color onSoft(ColorScheme scheme) => color;
}
