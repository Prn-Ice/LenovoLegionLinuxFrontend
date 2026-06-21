import 'package:flutter/material.dart';

import 'metric_format.dart';

/// Mono telemetry text roles, all in the Yaru-bundled Ubuntu Mono
/// ([kMonoFontFamily] + [kMonoFontPackage]). Yaru's sans `TextTheme` covers
/// every other piece of text; these name the one exception the design makes —
/// the numbers — in a single place.
///
/// The roles are used directly at call sites (`style: monoMetaStyle(scheme)`).
/// Color-driven roles take their [Color]/[ColorScheme] as an argument rather
/// than relying on `.copyWith`, which can silently drop the font package and
/// fall back to sans.

/// Right-aligned stat figure (kernel / uptime, 14px bold). Inherits the ambient
/// text color.
const TextStyle monoStatValueStyle = TextStyle(
  fontFamily: kMonoFontFamily,
  package: kMonoFontPackage,
  fontSize: 14,
  fontWeight: FontWeight.w700,
);

/// Large gauge number, sized ~0.23× the [gaugeSize] with tabular figures so it
/// doesn't jitter as digits change. [color] is passed so a critical reading can
/// flip to the error color.
TextStyle monoGaugeStyle(double gaugeSize, Color color) => TextStyle(
  fontFamily: kMonoFontFamily,
  package: kMonoFontPackage,
  fontSize: gaugeSize * 0.23,
  fontWeight: FontWeight.w700,
  height: 1,
  fontFeatures: const [FontFeature.tabularFigures()],
  color: color,
);

/// Usage-bar value (12px medium, tabular). [color] flips to error when critical.
TextStyle monoBarStyle(Color color) => TextStyle(
  fontFamily: kMonoFontFamily,
  package: kMonoFontPackage,
  fontSize: 12,
  fontWeight: FontWeight.w500,
  fontFeatures: const [FontFeature.tabularFigures()],
  color: color,
);

/// Unit suffix trailing a usage-bar value (12px, 50% muted).
TextStyle monoUnitStyle(ColorScheme scheme) => TextStyle(
  fontFamily: kMonoFontFamily,
  package: kMonoFontPackage,
  fontSize: 12,
  color: scheme.onSurface.withValues(alpha: 0.5),
);

/// Device product / BIOS / CPU meta line (12px, 56% muted).
TextStyle monoMetaStyle(ColorScheme scheme) => TextStyle(
  fontFamily: kMonoFontFamily,
  package: kMonoFontPackage,
  fontSize: 12,
  color: scheme.onSurface.withValues(alpha: 0.56),
);

/// Mode-banner facts line, e.g. the active power limits (13px, 70% muted).
TextStyle monoFactStyle(ColorScheme scheme) => TextStyle(
  fontFamily: kMonoFontFamily,
  package: kMonoFontPackage,
  fontSize: 13,
  color: scheme.onSurface.withValues(alpha: 0.7),
);
