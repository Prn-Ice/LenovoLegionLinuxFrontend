import 'dart:async';
import 'dart:io';

import 'package:hive_ce/hive.dart';
import 'package:riverbloc/riverbloc.dart';

import '../services/legion_cli_service.dart';
import '../services/portable_legion_control_transport.dart';
import '../services/native_host_cli_resolver.dart';
import '../models/control_mode.dart';
import '../services/legion_control_client.dart';
import '../services/legion_frontend_bridge_service.dart';
import '../services/legion_sysfs_service.dart';
import '../services/nvidia_smi_service.dart';
import '../services/package_power_telemetry_service.dart';
import '../services/power_profile_service.dart';
import '../services/xrandr_service.dart';
import '../../features/analytics/models/sensor_record.dart';

final controlModeProvider = Provider<ControlMode>(
  (ref) => ControlMode.installedService,
);

final portableControlAvailableProvider = Provider<bool>((ref) {
  return const bool.fromEnvironment('LLLF_ENABLE_PORTABLE_CONTROL') &&
      File(
        '${File(Platform.resolvedExecutable).parent.path}/libexec/legion-portable-control',
      ).existsSync();
});

typedef ControlTransportFactory =
    LegionControlTransport Function(
      ControlMode mode,
      Future<String> Function() resolveCliPath,
    );

final controlTransportFactoryProvider = Provider<ControlTransportFactory>((
  ref,
) {
  return (mode, resolveCliPath) => switch (mode) {
    ControlMode.installedService => DBusLegionControlTransport(),
    ControlMode.temporaryHelper => PortableLegionControlTransport(
      resolveCliPath: resolveCliPath,
    ),
  };
});
final legionSysfsServiceProvider = Provider<LegionSysfsService>(
  (ref) => LegionSysfsService(),
);

final legionCliServiceProvider = Provider<LegionCliService>((ref) {
  final mode = ref.watch(controlModeProvider);
  final available = ref.watch(portableControlAvailableProvider);
  final service = LegionCliService(
    pathResolver: mode == ControlMode.temporaryHelper
        ? () {
            if (!available) {
              throw const LegionControlPortableSetupException(
                'Temporary hardware control is not available in this build. Select installed service mode in Settings and reopen the app, or use a build that includes the temporary helper.',
              );
            }
            return resolveNativeHostCli();
          }
        : null,
  );
  ref.onDispose(service.close);
  return service;
});

final nvidiaSmiServiceProvider = Provider<NvidiaSmiService>(
  (ref) => NvidiaSmiService(),
);

final legionBridgeServiceProvider = Provider<LegionFrontendBridgeService>((
  ref,
) {
  final cliService = ref.watch(legionCliServiceProvider);
  final controlClient = ref.watch(legionControlClientProvider);
  return LegionFrontendBridgeService(
    cliService: cliService,
    controlClient: controlClient,
    controlMode: ref.watch(controlModeProvider),
  );
});

final legionControlClientProvider = Provider<LegionControlClient>((ref) {
  final mode = ref.watch(controlModeProvider);
  final cli = ref.watch(legionCliServiceProvider);
  final factory = ref.watch(controlTransportFactoryProvider);
  final client = LegionControlClient(
    transport: factory(mode, cli.resolvePath),
    controlMode: mode,
  );
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
      final client = DBusPackagePowerTelemetryClient();
      ref.onDispose(() => unawaited(client.close()));
      return client;
    });

final sensorRecordBoxProvider = Provider<Box<SensorRecord>>(
  (ref) => Hive.box<SensorRecord>('sensor_records'),
);
