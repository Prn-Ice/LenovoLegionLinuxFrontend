import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:legion_frontend/features/lighting/view/lighting_page.dart';

import '../support/journey.dart';
import '../support/safe_app.dart';
import '../support/safe_spectrum.dart';

void main() {
  testWidgets(
    'paints native Spectrum and stops software animation on dispose',
    (tester) async {
      final app = await SafeApp.create();
      final spectrum = await SafeSpectrum.create(app);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await app.dispose();
      });
      await app.launch(additionalOverrides: spectrum.overrides);
      expect(spectrum.service.inspectHidraw().outcome.name, 'supported');

      await waitFor(
        tester,
        () => find.text('Lighting').hitTestable().evaluate().isNotEmpty,
        description: 'Lighting navigation control',
      );
      await tester.tap(find.text('Lighting').hitTestable().first);
      await waitFor(
        tester,
        () =>
            find.byType(LightingPage).evaluate().isNotEmpty &&
            find.text('Legion Keyboard').evaluate().isNotEmpty &&
            find.textContaining('real-time').evaluate().isNotEmpty,
        description:
            'native Spectrum identity selected by the real discovery path',
      );
      expect(spectrum.openRgbProbes, [
        ['--list-devices'],
      ]);
      await tester.pumpAndSettle();

      final colorField = find.byWidgetPredicate(
        (widget) => widget is TextField && widget.decoration?.prefixText == '#',
      );
      await tester.ensureVisible(colorField);
      await tester.enterText(colorField, '12A4EF');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await waitFor(
        tester,
        () => spectrum.io.reports.length >= 4,
        description: 'native Spectrum feature reports after a UI paint',
      );
      final frame = spectrum.io.reports.firstWhere(
        (report) =>
            report[1] == 0xa1 &&
            report[4] == 0x01 &&
            report[5] == 0x00 &&
            report[6] == 0x12 &&
            report[7] == 0x90 &&
            report[8] == 0xef,
      );
      expect(frame.sublist(0, 4), [7, 0xa1, 0xc0, 3]);
      expect(frame.sublist(4, 6), [1, 0]);
      // UI #12A4EF at 100% uses the calibrated 0.88 green gain:
      // round(0xA4 * .88) = 0x90; the sum is below the power cap.
      expect(frame.sublist(6, 9), [0x12, 0x90, 0xef]);
      expect(spectrum.openRgbProbes, [
        ['--list-devices'],
      ]);

      final framesBeforePulse = spectrum.io.reports
          .where((report) => report[1] == 0xa1)
          .length;
      await tester.ensureVisible(find.text('Pulse'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pulse'));
      await waitFor(
        tester,
        () =>
            spectrum.io.reports.where((report) => report[1] == 0xa1).length >=
            framesBeforePulse + 3,
        description:
            'multiple software animation frames through native Spectrum',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await waitFor(
        tester,
        () => spectrum.io.closeCount == 1,
        description: 'native HID closed during provider disposal',
      );
      final writesAfterClose = spectrum.io.reports.length;
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(spectrum.io.closeCount, 1);
      expect(spectrum.io.reports.length, writesAfterClose);
      await tester.pump(const Duration(milliseconds: 500));
      expect(spectrum.io.closeCount, 1);
      expect(spectrum.io.reports.length, writesAfterClose);
      expect(spectrum.io.openCount, 1);
    },
  );
}
