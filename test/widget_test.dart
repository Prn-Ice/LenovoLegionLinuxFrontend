import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'package:legion_frontend/app/app.dart';
import 'package:legion_frontend/core/providers/system_services_provider.dart';
import 'package:legion_frontend/core/services/package_power_telemetry_service.dart';
import 'package:legion_frontend/features/analytics/models/sensor_record.dart';
import 'package:legion_frontend/features/analytics/providers/analytics_provider.dart';
import 'package:legion_frontend/features/analytics/repository/analytics_repository.dart';
import 'package:legion_frontend/features/about/models/about_snapshot.dart';
import 'package:legion_frontend/features/about/providers/about_provider.dart';
import 'package:legion_frontend/features/about/repository/about_repository.dart';
import 'package:legion_frontend/features/boot_logo/models/boot_logo_snapshot.dart';
import 'package:legion_frontend/features/boot_logo/providers/boot_logo_provider.dart';
import 'package:legion_frontend/features/boot_logo/repository/boot_logo_repository.dart';
import 'package:legion_frontend/features/devices/models/devices_snapshot.dart';
import 'package:legion_frontend/features/devices/providers/devices_provider.dart';
import 'package:legion_frontend/features/devices/repository/devices_repository.dart';
import 'package:legion_frontend/features/display/models/display_snapshot.dart';
import 'package:legion_frontend/features/display/providers/display_provider.dart';
import 'package:legion_frontend/features/display/repository/display_repository.dart';
import 'package:legion_frontend/features/automation/models/automation_config.dart';
import 'package:legion_frontend/features/automation/models/automation_trigger_snapshot.dart';
import 'package:legion_frontend/features/automation/providers/automation_provider.dart';
import 'package:legion_frontend/features/automation/repository/automation_repository.dart';
import 'package:legion_frontend/features/automation/view/automation_page.dart';
import 'package:legion_frontend/features/settings/models/settings_snapshot.dart';
import 'package:legion_frontend/features/settings/models/service_control.dart';
import 'package:legion_frontend/features/settings/providers/settings_provider.dart';
import 'package:legion_frontend/features/settings/repository/settings_repository.dart';
import 'package:legion_frontend/features/settings/view/settings_page.dart';
import 'package:legion_frontend/features/diagnostics/view/diagnostics_page.dart';
import 'package:yaru/yaru.dart';

class _UnavailablePackagePowerClient implements PackagePowerTelemetryClient {
  const _UnavailablePackagePowerClient();

  @override
  Future<double?> readPackagePowerWatts() async => null;
}

class _FakeAboutRepository implements AboutRepository {
  int loadCount = 0;

  @override
  Future<AboutSnapshot> loadSnapshot() async {
    loadCount++;
    return AboutSnapshot(
      updatedAt: DateTime.utc(2026),
      cliPath: '/usr/bin/legion',
      cliPathExists: true,
      pythonAvailable: true,
      controlServiceActive: false,
      systemctlAvailable: true,
      cliHealthy: true,
      cliHealthSummary: 'Healthy',
      diagnostics: const [],
      kernelVersion: 'test-kernel',
      hardwareModel: 'Test Legion',
      moduleVersion: 'test',
      cliVersion: 'test',
      commandHistory: const [],
    );
  }
}

class _FakeAnalyticsRepository implements AnalyticsRepository {
  @override
  Future<SensorRecord> recordReading() async =>
      SensorRecord(timestamp: DateTime.utc(2026));

  @override
  List<SensorRecord> readHistory({required DateTime since}) => const [];

  @override
  Future<void> pruneOldRecords() async {}
}

class _FakeSettingsRepository implements SettingsRepository {
  int loadCount = 0;

  @override
  Future<SettingsSnapshot> loadSnapshot() async {
    loadCount++;
    return const SettingsSnapshot(services: []);
  }

  @override
  Future<void> setServiceEnabled(ServiceControl service, bool enabled) async {}
}

class _FakeBootLogoRepository implements BootLogoRepository {
  int loadCount = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<BootLogoSnapshot> loadSnapshot() async {
    loadCount++;
    return const BootLogoSnapshot(status: null);
  }

  @override
  Future<void> enableBootLogo(String imagePath) async {}

  @override
  Future<void> restoreBootLogo() async {}
}

class _FakeDevicesRepository implements DevicesRepository {
  int loadCount = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<DevicesSnapshot> loadSnapshot() async {
    loadCount++;
    return const DevicesSnapshot(
      touchpadEnabled: null,
      touchpadSupported: false,
      winKeyEnabled: null,
      winKeySupported: false,
      fnLockEnabled: null,
      fnLockSupported: false,
      cameraEnabled: null,
      cameraSupported: false,
    );
  }

