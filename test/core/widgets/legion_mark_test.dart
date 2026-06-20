import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/widgets/legion_mark.dart';

void main() {
  testWidgets('sizes itself to the given square dimension', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: LegionMark(color: Color(0xFF8056D6), size: 40)),
      ),
    );

    expect(tester.getSize(find.byType(LegionMark)), const Size(40, 40));
  });

  testWidgets('paints without throwing for both antenna states', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: LegionMark(
            color: Color(0xFFEC5F2A),
            size: 24,
            showAntenna: false,
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(LegionMark), findsOneWidget);
  });

  group('LegionMarkPainter.shouldRepaint', () {
    const base = LegionMarkPainter(color: Color(0xFF8056D6), showAntenna: true);

    test('is false for an identical painter', () {
      expect(
        base.shouldRepaint(
          const LegionMarkPainter(color: Color(0xFF8056D6), showAntenna: true),
        ),
        isFalse,
      );
    });

    test('is true when the color changes', () {
      expect(
        base.shouldRepaint(
          const LegionMarkPainter(color: Color(0xFF12A4B8), showAntenna: true),
        ),
        isTrue,
      );
    });

    test('is true when the antenna toggles', () {
      expect(
        base.shouldRepaint(
          const LegionMarkPainter(color: Color(0xFF8056D6), showAntenna: false),
        ),
        isTrue,
      );
    });
  });
}
