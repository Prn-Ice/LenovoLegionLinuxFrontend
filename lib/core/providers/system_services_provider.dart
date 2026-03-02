import 'package:riverbloc/riverbloc.dart';

import '../services/legion_cli_service.dart';
import '../services/legion_sysfs_service.dart';

final legionSysfsServiceProvider = Provider<LegionSysfsService>(
  (ref) => LegionSysfsService(),
);

final legionCliServiceProvider = Provider<LegionCliService>(
  (ref) => LegionCliService(),
);
