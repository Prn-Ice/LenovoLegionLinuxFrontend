import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/theme/legion_accent.dart';
import 'package:legion_frontend/features/platform_surfaces/models/platform_event.dart';
import 'package:legion_frontend/features/platform_surfaces/widgets/platform_osd.dart';

void main() {
  Future<void> showOsd(
    WidgetTester tester,
    PlatformEvent event, {
    Brightness brightness = Brightness.light,
    double textScale = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Center(
            child: SizedBox(width: 240, child: PlatformOsd(event: event)),
          ),
        ),
      ),
    );
  }

  testWidgets(
    'uses confirmed mode accent and exposes one readable announcement',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await showOsd(
        tester,
        const PowerModeChanged(
          label: 'Performance',
          powerModeValue: 'performance',
        ),
      );
      expect(find.text('Performance'), findsOneWidget);
      expect(find.bySemanticsLabel('Power mode: Performance'), findsOneWidget);
      final icon = tester.widget<Icon>(find.byType(Icon));
      expect(icon.color, LegionAccent.performance.color);
      semantics.dispose();
    },
  );

  testWidgets('brightness is determinate only for valid values', (
    tester,
  ) async {
    await showOsd(tester, const KeyboardBrightnessChanged(fraction: 0.75));
    expect(find.text('75%'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      0.75,
    );
    for (final value in [null, double.nan, double.infinity, -0.1, 1.1]) {
      await showOsd(tester, KeyboardBrightnessChanged(fraction: value));
      expect(find.text('Unavailable'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    }
  });

  testWidgets(
    'unknown values and long automation remain readable in dark narrow layout',
    (tester) async {
      await showOsd(
        tester,
        const FanBoostChanged(enabled: null),
        brightness: Brightness.dark,
        textScale: 1.8,
      );
      expect(find.text('Unavailable'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await showOsd(
        tester,
        const AutomationChanged(
          description:
              'A long automation rule changed the active power profile after a game was detected.',
        ),
        brightness: Brightness.dark,
        textScale: 1.8,
      );
      expect(find.textContaining('A long automation'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
