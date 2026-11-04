import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/theme/legion_accent.dart';
import 'package:legion_frontend/features/dashboard/widgets/mode_hero.dart';
import 'package:legion_frontend/features/settings/models/appearance_theme.dart';
import 'package:yaru/yaru.dart';

Future<void> _pump(WidgetTester tester, Widget child) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

void main() {
  const accent = Color(0xFFEC5F2A);

  for (final mode in LegionAccent.all) {
    for (final brightness in Brightness.values) {
      testWidgets('${mode.label} selected chip has readable $brightness text', (
        tester,
      ) async {
        final themes = appearanceThemes(mode.mode.name, const YaruThemeData());
        final theme = brightness == Brightness.dark
            ? themes.darkTheme
            : themes.theme;
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: ModeHero(
                accent: theme.colorScheme.primary,
                availableModes: const [
                  'quiet',
                  'balanced',
                  'performance',
                  'custom',
                ],
                selectedMode: mode.mode.name,
                isApplying: false,
                onModeSelected: (_) {},
              ),
            ),
          ),
        );
        final label = find.descendant(
          of: find.byWidgetPredicate(
            (widget) => widget is ChoiceChip && widget.selected,
          ),
          matching: find.text(mode.label),
        );
        final paragraph = tester.renderObject<RenderParagraph>(label);
        final foreground = paragraph.text.style!.color!;
        final background = Color.alphaBlend(
          theme.colorScheme.primary.withValues(alpha: 0.2),
          theme.colorScheme.surface,
        );
        final luminances = [
          foreground.computeLuminance(),
          background.computeLuminance(),
        ]..sort();
        expect(
          (luminances.last + 0.05) / (luminances.first + 0.05),
          greaterThanOrEqualTo(4.5),
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('shows Yaru mode chips and the accent banner', (tester) async {
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
    expect(find.byType(ChoiceChip), findsNWidgets(3));

    final selectedChip = find.ancestor(
      of: find.text('Performance').first,
      matching: find.byType(ChoiceChip),
    );
    final chipContext = tester.element(selectedChip);
    final scheme = Theme.of(chipContext).colorScheme;
    expect(
      ChipTheme.of(chipContext).selectedColor,
      Color.alphaBlend(accent.withValues(alpha: 0.2), scheme.surface),
    );
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
