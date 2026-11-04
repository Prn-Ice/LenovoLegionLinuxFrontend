import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/widgets/surface_card.dart';
import 'package:legion_frontend/features/battery/bloc/battery_bloc.dart';
import 'package:legion_frontend/features/battery/bloc/battery_event.dart';
import 'package:legion_frontend/features/battery/models/battery_snapshot.dart';
import 'package:legion_frontend/features/battery/providers/battery_provider.dart';
import 'package:legion_frontend/features/battery/repository/battery_repository.dart';
import 'package:legion_frontend/features/dashboard/bloc/dashboard_bloc.dart';
import 'package:legion_frontend/features/dashboard/bloc/dashboard_event.dart';
import 'package:legion_frontend/features/dashboard/models/dashboard_snapshot.dart';
import 'package:legion_frontend/features/dashboard/providers/dashboard_provider.dart';
import 'package:legion_frontend/features/dashboard/repository/dashboard_repository.dart';
import 'package:legion_frontend/features/dashboard/view/dashboard_page.dart';
import 'package:legion_frontend/features/devices/bloc/devices_bloc.dart';
import 'package:legion_frontend/features/devices/providers/devices_provider.dart';
import 'package:legion_frontend/features/devices/repository/devices_repository.dart';
import 'package:legion_frontend/features/sensors/bloc/live_sensor_bloc.dart';
import 'package:legion_frontend/features/sensors/models/live_sensor_snapshot.dart';
import 'package:legion_frontend/features/sensors/providers/live_sensor_provider.dart';
import 'package:legion_frontend/features/sensors/repository/live_sensor_repository.dart';
import 'package:mocktail/mocktail.dart';
import 'package:yaru/yaru.dart';

class _MockDashboardRepository extends Mock implements DashboardRepository {}

class _MockDevicesRepository extends Mock implements DevicesRepository {}

class _MockLiveSensorRepository extends Mock implements LiveSensorRepository {}

class _MockBatteryRepository extends Mock implements BatteryRepository {}

BatterySnapshot batterySnapshot({
  bool conservation = false,
  bool rapid = false,
}) => BatterySnapshot(
  batteryConservationEnabled: conservation,
  batteryConservationSupported: true,
  rapidChargingEnabled: rapid,
  rapidChargingSupported: true,
  batteryPercent: 80,
  batteryCharging: false,
  batteryPowerDrawW: null,
  cycleCounts: null,
  fullCapacityWh: null,
  designCapacityWh: null,
  currentCapacityWh: null,
  batteryTempC: null,
);

Finder control(String title) => find.descendant(
  of: find.ancestor(of: find.text(title), matching: find.byType(SurfaceCard)),
  matching: find.byType(YaruSwitch),
);

Future<ProviderContainer> mountDashboard(
  WidgetTester tester,
  BatteryRepository batteryRepository,
) async {
  final dashboardRepository = _MockDashboardRepository();
  final sensorsRepository = _MockLiveSensorRepository();
  when(
    dashboardRepository.loadSnapshot,
  ).thenAnswer((_) async => DashboardSnapshot.initial());
  when(
    sensorsRepository.loadSnapshot,
  ).thenAnswer((_) async => LiveSensorSnapshot.initial());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dashboardRepositoryProvider.overrideWithValue(dashboardRepository),
        liveSensorRepositoryProvider.overrideWithValue(sensorsRepository),
        batteryRepositoryProvider.overrideWithValue(batteryRepository),
        devicesBlocProvider.overrideWith(
          (_) => DevicesBloc(repository: _MockDevicesRepository()),
        ),
      ],
      child: YaruTheme(
        data: const YaruThemeData(),
        builder: (context, yaru, child) => MaterialApp(
          theme: yaru.theme,
          home: const Scaffold(body: DashboardPage()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(DashboardPage)));
}

