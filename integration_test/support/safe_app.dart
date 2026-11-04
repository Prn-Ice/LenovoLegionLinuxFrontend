import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'package:legion_frontend/app/app.dart';
import 'package:legion_frontend/core/models/control_selectors.dart';
import 'package:legion_frontend/core/models/power_profiles_daemon_snapshot.dart';
import 'package:legion_frontend/core/providers/system_services_provider.dart';
import 'package:legion_frontend/core/services/legion_cli_service.dart';
import 'package:legion_frontend/core/services/legion_control_client.dart';
import 'package:legion_frontend/core/services/legion_sysfs_service.dart';
import 'package:legion_frontend/core/services/nvidia_smi_service.dart';
import 'package:legion_frontend/core/services/power_profile_service.dart';
import 'package:legion_frontend/features/analytics/models/sensor_record.dart';
import 'package:legion_frontend/features/automation/providers/automation_provider.dart';
import 'package:legion_frontend/features/automation/repository/automation_repository.dart';
import 'package:legion_frontend/features/lighting/providers/lighting_provider.dart';
import 'package:legion_frontend/features/sensors/models/live_sensor_snapshot.dart';
import 'package:legion_frontend/features/sensors/providers/live_sensor_provider.dart';
import 'package:legion_frontend/features/sensors/repository/live_sensor_repository.dart';
import 'package:legion_frontend/features/settings/models/service_control.dart';
import 'package:legion_frontend/features/settings/models/settings_snapshot.dart';
import 'package:legion_frontend/features/settings/providers/settings_provider.dart';
import 'package:legion_frontend/features/settings/repository/appearance_store.dart';
import 'package:legion_frontend/features/settings/repository/settings_repository.dart';
import 'package:yaru/yaru.dart';

enum ControlFailure { permissionDenied, unavailable, commandFailed }

/// Synthetic readings, not defaults or measurements from a supported laptop.
/// All writes stay inside this instance's temporary directory.
class SafeApp {
  SafeApp._(this.directory, this.conservationFile);

  final Directory directory;
  final File conservationFile;
  final writes = <bool>[];
  final requests = <bool>[];
  ControlFailure? nextFailure;
  Completer<void>? writeCompletion;
  bool _controlCreated = false;
  final _controlClosed = Completer<void>();
  int authorizations = 0;

  static Future<SafeApp> create() async {
    final directory = await Directory.systemTemp.createTemp('legion_journey_');
    final file = File(
      '${directory.path}/sys/bus/platform/drivers/ideapad_acpi/'
      'VPC2004:00/conservation_mode',
    );
    await file.parent.create(recursive: true);
    await file.writeAsString('0\n');
    final profile = File(
      '${directory.path}/sys/firmware/acpi/platform_profile',
    );
    await profile.parent.create(recursive: true);
    await profile.writeAsString('balanced\n');
    await File('${profile.path}_choices').writeAsString('quiet balanced\n');
    await Directory('${directory.path}/proc').create();

    Hive.init('${directory.path}/storage');
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(SensorRecordAdapter());
    }
    await Hive.openBox<SensorRecord>('sensor_records');
    await Hive.openBox<dynamic>('rgb_lighting');
    await Hive.openBox<dynamic>('preferences');
    return SafeApp._(directory, file);
  }

  Future<void> launch() async {
    await YaruWindowTitleBar.ensureInitialized();
    final sysfs = LegionSysfsService(
      sysRoot: '${directory.path}/sys',
      procRoot: '${directory.path}/proc',
    );
    runApp(
      ProviderScope(
        overrides: [
          legionSysfsServiceProvider.overrideWithValue(sysfs),
          legionControlClientProvider.overrideWith((ref) {
            final client = LegionControlClient(
              transport: _FixtureControl(this),
            );
            _controlCreated = true;
            ref.onDispose(() => unawaited(client.close()));
            return client;
          }),
          legionCliServiceProvider.overrideWithValue(
            LegionCliService(
              cliPath: '/integration-test/no-cli',
              processRunner: (_, _) => throw StateError(
                'Integration journeys must not run commands',
              ),
            ),
          ),
          powerProfileServiceProvider.overrideWithValue(
            PowerProfileService(sysfsService: sysfs, daemonClient: _NoDaemon()),
          ),
          nvidiaSmiServiceProvider.overrideWithValue(_NoNvidia()),
          automationRepositoryProvider.overrideWithValue(
            AutomationRepository(
              configFile: File('${directory.path}/automation_rules.json'),
            ),
          ),
          spectrumHidServiceProvider.overrideWith(
            (_) => throw StateError('HID access is outside this journey'),
          ),
          openRgbServiceProvider.overrideWith(
            (_) => throw StateError('OpenRGB access is outside this journey'),
          ),
          xrandrServiceProvider.overrideWith(
            (_) => throw StateError('Display access is outside this journey'),
          ),
          packagePowerTelemetryClientProvider.overrideWith(
            (_) => throw StateError('System telemetry is outside this journey'),
          ),
          // These repositories contain direct host reads (systemctl and /sys).
          // Keep their real providers/Blocs, but supply fixed repository results.
          settingsRepositoryProvider.overrideWithValue(_NoSystemServices()),
          liveSensorRepositoryProvider.overrideWithValue(_NoLiveSensors()),
          appearanceStoreProvider.overrideWithValue(
            AppearanceStore(Hive.box<dynamic>('preferences')),
          ),
        ],
        child: const LegionFrontendApp(),
      ),
    );
  }

  Future<void> dispose() async {
    final completion = writeCompletion;
    if (completion != null && !completion.isCompleted) completion.complete();
    try {
      if (_controlCreated) {
        await _controlClosed.future.timeout(const Duration(seconds: 5));
      }
    } finally {
      await Hive.close();
      await directory.delete(recursive: true);
    }
  }
}

