import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/lighting/models/keyboard_layout.dart';
import 'package:legion_frontend/features/lighting/view/keyboard_preview.dart';

void main() {
  testWidgets('uses the supplied model layout and maps its key interaction', (
    tester,
  ) async {
    int? painted;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KeyboardPreview(
            layout: const KeyboardLayout(
              rows: [
                KeyRow(main: [KeyCap('Fixture key', 'Test')]),
              ],
              neonLeds: [],
              mainUnits: 1,
              navUnits: 0,
              numpadUnits: 0,
              groupGap: 0,
            ),
            leds: const ['Unshown key', 'Fixture key'],
            keyColors: const [Colors.black, Colors.white],
            enabled: true,
            onPaint: (index) => painted = index,
            onErase: (_) {},
            onPick: (_) {},
          ),
        ),
      ),
    );
    expect(find.text('Esc'), findsNothing);
    await tester.tap(find.text('Test'));
    expect(painted, 1);
    expect(tester.takeException(), isNull);
  });

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
