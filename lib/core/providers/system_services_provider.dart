import 'dart:async';

import 'package:hive_ce/hive.dart';
import 'package:riverbloc/riverbloc.dart';

import '../services/legion_cli_service.dart';
import '../services/helper_control_transport.dart';
import '../services/native_host_cli_resolver.dart';
import '../services/legion_control_client.dart';
import '../services/legion_frontend_bridge_service.dart';
import '../services/legion_sysfs_service.dart';
import '../services/nvidia_smi_service.dart';
import '../services/igpu_sysfs_service.dart';
import '../services/package_power_telemetry_service.dart';
import '../services/power_profile_service.dart';
import '../services/xrandr_service.dart';
import '../../features/analytics/models/sensor_record.dart';

typedef ControlTransportFactory = LegionControlTransport Function(
  Future<String> Function() resolveCliPath,
);

final controlTransportFactoryProvider = Provider<ControlTransportFactory>((
  ref,
) {
  return (resolveCliPath) =>
      HelperControlTransport(resolveCliPath: resolveCliPath);
});
final legionSysfsServiceProvider = Provider<LegionSysfsService>(
  (ref) => LegionSysfsService(),
);

final legionCliServiceProvider = Provider<LegionCliService>((ref) {
  final service = LegionCliService(pathResolver: resolveNativeHostCli);
  ref.onDispose(service.close);
  return service;
});

final nvidiaSmiServiceProvider = Provider<NvidiaSmiService>(
  (ref) => NvidiaSmiService(),
);

final igpuSysfsServiceProvider = Provider<IgpuSysfsService>(
  (ref) => IgpuSysfsService(),
);

final legionBridgeServiceProvider = Provider<LegionFrontendBridgeService>((
  ref,
) {
  final cliService = ref.watch(legionCliServiceProvider);
  final controlClient = ref.watch(legionControlClientProvider);
  return LegionFrontendBridgeService(
    cliService: cliService,
    controlClient: controlClient,
  );
});

final legionControlClientProvider = Provider<LegionControlClient>((ref) {
  final cli = ref.watch(legionCliServiceProvider);
  final factory = ref.watch(controlTransportFactoryProvider);
  final client = LegionControlClient(transport: factory(cli.resolvePath));
  ref.onDispose(() => unawaited(client.close()));
  return client;
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
      final client = SessionPackagePowerClient();
      ref.onDispose(() => unawaited(client.close()));
      return client;
    });

final sensorRecordBoxProvider = Provider<Box<SensorRecord>>(
  (ref) => Hive.box<SensorRecord>('sensor_records'),
);
