import 'package:hive_ce/hive.dart';
import 'package:riverbloc/riverbloc.dart';

import '../services/legion_cli_service.dart';
import '../services/legion_frontend_bridge_service.dart';
import '../services/legion_sysfs_service.dart';
import '../services/xrandr_service.dart';
import '../../features/analytics/models/sensor_record.dart';

final legionSysfsServiceProvider = Provider<LegionSysfsService>(
  (ref) => LegionSysfsService(),
);

final legionCliServiceProvider = Provider<LegionCliService>(
  (ref) => LegionCliService(),
);

final legionBridgeServiceProvider = Provider<LegionFrontendBridgeService>((
  ref,
) {
  final cliService = ref.watch(legionCliServiceProvider);
  return LegionFrontendBridgeService(cliService: cliService);
});

final xrandrServiceProvider = Provider<XrandrService>((ref) => XrandrService());

final sensorRecordBoxProvider = Provider<Box<SensorRecord>>(
  (ref) => Hive.box<SensorRecord>('sensor_records'),
);
