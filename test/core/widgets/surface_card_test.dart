import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/widgets/surface_card.dart';
import 'package:yaru/yaru.dart';

void main() {
  testWidgets('uses redesign light defaults', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.light),
        home: const SurfaceCard(child: Text('content')),
      ),
    );

    final container = tester.widget<YaruBorderContainer>(
      find.byType(YaruBorderContainer),
    );
    expect(container.color, const Color(0xffFFFFFF));
    expect(container.border, Border.all(color: const Color(0xffE6E2DD)));
  });

  testWidgets('retains dark default styling', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: const SurfaceCard(child: Text('content')),
      ),
    );

    final container = tester.widget<YaruBorderContainer>(
      find.byType(YaruBorderContainer),
    );
    expect(container.color, isNot(const Color(0xffFFFFFF)));
    expect(container.border, isA<Border>());
    expect((container.border! as Border).top.color.a, closeTo(0.06, 0.001));
  });

  testWidgets('forwards surface overrides to YaruBorderContainer', (
    tester,
  ) async {
    const padding = EdgeInsets.symmetric(horizontal: 8, vertical: 12);
    const color = Color(0xff123456);
    const border = Border.fromBorderSide(
      BorderSide(color: Color(0xffabcdef), width: 2),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SurfaceCard(
          padding: padding,
          color: color,
          border: border,
          child: const Text('content'),
        ),
      ),
    );

    final container = tester.widget<YaruBorderContainer>(
      find.byType(YaruBorderContainer),
    );
    expect(container.padding, padding);
    expect(container.color, color);
    expect(container.border, border);
    expect(container.borderRadius, BorderRadius.circular(13));
    expect(find.text('content'), findsOneWidget);
  });
}