class _FixtureControl implements LegionControlTransport {
  _FixtureControl(this.app);
  final SafeApp app;

  @override
  Future<void> authorize() async {
    app.authorizations++;
    switch (app.nextFailure) {
      case ControlFailure.permissionDenied:
        app.nextFailure = null;
        throw const LegionControlPermissionDeniedException(
          'Test authorization was denied. Approve authentication and retry.',
        );
      case ControlFailure.unavailable:
        app.nextFailure = null;
        throw const LegionControlUnavailableException(
          'Test control service is unavailable. Reconnect and retry.',
        );
      case ControlFailure.commandFailed:
      case null:
        return;
    }
  }

  @override
  Future<void> call(String method, List<Object> arguments) async {
    if (method != 'SetToggle' ||
        arguments.length != 2 ||
        arguments.first != ControlToggle.batteryConservation.wireValue ||
        arguments.last is! bool) {
      throw StateError('Unexpected control operation: $method $arguments');
    }
    final enabled = arguments.last as bool;
    app.requests.add(enabled);
    if (app.nextFailure == ControlFailure.commandFailed) {
      app.nextFailure = null;
      throw const LegionControlCommandFailedException(
        'Test backend rejected the write. Fix the backend and retry.',
      );
    }
    await app.writeCompletion?.future;
    await app.conservationFile.writeAsString(enabled ? '1\n' : '0\n');
    app.writes.add(enabled);
  }

  @override
  Future<void> close() async => app._controlClosed.complete();
}

class _NoDaemon implements PowerProfilesDaemonClient {
  @override
  Future<PowerProfilesDaemonSnapshot?> loadSnapshot() async => null;

  @override
  Future<void> setActiveProfile(String profile) =>
      throw StateError('Power profile writes are outside this journey');
}

class _NoNvidia implements NvidiaSmiService {
  @override
  Future<NvidiaSmiSnapshot?> readSnapshot() async => null;
}

class _NoSystemServices implements SettingsRepository {
  @override
  Future<SettingsSnapshot> loadSnapshot() async =>
      const SettingsSnapshot(services: []);

  @override
  Future<void> setServiceEnabled(ServiceControl service, bool enabled) =>
      throw StateError('System service writes are outside this journey');
}

class _NoLiveSensors implements LiveSensorRepository {
  @override
  Future<LiveSensorSnapshot> loadSnapshot() async =>
      LiveSensorSnapshot.initial();
}