void main() {
  testWidgets('dashboard shows loading state before its first snapshot', (
    tester,
  ) async {
    final dashboardRepository = _MockDashboardRepository();
    final sensorsRepository = _MockLiveSensorRepository();
    final devicesRepository = _MockDevicesRepository();
    final pendingDashboard = Completer<DashboardSnapshot>();

    when(
      dashboardRepository.loadSnapshot,
    ).thenAnswer((_) => pendingDashboard.future);
    when(
      sensorsRepository.loadSnapshot,
    ).thenAnswer((_) async => LiveSensorSnapshot.initial());

    final dashboardBloc = DashboardBloc(
      repository: dashboardRepository,
      pollInterval: const Duration(days: 1),
    );
    final sensorsBloc = LiveSensorBloc(
      repository: sensorsRepository,
      pollInterval: const Duration(days: 1),
    );
    final devicesBloc = DevicesBloc(
      repository: devicesRepository,
      pollInterval: const Duration(days: 1),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dashboardBlocProvider.overrideWith((ref) => dashboardBloc),
          liveSensorBlocProvider.overrideWith((ref) => sensorsBloc),
          devicesBlocProvider.overrideWith((ref) => devicesBloc),
          batteryBlocProvider.overrideWith(
            (_) => BatteryBloc(repository: _MockBatteryRepository()),
          ),
        ],
        child: YaruTheme(
          data: const YaruThemeData(),
          builder: (context, yaru, child) => MaterialApp(
            theme: yaru.theme,
            home: const Scaffold(body: DashboardPage()),
          ),
        ),
      ),
    );
    dashboardBloc.add(const DashboardStarted());
    await tester.pump();

    expect(find.bySemanticsLabel('Loading dashboard data'), findsOneWidget);
    expect(find.byType(YaruCircularProgressIndicator), findsOneWidget);
    expect(find.text('Quick controls'), findsNothing);

    pendingDashboard.complete(DashboardSnapshot.initial());
    await tester.pump();
  });

  testWidgets('Dashboard uses shared battery readback and busy state', (
    tester,
  ) async {
    final repository = _MockBatteryRepository();
    var snapshot = batterySnapshot();
    final write = Completer<void>();
    when(repository.loadSnapshot).thenAnswer((_) async => snapshot);
    when(() => repository.setRapidCharging(true)).thenAnswer((_) async {
      await write.future;
      snapshot = batterySnapshot(rapid: true);
    });
    when(() => repository.setBatteryConservation(true)).thenAnswer((_) async {
      snapshot = batterySnapshot(conservation: true, rapid: true);
    });
    final container = await mountDashboard(tester, repository);
    final rapid = control('Rapid charge');
    final health = control('Battery health');
    await tester.ensureVisible(rapid);
    await tester.tap(rapid);
    await tester.pumpAndSettle();
    verifyNever(() => repository.setRapidCharging(true));
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(tester.widget<YaruSwitch>(rapid).value, isFalse);
    expect(tester.widget<YaruSwitch>(rapid).onChanged, isNull);
    expect(tester.widget<YaruSwitch>(health).onChanged, isNull);
    expect(container.read(batteryBlocProvider).isApplying, isTrue);

    write.complete();
    await tester.pumpAndSettle();
    expect(tester.widget<YaruSwitch>(rapid).value, isTrue);
    expect(container.read(batteryBlocProvider).rapidChargingEnabled, isTrue);
    verify(() => repository.setRapidCharging(true)).called(1);

    // A command from another consumer updates the Dashboard without refresh.
    container
        .read(batteryBlocProvider.bloc)
        .add(const BatteryConservationSetRequested(true));
    await tester.pumpAndSettle();
    expect(tester.widget<YaruSwitch>(health).value, isTrue);
    expect(tester.widget<YaruSwitch>(health).onChanged, isNotNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('confirmation resolves the current battery provider', (
    tester,
  ) async {
    final repository = _MockBatteryRepository();
    when(repository.loadSnapshot).thenAnswer((_) async => batterySnapshot());
    var rapidEnabled = false;
    when(() => repository.setRapidCharging(true)).thenAnswer((_) async {
      rapidEnabled = true;
    });
    final container = await mountDashboard(tester, repository);
    final original = container.read(batteryBlocProvider.bloc);
    final rapid = control('Rapid charge');
    await tester.ensureVisible(rapid);
    await tester.tap(rapid);
    await tester.pumpAndSettle();
    when(
      repository.loadSnapshot,
    ).thenAnswer((_) async => batterySnapshot(rapid: rapidEnabled));
    container.invalidate(batteryBlocProvider);
    await tester.pumpAndSettle();
    expect(container.read(batteryBlocProvider.bloc), isNot(same(original)));
    expect(original.isClosed, isTrue);
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(tester.widget<YaruSwitch>(rapid).value, isTrue);
    verify(() => repository.setRapidCharging(true)).called(1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
