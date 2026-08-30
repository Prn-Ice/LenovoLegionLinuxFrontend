import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
