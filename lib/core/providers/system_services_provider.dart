import 'dart:async';

import 'package:hive_ce/hive.dart';
import 'package:riverbloc/riverbloc.dart';

import '../services/legion_cli_service.dart';
import '../services/legion_frontend_bridge_service.dart';
import '../services/legion_sysfs_service.dart';
import '../services/nvidia_smi_service.dart';
import '../services/package_power_telemetry_service.dart';
import '../services/power_profile_service.dart';
import '../services/xrandr_service.dart';
import '../../features/analytics/models/sensor_record.dart';

final legionSysfsServiceProvider = Provider<LegionSysfsService>(
  (ref) => LegionSysfsService(),
);

final legionCliServiceProvider = Provider<LegionCliService>(
  (ref) => LegionCliService(),
);

final nvidiaSmiServiceProvider = Provider<NvidiaSmiService>(
  (ref) => NvidiaSmiService(),
);

final legionBridgeServiceProvider = Provider<LegionFrontendBridgeService>((
  ref,
) {
  final cliService = ref.watch(legionCliServiceProvider);
  return LegionFrontendBridgeService(cliService: cliService);
});

final xrandrServiceProvider = Provider<XrandrService>((ref) => XrandrService());

final powerProfileServiceProvider = Provider<PowerProfileService>((ref) {
  final daemonClient = DBusPowerProfilesDaemonClient();
  ref.onDispose(() => unawaited(daemonClient.close()));
  return PowerProfileService(
    sysfsService: ref.watch(legionSysfsServiceProvider),
    daemonClient: daemonClient,
  );
});

final packagePowerTelemetryClientProvider =
    Provider<PackagePowerTelemetryClient>((ref) {
      final client = DBusPackagePowerTelemetryClient();
      ref.onDispose(() => unawaited(client.close()));
      return client;
    });

final sensorRecordBoxProvider = Provider<Box<SensorRecord>>(
  (ref) => Hive.box<SensorRecord>('sensor_records'),
);
