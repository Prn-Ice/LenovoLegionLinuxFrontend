import 'package:flutter/material.dart';

/// The four mode accents from the Yaru handoff. [custom] covers manual/custom
/// tuning (including the `balanced-performance` platform profile, which the app
/// already surfaces as "Custom").
enum LegionAccentMode { quiet, balanced, performance, custom }

/// A single source of truth for the handoff's mode-accent styling.
///
/// Kept dependency-free of the `features/` layer: callers map their own power
/// mode to an accent via [fromPowerModeValue] (pass `PowerMode.value`), and fall
/// back to `Theme.of(context).colorScheme.primary` when it returns null.
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
    color: Color(0xFF12A4B8),
    label: 'Quiet',
  );

  static const LegionAccent balanced = LegionAccent(
    mode: LegionAccentMode.balanced,
    color: Color(0xFF3A9D4F),
    label: 'Balanced',
  );

  static const LegionAccent performance = LegionAccent(
    mode: LegionAccentMode.performance,
    color: Color(0xFFEC5F2A),
    label: 'Performance',
  );

  static const LegionAccent custom = LegionAccent(
    mode: LegionAccentMode.custom,
    color: Color(0xFF8056D6),
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
