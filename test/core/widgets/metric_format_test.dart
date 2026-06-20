import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/widgets/metric_format.dart';

void main() {
  group('formatMetric', () {
    test('returns the placeholder for null or NaN', () {
      expect(formatMetric(null), '—');
      expect(formatMetric(double.nan), '—');
      expect(formatMetric(null, placeholder: 'n/a'), 'n/a');
    });

    test('formats to the requested fraction digits', () {
      expect(formatMetric(72), '72');
      expect(formatMetric(72.456, fractionDigits: 1), '72.5');
      expect(formatMetric(8.2, fractionDigits: 2), '8.20');
    });
  });

  group('metricFraction', () {
    test('returns the normalized 0..1 position within the range', () {
      expect(metricFraction(50, 0, 100), 0.5);
      expect(metricFraction(30, 20, 40), closeTo(0.5, 1e-9));
    });

    test('clamps out-of-range values', () {
      expect(metricFraction(-10, 0, 100), 0.0);
      expect(metricFraction(150, 0, 100), 1.0);
    });

    test('returns null for unavailable values or a degenerate range', () {
      expect(metricFraction(null, 0, 100), isNull);
      expect(metricFraction(double.nan, 0, 100), isNull);
      expect(metricFraction(50, 100, 100), isNull);
      expect(metricFraction(50, 100, 0), isNull);
    });
  });

  group('isMetricCritical', () {
    test('is true only when value meets or exceeds the threshold', () {
      expect(isMetricCritical(90, 90), isTrue);
      expect(isMetricCritical(95, 90), isTrue);
      expect(isMetricCritical(89.9, 90), isFalse);
    });

    test('is false when value or threshold is absent', () {
      expect(isMetricCritical(null, 90), isFalse);
      expect(isMetricCritical(95, null), isFalse);
    });
  });
}