  @override
  Future<void> setTouchpad(bool enabled) async {}

  @override
  Future<void> setWinKey(bool enabled) async {}

  @override
  Future<void> setFnLock(bool enabled) async {}

  @override
  Future<void> setCamera(bool enabled) async {}
}

class _FakeDisplayRepository implements DisplayRepository {
  int loadCount = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<DisplaySnapshot> loadSnapshot() async {
    loadCount++;
    return const DisplaySnapshot(
      overdriveEnabled: null,
      overdriveSupported: false,
      xrandrOutputName: null,
      availableRefreshRates: null,
      currentRefreshRate: null,
    );
  }

  @override
  Future<void> setOverdriveMode(bool enabled) async {}

  @override
  Future<void> setRefreshRate(String outputName, double rate) async {}
}

class _FakeAutomationRepository implements AutomationRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<AutomationConfig> loadConfig() async => AutomationConfig.defaults();

  @override
  Future<AutomationTriggerSnapshot> readTriggerSnapshot() async =>
      const AutomationTriggerSnapshot(
        platformProfile: null,
        onPowerSupply: null,
      );
}

final _aboutRepository = _FakeAboutRepository();
final _analyticsRepository = _FakeAnalyticsRepository();
final _settingsRepository = _FakeSettingsRepository();
final _bootLogoRepository = _FakeBootLogoRepository();
final _devicesRepository = _FakeDevicesRepository();
final _displayRepository = _FakeDisplayRepository();
final _automationRepository = _FakeAutomationRepository();

Widget _testApp() => ProviderScope(
  overrides: [
    packagePowerTelemetryClientProvider.overrideWithValue(
      const _UnavailablePackagePowerClient(),
    ),
    aboutRepositoryProvider.overrideWithValue(_aboutRepository),
    analyticsRepositoryProvider.overrideWithValue(_analyticsRepository),
    settingsRepositoryProvider.overrideWithValue(_settingsRepository),
    bootLogoRepositoryProvider.overrideWithValue(_bootLogoRepository),
    devicesRepositoryProvider.overrideWithValue(_devicesRepository),
    displayRepositoryProvider.overrideWithValue(_displayRepository),
    automationRepositoryProvider.overrideWithValue(_automationRepository),
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

  testWidgets('opens diagnostics and exports it from Settings', (tester) async {
    tester.view.physicalSize = const Size(1200, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(_testApp());
    // Pump once so post-frame callbacks (e.g. sensor bloc start) run.
    await tester.pump(Duration.zero);

    await tester.tap(find.text('Settings').first);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.text('Diagnostics and export'));
    await tester.pumpAndSettle();
    expect(find.byType(DiagnosticsPage), findsOneWidget);
    expect(find.text('Copy JSON'), findsOneWidget);

    await tester.tap(find.text('Copy JSON'));
    await tester.pump();
    expect(find.text('Copied'), findsOneWidget);
  });

  testWidgets('Settings title bar refreshes all available migrated features', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(_testApp());
    await tester.pump(Duration.zero);
    await tester.tap(find.text('Settings').first);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final before = [
      _settingsRepository.loadCount,
      _bootLogoRepository.loadCount,
      _aboutRepository.loadCount,
      _devicesRepository.loadCount,
      _displayRepository.loadCount,
    ];
    expect(find.byTooltip('Refresh'), findsOneWidget);
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pump();

    expect(_settingsRepository.loadCount, before[0] + 1);
    expect(_bootLogoRepository.loadCount, before[1] + 1);
    expect(_aboutRepository.loadCount, before[2] + 1);
    expect(_devicesRepository.loadCount, before[3] + 1);
    expect(_displayRepository.loadCount, before[4] + 1);
  });

  testWidgets('real shell selection survives compact and wide layout changes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(_testApp());
    await tester.pump(Duration.zero);
    await tester.tap(find.text('Settings').first);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(SettingsPage), findsOneWidget);

    tester.view.physicalSize = const Size(420, 1200);
    tester.binding.handleMetricsChanged();
    await tester.pump();
    expect(find.text('Settings'), findsOneWidget);
    expect(find.byType(SettingsPage), findsOneWidget);

    await tester.tap(find.byTooltip('Automation'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(AutomationPage), findsOneWidget);

    tester.view.physicalSize = const Size(1200, 1200);
    tester.binding.handleMetricsChanged();
    await tester.pump();
    expect(find.byType(AutomationPage), findsOneWidget);
  });
}
