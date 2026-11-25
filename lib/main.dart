import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:yaru/yaru.dart';

import 'app/app.dart';
import 'app/view/package_power_prompt.dart';
import 'features/navigation/view/navigation_shell.dart';
import 'features/analytics/models/sensor_record.dart';
import 'features/dashboard/providers/dashboard_readings_provider.dart';
import 'features/dashboard/repository/dashboard_readings_store.dart';
import 'features/settings/providers/settings_provider.dart';
import 'features/settings/repository/appearance_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await YaruWindowTitleBar.ensureInitialized();
  await Hive.initFlutter();
  Hive.registerAdapter(SensorRecordAdapter());
  await Hive.openBox<SensorRecord>('sensor_records');
  await Hive.openBox<dynamic>('rgb_lighting');
  final preferences = await Hive.openBox<dynamic>('preferences');
  runApp(
    ProviderScope(
      overrides: [
        appearanceStoreProvider.overrideWithValue(AppearanceStore(preferences)),
        dashboardReadingsStoreProvider.overrideWithValue(
          DashboardReadingsStore(preferences),
        ),
      ],
      child: const LegionFrontendApp(
        home: NavigationShell(onReady: requestPackagePowerAccess),
      ),
    ),
  );
}
