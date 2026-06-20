import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/widgets/responsive_card_grid.dart';

void main() {
  group('responsiveColumnCount (minCardWidth 320, spacing 16)', () {
    int columns(double width) => responsiveColumnCount(width, 320, 16);

    test('fits one column at exactly one card width', () {
      expect(columns(320), 1);
    });

    test('needs room for the inter-card gap before adding a column', () {
      expect(columns(655), 1); // 2 cards + gap = 656, so 655 is still 1
      expect(columns(656), 2);
    });

    test('scales up with width', () {
      expect(columns(1000), 3);
      expect(columns(1350), 4);
    });

    test('never drops below one column', () {
      expect(columns(100), 1);
      expect(columns(0), 1);
    });
  });

  testWidgets('lays out every child without overflowing', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 700,
            child: ResponsiveCardGrid(
              children: List.generate(
                4,
                (i) => Text('card$i', key: ValueKey('card$i')),
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    for (var i = 0; i < 4; i++) {
      expect(find.byKey(ValueKey('card$i')), findsOneWidget);
    }
  });
}
