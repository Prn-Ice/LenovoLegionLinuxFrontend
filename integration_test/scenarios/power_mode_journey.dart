import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/dashboard/view/dashboard_page.dart';
import 'package:legion_frontend/features/power/view/power_page.dart';

import '../support/journey.dart';
import '../support/safe_app.dart';

void main() {
  testWidgets('select a power profile and refresh its Dashboard readback', (
    tester,
  ) async {
    final app = await SafeApp.create();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await app.dispose();
    });
    await app.launch();

    await _navigate(tester, 'Power', PowerPage);
    final performance = find.text('Performance').hitTestable();
    await waitFor(
      tester,
      () => performance.evaluate().isNotEmpty,
      description: 'Performance power profile option',
    );
    await tester.tap(performance.first);
    await waitFor(
      tester,
      () =>
          app.platformProfileWrites.contains(
            FixturePlatformProfile.performance,
          ) &&
          _isModeSelected(tester, PowerPage, 'Performance'),
      description: 'Power page platform profile readback',
    );
    expect(app.platformProfileRequests, [FixturePlatformProfile.performance]);
    expect(app.platformProfileWrites, [FixturePlatformProfile.performance]);
    expect(
      await File(
        '${app.directory.path}/sys/firmware/acpi/platform_profile',
      ).readAsString(),
      'performance\n',
    );
    expect(app.requests, isEmpty);
    expect(app.writes, isEmpty);

    await _navigate(tester, 'Dashboard', DashboardPage);
    await tester.tap(find.byTooltip('Refresh'));
    await waitFor(
      tester,
      () => _isModeSelected(tester, DashboardPage, 'Performance'),
      description: 'refreshed Dashboard power profile selection',
    );
    expect(app.platformProfileRequests, [FixturePlatformProfile.performance]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AC-only profile selection on battery makes no write', (
    tester,
  ) async {
    final app = await SafeApp.create(acOnline: false);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await app.dispose();
    });
    await app.launch();

    await _navigate(tester, 'Power', PowerPage);
    final maxPower = find.text('Extreme').hitTestable();
    await waitFor(
      tester,
      () => maxPower.evaluate().isNotEmpty,
      description: 'Max Power profile option',
    );
    await tester.tap(maxPower.first);
    await waitFor(
      tester,
      () => find.textContaining('Connect AC power').evaluate().isNotEmpty,
      description: 'AC power constraint message',
    );
    expect(app.platformProfileRequests, isEmpty);
    expect(app.platformProfileWrites, isEmpty);
    expect(app.authorizations, 0);
    expect(app.requests, isEmpty);
    expect(app.writes, isEmpty);
    expect(
      await File(
        '${app.directory.path}/sys/firmware/acpi/platform_profile',
      ).readAsString(),
      'balanced\n',
    );
    expect(tester.takeException(), isNull);
  });
}

bool _isModeSelected(WidgetTester tester, Type pageType, String label) {
  final pageLabel = find.descendant(
    of: find.byType(pageType),
    matching: find.text(label),
  );
  final chips = find.ancestor(of: pageLabel, matching: find.byType(ChoiceChip));
  return chips.evaluate().any(
    (element) => (element.widget as ChoiceChip).selected,
  );
}

Future<void> _navigate(WidgetTester tester, String label, Type pageType) async {
  final navigation = find.text(label).hitTestable();
  await waitFor(
    tester,
    () =>
        navigation.evaluate().isNotEmpty ||
        find.byTooltip(label).evaluate().isNotEmpty,
    description: '$label navigation control',
  );
  await tester.tap(
    navigation.evaluate().isNotEmpty ? navigation.first : find.byTooltip(label),
  );
  await waitFor(
    tester,
    () => find.byType(pageType).evaluate().isNotEmpty,
    description: '$label page navigation',
  );
  await tester.pumpAndSettle();
}
