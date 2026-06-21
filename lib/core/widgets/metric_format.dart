// Pure helpers for telemetry metric rendering.
//
// Kept separate from the gauge/tile widgets so the value math is unit-tested
// without pumping widgets. All accept nullable values because sensors are
// frequently unavailable.

/// Monospace family for telemetry numbers, matching the design (Ubuntu Mono).
/// Uses the copy the Yaru package bundles — always in the build — referenced
/// together with [kMonoFontPackage].
const String kMonoFontFamily = 'UbuntuMono';
const String kMonoFontPackage = 'yaru';

/// Formats [value] to [fractionDigits] decimals, returning [placeholder] when
/// the value is absent or not a number.
String formatMetric(
  double? value, {
  int fractionDigits = 0,
  String placeholder = '—',
}) {
  if (value == null || value.isNaN) return placeholder;
  return value.toStringAsFixed(fractionDigits);
}

/// The normalized `0..1` position of [value] within `[min, max]`, clamped to
/// the range. Returns null when [value] is unavailable or the range is
/// degenerate (`max <= min`).
double? metricFraction(double? value, double min, double max) {
  if (value == null || value.isNaN || max <= min) return null;
  return ((value - min) / (max - min)).clamp(0.0, 1.0);
}

/// Whether [value] has reached the critical [threshold]. False when either is
/// absent.
bool isMetricCritical(double? value, double? threshold) =>
    value != null && threshold != null && value >= threshold;
