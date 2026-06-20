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

  testWidgets('shows mode chips and the accent description banner', (
    tester,
  ) async {
    await _pump(
      tester,
      ModeHero(
        accent: accent,
        label: 'Performance',
        description: 'Full power',
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
    expect(find.textContaining('Full power'), findsOneWidget);
  });

  testWidgets('maps balanced-performance to a Custom chip', (tester) async {
    await _pump(
      tester,
      ModeHero(
        accent: accent,
        label: 'Custom',
        description: 'User tuned',
        availableModes: const ['balanced-performance'],
        selectedMode: 'balanced-performance',
        isApplying: false,
        onModeSelected: (_) {},
      ),
    );

    expect(find.text('Custom'), findsWidgets);
  });

  testWidgets('shows a message when there are no writable modes', (
    tester,
  ) async {
    await _pump(
      tester,
      const ModeHero(
        accent: accent,
        label: 'Unknown',
        description: '',
        availableModes: [],
        selectedMode: null,
        isApplying: false,
        onModeSelected: null,
      ),
    );

    expect(find.text('No writable power modes available.'), findsOneWidget);
  });
}
