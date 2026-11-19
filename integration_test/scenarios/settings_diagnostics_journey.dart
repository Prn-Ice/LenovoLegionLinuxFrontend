import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/diagnostics/view/diagnostics_page.dart';
import 'package:legion_frontend/features/settings/view/settings_page.dart';
import 'package:window_manager/window_manager.dart';

import '../support/journey.dart';
import '../support/safe_app.dart';
import '../support/safe_settings.dart';

Future<void> openSettings(WidgetTester tester) async {
  final settings = find.byTooltip('Settings').hitTestable();
  final labelledSettings = find.text('Settings').hitTestable();
  await waitFor(
    tester,
    () =>
        settings.evaluate().isNotEmpty ||
        labelledSettings.evaluate().isNotEmpty,
    description: 'Settings navigation',
  );
  await tester.tap(
    settings.evaluate().isNotEmpty ? settings.first : labelledSettings.first,
  );
  await waitFor(
    tester,
    () => find.byType(SettingsPage).evaluate().isNotEmpty,
    description: 'Settings page',
  );
  await tester.pumpAndSettle();
}

Future<void> _openDiagnostics(WidgetTester tester) async {
  final button = find.text('Diagnostics and export');
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await waitFor(
    tester,
    () =>
        find.byType(DiagnosticsPage).evaluate().isNotEmpty &&
        find.text('Environment').evaluate().isNotEmpty,
    description: 'diagnostics page',
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Settings compact navigation and diagnostics copy use synthetic data',
    (tester) async {
      final app = await SafeApp.create();
      Rect? originalBounds;
      addTearDown(() async {
        final bounds = originalBounds;
        if (bounds != null) {
          await windowManager.setBounds(bounds, animate: false);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await app.dispose();
      });

      await app.launch(additionalOverrides: safeSettingsOverrides());
      await windowManager.ensureInitialized();
      originalBounds = await windowManager.getBounds();
      await windowManager.setBounds(
        null,
        position: originalBounds.topLeft,
        size: const Size(420, 700),
        animate: false,
      );
      await tester.pumpAndSettle();
      final narrowBounds = await windowManager.getBounds();
      expect(narrowBounds.width, lessThanOrEqualTo(500));
      await openSettings(tester);

      // Navigation state must remain usable when the Settings page is revisited.
      final dashboard = find.byTooltip('Dashboard').hitTestable();
      await waitFor(
        tester,
        () => dashboard.evaluate().isNotEmpty,
        description: 'Dashboard navigation',
      );
      await tester.tap(dashboard.first);
      await waitFor(
        tester,
        () => find.text('Dashboard').evaluate().isNotEmpty,
        description: 'Dashboard page after narrow navigation',
      );
      await openSettings(tester);

      // The boot-logo button opens an OS-owned file picker. This journey does
      // not launch or automate that dialog; cancellation needs an injectable
      // picker boundary before it can be covered safely.
      await _openDiagnostics(tester);

      final copy = find.text('Copy report JSON');
      await Clipboard.setData(
        const ClipboardData(text: 'native copy sentinel'),
      );
      await waitFor(
        tester,
        () => copy.evaluate().isNotEmpty,
        description: 'diagnostics copy action',
      );
      await tester.ensureVisible(copy);
      await tester.pumpAndSettle();
      await tester.tap(copy);
      await waitFor(
        tester,
        () => find.text('Copied').evaluate().isNotEmpty,
        description: 'diagnostics copy feedback',
      );

      final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
      expect(clipboard?.text, isNotNull);
      expect(clipboard!.text, contains('"schema_version"'));
      expect(clipboard.text, contains('"hardware_model": "Journey fixture"'));
      expect(clipboard.text, contains('"cli_path": "<configured-cli>"'));
      expect(clipboard.text, isNot(contains('/home/')));
      expect(app.authorizations, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
