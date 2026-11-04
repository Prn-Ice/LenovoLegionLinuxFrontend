import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:legion_frontend/core/widgets/surface_card.dart';
import 'package:legion_frontend/features/battery/view/battery_page.dart';
import 'package:yaru/yaru.dart';

import 'support/safe_app.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('cancel then apply battery health and read it on Battery', (
    tester,
  ) async {
    final app = await SafeApp.create();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await app.dispose();
    });
    await app.launch();

    final healthSwitch = switchInCard('Battery health');
    await waitFor(tester, () => healthSwitch.evaluate().isNotEmpty);
    await tester.ensureVisible(healthSwitch);
    await tester.pumpAndSettle();
    expect(tester.widget<YaruSwitch>(healthSwitch).value, isFalse);

    await tester.tap(healthSwitch);
    await tester.pumpAndSettle();
    expect(find.text('Set battery conservation'), findsOneWidget);
    expect(app.writes, isEmpty);
    expect(app.authorizations, 0);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.widget<YaruSwitch>(healthSwitch).value, isFalse);
    expect(app.writes, isEmpty);
    expect(app.authorizations, 0);

    await tester.tap(healthSwitch);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    await waitFor(tester, () => tester.widget<YaruSwitch>(healthSwitch).value);
    expect(app.writes, [true]);
    expect(app.authorizations, 1);
    expect(await app.conservationFile.readAsString(), '1\n');

    // Use the actual navigation control, including the compact rail variant.
    final batteryNavigation = find.text('Battery').hitTestable();
    await tester.tap(
      batteryNavigation.evaluate().isNotEmpty
          ? batteryNavigation.first
          : find.byTooltip('Battery'),
    );
    await waitFor(tester, () => find.byType(BatteryPage).evaluate().isNotEmpty);
    final conservationSwitch = switchInCard('Conservation mode');
    await waitFor(tester, () => conservationSwitch.evaluate().isNotEmpty);
    await tester.ensureVisible(conservationSwitch);
    await tester.pumpAndSettle();
    // The sidebar keeps Battery's earlier snapshot alive. Explicit refresh is
    // the current cross-page readback path; automatic invalidation is lllf-kmd.
    await tester.tap(find.byTooltip('Refresh'));
    await waitFor(
      tester,
      () => tester.widget<YaruSwitch>(conservationSwitch).value,
    );
    expect(tester.widget<YaruSwitch>(conservationSwitch).value, isTrue);
    expect(app.writes, [true]);
    expect(tester.takeException(), isNull);
  });
}

Finder switchInCard(String label) => find.descendant(
  of: find.ancestor(of: find.text(label), matching: find.byType(SurfaceCard)),
  matching: find.byType(YaruSwitch),
);

Future<void> waitFor(WidgetTester tester, bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('The app did not reach the expected state within 15 seconds');
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
}
