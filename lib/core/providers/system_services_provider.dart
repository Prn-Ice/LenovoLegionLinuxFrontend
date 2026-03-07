import 'package:riverbloc/riverbloc.dart';

import '../services/legion_cli_service.dart';
import '../services/legion_frontend_bridge_service.dart';
import '../services/legion_sysfs_service.dart';
import '../services/xrandr_service.dart';

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
