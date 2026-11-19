import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:legion_frontend/core/widgets/app_shell_components.dart';
import 'package:legion_frontend/features/automation/view/automation_page.dart';
import 'package:legion_frontend/features/battery/view/battery_page.dart';
import 'package:legion_frontend/features/dashboard/view/dashboard_page.dart';
import 'package:legion_frontend/features/dgpu/view/dgpu_page.dart';
import 'package:legion_frontend/features/fans/view/fans_page.dart';
import 'package:legion_frontend/features/lighting/view/lighting_page.dart';
import 'package:legion_frontend/features/navigation/models/app_section.dart';
import 'package:legion_frontend/features/navigation/providers/navigation_provider.dart';
import 'package:legion_frontend/features/power/view/power_page.dart';
import 'package:legion_frontend/features/settings/view/settings_page.dart';

import '../support/journey.dart';
import '../support/safe_app.dart';
import '../support/safe_graphics.dart';
import '../support/safe_lighting.dart';
import '../support/safe_settings.dart';

void main() {
  testWidgets('all main sections render using isolated hardware fixtures', (
    tester,
  ) async {
    final app = await SafeApp.create(includeFanFixture: true);
    final lighting = SafeLighting(app);
    final graphics = SafeGraphicsFixture();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await app.dispose();
    });
    await app.launch(
      additionalOverrides: [
        ...lighting.overrides,
        ...safeGraphicsOverrides(graphics),
        ...safeSettingsOverrides(),
      ],
    );
    for (final section in AppSection.values) {
      final navigation = find.text(section.label).hitTestable();
      await waitFor(
        tester,
        () => navigation.evaluate().isNotEmpty,
        description: '${section.label} navigation',
      );
      await tester.tap(navigation.first);
      await tester.pumpAndSettle();
      final type = switch (section) {
        AppSection.dashboard => DashboardPage,
        AppSection.power => PowerPage,
        AppSection.fans => FansPage,
        AppSection.battery => BatteryPage,
        AppSection.lighting => LightingPage,
        AppSection.dgpu => DgpuPage,
        AppSection.automation => AutomationPage,
        AppSection.settings => SettingsPage,
      };
      final content = switch (section) {
        AppSection.dashboard => 'Battery health',
        AppSection.power => 'Power limits',
        AppSection.fans => 'Precise point controls',
        AppSection.battery => 'Conservation mode',
        AppSection.lighting => 'PROFILES',
        AppSection.dgpu => 'Graphics mode',
        AppSection.automation => 'Keyboard profiles by power mode',
        AppSection.settings => 'Appearance',
      };
      await waitFor(
        tester,
        () =>
            find.byType(type).evaluate().length == 1 &&
            find.text(content).evaluate().isNotEmpty,
        description: '${section.label} page',
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(type)),
      );
      expect(container.read(navigationBlocProvider).section, section);
      expect(find.byType(AppErrorDialog), findsNothing);
      expect(tester.takeException(), isNull);
    }
    expect(app.authorizations, 0);
    expect(graphics.authorizations, 0);
    expect(graphics.requests, isEmpty);
    expect(app.requests, isEmpty);
    expect(app.fanPresetRequests, isEmpty);
    expect(app.fanCurveRequests, isEmpty);
    expect(app.powerLimitRequests, isEmpty);
  });
}
