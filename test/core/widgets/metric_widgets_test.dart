import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/widgets/metric_gauge.dart';
import 'package:legion_frontend/core/widgets/metric_tile.dart';

Future<void> _pump(WidgetTester tester, Widget child) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  const accent = Color(0xFF3A9D4F);

  testWidgets('MetricGauge shows the value, unit and label', (tester) async {
    await _pump(
      tester,
      const MetricGauge(
        value: 72,
        min: 0,
        max: 100,
        label: 'CPU',
        unit: '°C',
        accent: accent,
      ),
    );

    expect(find.textContaining('72'), findsOneWidget);
    expect(find.textContaining('°C'), findsOneWidget);
    expect(find.text('CPU'), findsOneWidget);
  });

  testWidgets('MetricGauge renders the placeholder for a null value', (
    tester,
  ) async {
    await _pump(
      tester,
      const MetricGauge(
        value: null,
        min: 0,
        max: 100,
        label: 'GPU',
        accent: accent,
      ),
    );

    expect(find.textContaining('—'), findsOneWidget);
  });

  testWidgets('MetricTile renders label, value and a bar', (tester) async {
    await _pump(tester, const MetricTile(label: 'RAM', value: 40));

    expect(find.text('RAM'), findsOneWidget);
    expect(find.textContaining('40'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('MetricTile can hide the bar and handles a null value', (
    tester,
  ) async {
    await _pump(
      tester,
      const MetricTile(label: 'Cycles', value: null, showBar: false),
    );

    expect(find.textContaining('—'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  group('GaugeArcPainter.shouldRepaint', () {
    const base = GaugeArcPainter(
      fraction: 0.5,
      color: accent,
      trackColor: Color(0xFFEEEEEE),
    );

    test('is false for an identical painter', () {
      expect(
        base.shouldRepaint(
          const GaugeArcPainter(
            fraction: 0.5,
            color: accent,
            trackColor: Color(0xFFEEEEEE),
          ),
        ),
        isFalse,
      );
    });

    test('is true when the fill fraction changes', () {
      expect(
        base.shouldRepaint(
          const GaugeArcPainter(
            fraction: 0.7,
            color: accent,
            trackColor: Color(0xFFEEEEEE),
          ),
        ),
        isTrue,
      );
    });
  });
}
