import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'package:legion_frontend/app/app.dart';
import 'package:legion_frontend/core/providers/system_services_provider.dart';
import 'package:legion_frontend/core/services/package_power_telemetry_service.dart';
import 'package:legion_frontend/features/analytics/models/sensor_record.dart';
import 'package:legion_frontend/features/diagnostics/view/diagnostics_page.dart';
import 'package:yaru/yaru.dart';

class _UnavailablePackagePowerClient implements PackagePowerTelemetryClient {
  const _UnavailablePackagePowerClient();

  @override
  Future<double?> readPackagePowerWatts() async => null;
}

Widget _testApp() => ProviderScope(
  overrides: [
    packagePowerTelemetryClientProvider.overrideWithValue(
      const _UnavailablePackagePowerClient(),
    ),
  ],
  child: const LegionFrontendApp(),
);

void main() {
  late Directory hiveDir;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('hive_widget_test_');
    Hive.init(hiveDir.path);
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(SensorRecordAdapter());
    }
    await Hive.openBox<SensorRecord>('sensor_records');
  });

  tearDownAll(() async {
    await Hive.close();
    await hiveDir.delete(recursive: true);
  });

  testWidgets('renders navigation shell and core sections', (tester) async {
    await tester.pumpWidget(_testApp());
    // Pump once so post-frame callbacks (e.g. sensor bloc start) run.
    await tester.pump(Duration.zero);
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Power'), findsWidgets);
    expect(find.text('Battery'), findsWidgets);
  });

  testWidgets('aligns wide light shell surfaces with the redesign', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(_testApp());
    await tester.pump(Duration.zero);

    final detail = tester.widget<YaruDetailPage>(find.byType(YaruDetailPage));
    expect(detail.backgroundColor, const Color(0xffFAF9F8));
    expect(
      (detail.appBar! as YaruWindowTitleBar).backgroundColor,
      const Color(0xffFAF9F8),
    );

    final masterDetailTheme = tester.widget<YaruMasterDetailTheme>(
      find.byType(YaruMasterDetailTheme),
    );
    expect(masterDetailTheme.data.sideBarColor, const Color(0xffECEBE9));
  });

  testWidgets('renders diagnostics page', (tester) async {
    // Use a tall surface so all sidebar items fit without scrolling.
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(_testApp());
    // Pump once so post-frame callbacks (e.g. sensor bloc start) run.
    await tester.pump(Duration.zero);

    await tester.tap(find.text('Diagnostics').first);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(DiagnosticsPage), findsOneWidget);
  });
}
