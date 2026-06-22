import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:yaru/yaru.dart';

import 'app/app.dart';
import 'features/analytics/models/sensor_record.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await YaruWindowTitleBar.ensureInitialized();
  await Hive.initFlutter();
  Hive.registerAdapter(SensorRecordAdapter());
  await Hive.openBox<SensorRecord>('sensor_records');
  await Hive.openBox<dynamic>('rgb_lighting');
  runApp(const ProviderScope(child: LegionFrontendApp()));
}
