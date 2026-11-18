import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/models/control_selectors.dart';
import 'package:legion_frontend/features/fans/bloc/fans_bloc.dart';
import 'package:legion_frontend/features/fans/bloc/fans_event.dart';
import 'package:legion_frontend/features/fans/providers/fans_provider.dart';
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
    await app.launch(
      additionalOverrides: [
        // Require the write's readback; polling must not repair stale state.
        fansBlocProvider.overrideWith(
          (ref) => FansBloc(
            repository: ref.watch(fansRepositoryProvider),
            pollInterval: const Duration(days: 1),
          )..add(const FansStarted()),
        ),
      ],
    );

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

  testWidgets('speed-only firmware table stays read-only through the app', (
    tester,
  ) async {
    final app = await SafeApp.create();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await app.dispose();
    });
    await _prepareSpeedTable(app.directory);
    await app.launch();
    await _navigateToFans(tester);
    await waitFor(
      tester,
      () => find.byKey(const ValueKey('fan-speed-table')).evaluate().isNotEmpty,
      description: 'read-only firmware speed table',
    );

    expect(find.byKey(const ValueKey('fan-curve-save')), findsNothing);
    expect(
      find.byKey(const ValueKey('fan-preset-performance-ac')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('mini-fan-curve')), findsNothing);
    expect(find.byKey(const ValueKey('lock-fan-controller')), findsNothing);

    // A stale caller must not reach authorization after the UI hides editing.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(FansPage)),
    );
    final bloc = container.read(fansBlocProvider.bloc);
    bloc.add(const FansPresetSelectionChanged('performance-ac'));
    bloc.add(const FansApplySelectedPresetRequested());
    bloc.add(const FansApplyCurrentPresetRequested());
    bloc.add(const FanCurveSaveRequested());
    await tester.pumpAndSettle();
    expect(app.authorizations, 0);
    expect(app.fanPresetRequests, isEmpty);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _prepareSpeedTable(Directory directory) async {
  const platform = 'sys/module/legion_laptop/drivers/platform:legion/legion';
  final values = <String, String>{
    'sys/class/dmi/id/product_name': '82Y4',
    'sys/class/dmi/id/bios_version': 'M1CN48WW',
    '$platform/fancurve_speed_unit': 'level',
    '$platform/fan1_level_rpm_table':
        '1000 1500 2000 2500 3000 3500 4000 4500 5000 5500',
    '$platform/fan2_level_rpm_table':
        '900 1400 1900 2400 2900 3400 3900 4400 4900 5400',
    '$platform/hwmon/hwmon0/name': 'legion_hwmon',
    '$platform/hwmon/hwmon0/auto_points_size': '8',
    for (var i = 1; i <= 8; i++)
      '$platform/hwmon/hwmon0/pwm1_auto_point${i}_pwm': '${i * 255 ~/ 10}',
  };
  for (final entry in values.entries) {
    final file = File('${directory.path}/${entry.key}');
    await file.parent.create(recursive: true);
    await file.writeAsString('${entry.value}\n');
  }
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
