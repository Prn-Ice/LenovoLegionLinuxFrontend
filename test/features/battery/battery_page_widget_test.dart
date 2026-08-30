import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/analytics/bloc/analytics_bloc.dart';
import 'package:legion_frontend/features/analytics/models/sensor_record.dart';
import 'package:legion_frontend/features/analytics/providers/analytics_provider.dart';
import 'package:legion_frontend/features/analytics/repository/analytics_repository.dart';
import 'package:legion_frontend/features/battery/bloc/battery_bloc.dart';
import 'package:legion_frontend/features/battery/bloc/battery_event.dart';
import 'package:legion_frontend/features/battery/models/battery_snapshot.dart';
import 'package:legion_frontend/features/battery/providers/battery_provider.dart';
import 'package:legion_frontend/features/battery/repository/battery_repository.dart';
import 'package:legion_frontend/features/battery/view/battery_page.dart';
import 'package:mocktail/mocktail.dart';
import 'package:yaru/yaru.dart';

class _MockBatteryRepository extends Mock implements BatteryRepository {}

class _MockAnalyticsRepository extends Mock implements AnalyticsRepository {}

void main() {
  testWidgets('battery handoff is truthful and responsive at compact width', (
    tester,
  ) async {
    await _pumpPage(tester, width: 360);

    expect(find.text('Battery & energy'), findsNothing);
    expect(find.text('Full'), findsWidgets);
    expect(find.text('Discharging'), findsNothing);
    expect(find.text('Charge %'), findsOneWidget);
    expect(find.text('Export logs'), findsOneWidget);
    expect(find.text('Always-on USB'), findsOneWidget);
    expect(
      find.text('Charge devices while asleep · read-only'),
      findsOneWidget,
    );
    expect(find.byType(YaruPopupMenuButton<int>), findsOneWidget);
    expect(
      find.byWidgetPredicate((widget) => widget is YaruPopupMenuButton),
      findsNWidgets(2),
    );
    expect(find.byType(YaruCheckboxTheme), findsNWidgets(2));
    for (final theme in tester.widgetList<YaruCheckboxTheme>(
      find.byType(YaruCheckboxTheme),
    )) {
      expect(
        theme.data.color?.resolve({WidgetState.selected}),
        const Color(0xff3A9D4F),
      );
    }
    for (final widget in tester.widgetList<YaruSwitch>(
      find.byType(YaruSwitch),
    )) {
      expect(widget.selectedColor, const Color(0xff3A9D4F));
    }
    await tester.tap(find.text('Last hour'));
    await tester.pumpAndSettle();
    final checkedItem = find.byType(YaruCheckbox).first;
    expect(checkedItem, findsOneWidget);
    expect(
      YaruCheckboxTheme.of(
        tester.element(checkedItem),
      ).color?.resolve({WidgetState.selected}),
      const Color(0xff3A9D4F),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('battery details use two columns at wide width', (tester) async {
    await _pumpPage(tester, width: 1100, dark: true);

    expect(
      tester.getTopLeft(find.text('BATTERY')).dy,
      tester.getTopLeft(find.text('ENERGY')).dy,
    );
    final chart = tester.widget<LineChart>(find.byType(LineChart));
    expect(
      chart.data.lineTouchData.touchTooltipData.fitInsideHorizontally,
      isTrue,
    );
    expect(
      chart.data.lineTouchData.touchTooltipData.fitInsideVertically,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('battery explains telemetry the kernel does not expose', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      width: 1100,
      snapshot: _snapshotWithoutTemperature,
      includeTemperature: false,
    );

    expect(find.text('Not exposed by battery driver'), findsOneWidget);
    expect(find.text('Battery power'), findsOneWidget);
    final selector = tester.widget<SegmentedButton<int>>(
      find.byType(SegmentedButton<int>),
    );
    expect(
      selector.style?.foregroundColor?.resolve({WidgetState.selected}),
      const Color(0xff3A9D4F),
    );
    expect(
      selector.style?.backgroundColor?.resolve({WidgetState.selected}),
      const Color(0xff3A9D4F).withValues(alpha: 0.18),
    );
  });
}

Future<void> _pumpPage(
  WidgetTester tester, {
  required double width,
  bool dark = false,
  BatterySnapshot snapshot = _snapshot,
  bool includeTemperature = true,
}) async {
  tester.view.physicalSize = Size(width, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final batteryRepository = _MockBatteryRepository();
  when(batteryRepository.loadSnapshot).thenAnswer((_) async => snapshot);
  final batteryBloc = BatteryBloc(
    repository: batteryRepository,
    pollInterval: const Duration(days: 1),
  );
  final batteryLoaded = batteryBloc.stream.firstWhere(
    (state) => !state.isLoading && state.hasLoaded,
  );
  batteryBloc.add(const BatteryStarted());
  await batteryLoaded;

  final history = [
    SensorRecord(
      timestamp: DateTime.now().subtract(const Duration(minutes: 1)),
      batteryPercent: 77,
      batteryPowerDrawW: 12,
      batteryTempC: includeTemperature ? 28 : null,
    ),
    SensorRecord(
      timestamp: DateTime.now(),
      batteryPercent: 78,
      batteryPowerDrawW: 0,
      batteryTempC: includeTemperature ? 28.2 : null,
    ),
  ];
  final analyticsRepository = _MockAnalyticsRepository();
  when(analyticsRepository.pruneOldRecords).thenAnswer((_) async {});
  when(analyticsRepository.recordReading).thenAnswer((_) async => history.last);
  when(
    () => analyticsRepository.readHistory(since: any(named: 'since')),
  ).thenReturn(history);
  final analyticsBloc = AnalyticsBloc(
    repository: analyticsRepository,
    pollInterval: const Duration(days: 1),
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        batteryBlocProvider.overrideWith((ref) => batteryBloc),
        analyticsBlocProvider.overrideWith((ref) => analyticsBloc),
      ],
      child: YaruTheme(
        data: const YaruThemeData(),
        builder: (context, yaru, child) => MaterialApp(
          theme: yaru.theme,
          darkTheme: yaru.darkTheme,
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          home: const Scaffold(body: BatteryPage()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const _snapshot = BatterySnapshot(
  batteryConservationEnabled: true,
  batteryConservationSupported: true,
  rapidChargingEnabled: false,
  rapidChargingSupported: true,
  batteryPercent: 78,
  batteryCharging: false,
  batteryPowerDrawW: 0,
  cycleCounts: 87,
  fullCapacityWh: 56.82,
  designCapacityWh: 60,
  currentCapacityWh: 44.2,
  batteryTempC: 26.7,
  batteryStatus: 'Full',
  alwaysOnUsbEnabled: true,
  alwaysOnUsbSupported: false,
  voltageV: 17.33,
  manufacturer: 'SMP',
  modelName: 'L22M4PC3',
  serialNumber: '387',
);

const _snapshotWithoutTemperature = BatterySnapshot(
  batteryConservationEnabled: true,
  batteryConservationSupported: true,
  rapidChargingEnabled: false,
  rapidChargingSupported: true,
  batteryPercent: 78,
  batteryCharging: false,
  batteryPowerDrawW: 12.4,
  cycleCounts: 87,
  fullCapacityWh: 56.82,
  designCapacityWh: 60,
  currentCapacityWh: 44.2,
  batteryTempC: null,
  batteryStatus: 'Discharging',
  alwaysOnUsbEnabled: true,
  alwaysOnUsbSupported: false,
  voltageV: 17.33,
  manufacturer: 'SMP',
  modelName: 'L22M4PC3',
  serialNumber: '387',
);
