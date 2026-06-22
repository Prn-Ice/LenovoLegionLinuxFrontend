import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/lighting/view/keyboard_preview.dart';

void main() {
  testWidgets('a key painted white renders a white fill (not transparent)', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: KeyboardPreview(
            leds: const ['Key: Escape'],
            keyColors: const [Color(0xFFFFFFFF)],
            enabled: true,
            onPaint: (_) {},
            onErase: (_) {},
            onPick: (_) {},
          ),
        ),
      ),
    );

    final whiteFills = tester
        .widgetList<Container>(find.byType(Container))
        .where((c) {
          final d = c.decoration;
          return d is BoxDecoration && d.color == const Color(0xFFFFFFFF);
        });
    expect(whiteFills, isNotEmpty);
  });
}
