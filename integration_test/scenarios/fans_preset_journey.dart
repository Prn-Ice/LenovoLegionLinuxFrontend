import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/models/control_selectors.dart';
import 'package:legion_frontend/features/fans/view/fans_page.dart';

import '../support/journey.dart';
import '../support/safe_app.dart';

void main() {
  testWidgets('cancel then apply a fan preset and verify curve readback', (
    tester,
  ) async {
    final app = await SafeApp.create(includeFanFixture: true);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await app.dispose();
    });
    await app.launch();

    await _navigateToFans(tester);
    final performancePreset = find
        .byKey(const ValueKey('fan-preset-performance-ac'))
        .hitTestable();
    await waitFor(
      tester,
      () => performancePreset.evaluate().isNotEmpty,
      description: 'Aggressive fan preset option',
    );
    expect(find.text('9%  ·  941 RPM'), findsNothing);
    expect(find.text('8%  ·  784 RPM'), findsOneWidget);

    await tester.tap(performancePreset);
    await tester.pumpAndSettle();
    expect(find.text('Apply Aggressive preset'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(app.authorizations, 0);
    expect(app.fanPresetRequests, isEmpty);
    expect(app.fanPresetWrites, isEmpty);
    expect(find.text('8%  ·  784 RPM'), findsOneWidget);

    await tester.tap(performancePreset);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply preset'));
    await waitFor(
      tester,
      () =>
          app.fanPresetWrites.contains(ControlFanPreset.performanceAc) &&
          find.text('9%  ·  941 RPM').evaluate().isNotEmpty,
      description: 'applied curve values reloaded by the Fans page',
    );

    expect(app.authorizations, 1);
    expect(app.fanPresetRequests, [ControlFanPreset.performanceAc]);
    expect(app.fanPresetWrites, [ControlFanPreset.performanceAc]);
    expect(app.requests, isEmpty);
    expect(app.writes, isEmpty);
    expect(
      await File(
        '${app.directory.path}/sys/module/legion_laptop/drivers/platform:legion/'
        'legion/hwmon/hwmon0/pwm1_auto_point1_pwm',
      ).readAsString(),
      '24\n',
    );
    expect(tester.takeException(), isNull);
  });
}

Future<void> _navigateToFans(WidgetTester tester) async {
  final navigation = find.text('Fans').hitTestable();
  await waitFor(
    tester,
    () => navigation.evaluate().isNotEmpty,
    description: 'Fans navigation control',
  );
  await tester.tap(navigation.first);
  await waitFor(
    tester,
    () => find.byType(FansPage).evaluate().isNotEmpty,
    description: 'Fans page navigation',
  );
  await tester.pumpAndSettle();
}
