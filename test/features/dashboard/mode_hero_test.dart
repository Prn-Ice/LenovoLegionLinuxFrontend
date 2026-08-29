import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/dashboard/widgets/mode_hero.dart';

Future<void> _pump(WidgetTester tester, Widget child) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

void main() {
  const accent = Color(0xFFEC5F2A);

  testWidgets('shows mode cards and the accent banner', (tester) async {
    await _pump(
      tester,
      ModeHero(
        accent: accent,
        availableModes: const ['quiet', 'balanced', 'performance'],
        selectedMode: 'performance',
        isApplying: false,
        onModeSelected: (_) {},
      ),
    );

    expect(find.text('Quiet'), findsOneWidget);
    expect(find.text('Balanced'), findsOneWidget);
    // 'Performance' appears in both the chip and the banner.
    expect(find.textContaining('Performance'), findsWidgets);
  });

  testWidgets('maps kernel profile names to user-facing mode semantics', (
    tester,
  ) async {
    await _pump(
      tester,
      ModeHero(
        accent: accent,
        availableModes: const ['low-power'],
        selectedMode: 'low-power',
        isApplying: false,
        onModeSelected: (_) {},
      ),
    );

    expect(find.textContaining('Quiet'), findsWidgets);
    expect(find.text('Keeps heat, noise, and power use low.'), findsOneWidget);
  });

  testWidgets('shows a message when there are no writable modes', (
    tester,
  ) async {
    await _pump(
      tester,
      const ModeHero(
        accent: accent,
        availableModes: [],
        selectedMode: null,
        isApplying: false,
        onModeSelected: null,
      ),
    );

    expect(find.text('No writable power modes available.'), findsOneWidget);
  });
}
