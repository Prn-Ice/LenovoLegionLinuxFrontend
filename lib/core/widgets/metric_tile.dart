import 'package:flutter/material.dart';

import 'metric_format.dart';

/// A compact metric readout: a label, a formatted tabular value with optional
/// unit, and an optional thin progress bar. Used for utilisation bars
/// (CPU/GPU/RAM) and dense metric rows (Wh, cycles, discharge rate, …).
///
/// Mirrors [MetricGauge]'s severity behavior: the value and bar use [accent]
/// (or the theme primary) normally and the error color past [criticalThreshold].
class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.label,
    required this.value,
    this.unit = '',
    this.min = 0,
    this.max = 100,
    this.accent,
    this.criticalThreshold,
    this.showBar = true,
    this.fractionDigits = 0,
  });

  final String label;
  final double? value;
  final String unit;
  final double min;
  final double max;
  final Color? accent;
  final double? criticalThreshold;
  final bool showBar;
  final int fractionDigits;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final fraction = metricFraction(value, min, max);
    final critical = isMetricCritical(value, criticalThreshold);
    final barColor = critical ? scheme.error : (accent ?? scheme.primary);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: formatMetric(value, fractionDigits: fractionDigits),
                    style: textTheme.titleSmall?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                      fontWeight: FontWeight.w700,
                      color: critical ? scheme.error : null,
                    ),
                  ),
                  if (unit.isNotEmpty)
                    TextSpan(
                      text: unit,
                      style: textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        if (showBar) ...[
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fraction ?? 0,
              minHeight: 7,
              backgroundColor: scheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
            ),
          ),
        ],
      ],
    );
  }
}
