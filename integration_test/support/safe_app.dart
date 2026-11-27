import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:hive_ce/hive.dart';
import 'package:legion_frontend/app/app.dart';
import 'package:legion_frontend/core/models/control_selectors.dart';
import 'package:legion_frontend/core/models/power_profiles_daemon_snapshot.dart';
import 'package:legion_frontend/core/providers/system_services_provider.dart';
import 'package:legion_frontend/core/services/legion_cli_service.dart';
import 'package:legion_frontend/core/models/control_capabilities.dart';
import 'package:legion_frontend/core/services/legion_control_client.dart';
import 'package:legion_frontend/core/services/legion_sysfs_service.dart';
import 'package:legion_frontend/core/services/nvidia_smi_service.dart';
import 'package:legion_frontend/core/services/package_power_telemetry_service.dart';
import 'package:legion_frontend/core/models/gpu_reading.dart';
import 'package:legion_frontend/core/services/power_profile_service.dart';
import 'package:legion_frontend/features/analytics/models/sensor_record.dart';
import 'package:legion_frontend/features/automation/providers/automation_provider.dart';
import 'package:legion_frontend/features/automation/repository/automation_repository.dart';
import 'package:legion_frontend/features/lighting/providers/lighting_provider.dart';
import 'package:legion_frontend/features/sensors/models/live_sensor_snapshot.dart';
import 'package:legion_frontend/features/sensors/providers/live_sensor_provider.dart';
import 'package:legion_frontend/features/sensors/repository/live_sensor_repository.dart';
import 'package:legion_frontend/features/settings/providers/settings_provider.dart';
import 'package:legion_frontend/features/settings/repository/appearance_store.dart';
import 'package:yaru/yaru.dart';

enum ControlFailure { permissionDenied, unavailable, commandFailed }

enum FixturePlatformProfile { quiet, balanced, performance, maxPower, custom }

enum FixtureFanCurveResult { applied, unchanged }

enum FixtureRapidChargingResult { applied, unchanged, readbackUnavailable }

/// Synthetic values chosen to distinguish edits and rollback from initial state.
enum FixturePowerLimit {
  sustained(
    ControlFeature.cpuLongtermPowerLimit,
    'cpu_longterm_powerlimit',
    45,
  ),
  boost(ControlFeature.cpuShorttermPowerLimit, 'cpu_shortterm_powerlimit', 80),
  gpu(ControlFeature.gpuCtgpPowerLimit, 'gpu_ctgp_powerlimit', 100);

  const FixturePowerLimit(this.feature, this.attribute, this.initialValue);

  final ControlFeature feature;
  final String attribute;
  final int initialValue;
}

/// Synthetic readings, not defaults or measurements from a supported laptop.
/// All writes stay inside this instance's temporary directory.
class SafeApp {
  SafeApp._(
    this.directory,
    this.conservationFile, {
    required this._ownsDirectory,
    required this.hasFanFixture,
    required this.hasPowerLimitFixture,
  });

  final Directory directory;
  final File conservationFile;
  final bool _ownsDirectory;
  final bool hasFanFixture;
  final bool hasPowerLimitFixture;
  final powerLimitRequests = <(FixturePowerLimit, int)>[];
  final powerLimitWrites = <(FixturePowerLimit, int)>[];
  FixturePowerLimit? failNextPowerLimit;
  final writes = <bool>[];
  final requests = <bool>[];
  final rapidChargingRequests = <bool>[];
  final rapidChargingWrites = <bool>[];
  FixtureRapidChargingResult rapidChargingResult =
      FixtureRapidChargingResult.applied;
  File get rapidChargingFile => File(
    '${directory.path}/sys/module/legion_laptop/drivers/'
    'platform:legion/legion/rapidcharge',
  );
  final platformProfileWrites = <FixturePlatformProfile>[];
  final platformProfileRequests = <FixturePlatformProfile>[];
  final fanPresetWrites = <ControlFanPreset>[];
  final fanPresetRequests = <ControlFanPreset>[];
  final fanCurveRequests = <List<int>>[];
  final fanCurveCompletions = <List<int>>[];
  FixtureFanCurveResult fanCurveResult = FixtureFanCurveResult.applied;
  ControlFailure? nextFailure;
  Completer<void>? writeCompletion;
  bool _controlCreated = false;
  final _controlClosed = Completer<void>();
  int authorizations = 0;

  /// Caller-created roots survive disposal so separate app processes can share
  /// test storage. The caller owns their cleanup.
  static Future<SafeApp> create({
    Directory? fixtureDirectory,
    bool acOnline = true,
    bool includeFanFixture = false,
    bool includePowerLimitFixture = false,
    bool includeRapidChargingFixture = false,
    List<FixturePlatformProfile> profileChoices = const [
      FixturePlatformProfile.quiet,
      FixturePlatformProfile.balanced,
      FixturePlatformProfile.performance,
      FixturePlatformProfile.maxPower,
    ],
  }) async {
    final ownsDirectory = fixtureDirectory == null;
    final directory =
        fixtureDirectory ??
        await Directory.systemTemp.createTemp('legion_journey_');
    if (!await directory.exists()) {
      throw ArgumentError.value(
        directory.path,
        'fixtureDirectory',
        'The parent must create the fixture directory first',
      );
    }
    await _prepareHardwareFixtures(
      directory,
      profileChoices: profileChoices,
      acOnline: acOnline,
      includeFanFixture: includeFanFixture,
      includePowerLimitFixture: includePowerLimitFixture,
      includeRapidChargingFixture: includeRapidChargingFixture,
    );
    Hive.init('${directory.path}/storage');
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(SensorRecordAdapter());
    }
    await Hive.openBox<SensorRecord>('sensor_records');
    await Hive.openBox<dynamic>('rgb_lighting');
    await Hive.openBox<dynamic>('preferences');
    return SafeApp._(
      directory,
      File(
        '${directory.path}/sys/bus/platform/drivers/ideapad_acpi/'
        'VPC2004:00/conservation_mode',
      ),
      ownsDirectory: ownsDirectory,
      hasFanFixture: includeFanFixture,
      hasPowerLimitFixture: includePowerLimitFixture,
    );
  }

  static Future<void> _prepareHardwareFixtures(
    Directory directory, {
    required List<FixturePlatformProfile> profileChoices,
    required bool acOnline,
    required bool includeFanFixture,
    required bool includePowerLimitFixture,
    required bool includeRapidChargingFixture,
  }) async {
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
    await File('${profile.path}_choices').writeAsString(
      '${profileChoices.map((choice) => choice.wireValue).join(' ')}\n',
    );
    final ac = Directory('${directory.path}/sys/class/power_supply/AC');
    await ac.create(recursive: true);
    await File('${ac.path}/type').writeAsString('Mains\n');
    await File('${ac.path}/online').writeAsString(acOnline ? '1\n' : '0\n');
    await Directory('${directory.path}/proc').create(recursive: true);
    if (includeRapidChargingFixture) {
      final rapidCharge = File(
        '${directory.path}/sys/module/legion_laptop/drivers/'
        'platform:legion/legion/rapidcharge',
      );
      await rapidCharge.parent.create(recursive: true);
      await rapidCharge.writeAsString('0\n');
    }
    if (includeFanFixture) {
      await _prepareFanFixture(directory);
    }
    if (includePowerLimitFixture) {
      final controller = Directory(
        '${directory.path}/sys/module/legion_laptop/drivers/platform:legion/legion',
      );
      await controller.create(recursive: true);
      for (final limit in FixturePowerLimit.values) {
        await File('${controller.path}/${limit.attribute}')
            .writeAsString('${limit.initialValue}\n');
      }
    }
  }

  static Future<void> _prepareFanFixture(Directory directory) async {
    final controller = Directory(
      '${directory.path}/sys/module/legion_laptop/drivers/platform:legion/'
      'legion/hwmon/hwmon0',
    );
    await controller.create(recursive: true);
    await File('${controller.path}/name').writeAsString('legion_hwmon\n');
    await File('${controller.path}/fan1_max').writeAsString('10000\n');
    await File('${controller.path}/fan2_max').writeAsString('9000\n');
    for (var point = 1; point <= 10; point++) {
      final values = <String, int>{
        'pwm1_auto_point${point}_pwm': point * 20,
        'pwm2_auto_point${point}_pwm': point * 20,
        'pwm1_auto_point${point}_temp_hyst': 3,
        'pwm1_auto_point${point}_temp': 30 + point * 5,
        'pwm2_auto_point${point}_temp_hyst': 3,
        'pwm2_auto_point${point}_temp': 32 + point * 5,
        'pwm3_auto_point${point}_temp_hyst': 2,
        'pwm3_auto_point${point}_temp': 35 + point * 5,
        'pwm1_auto_point${point}_accel': 4,
        'pwm1_auto_point${point}_decel': 8,
      };
      for (final entry in values.entries) {
        await File('${controller.path}/${entry.key}')
            .writeAsString('${entry.value}\n');
      }
    }
  }

  Future<void> launch({List<Override> additionalOverrides = const []}) async {
    await YaruWindowTitleBar.ensureInitialized();
    final sysfs = LegionSysfsService(
      sysRoot: '${directory.path}/sys',
      procRoot: '${directory.path}/proc',
    );
    runApp(
      ProviderScope(
        overrides: _mergeOverrides([
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
          packagePowerTelemetryClientProvider.overrideWithValue(
            _NoPackagePower(),
          ),
          // Keep the real sensor provider/Bloc with synthetic hardware readings.
          liveSensorRepositoryProvider.overrideWithValue(_NoLiveSensors()),
          appearanceStoreProvider.overrideWithValue(
            AppearanceStore(Hive.box<dynamic>('preferences')),
          ),
        ], additionalOverrides),
        child: const LegionFrontendApp(),
      ),
    );
  }

  static List<Override> _mergeOverrides(
    List<Override> defaults,
    List<Override> additional,
  ) {
    final merged = [...defaults];
    for (final override in additional) {
      merged.removeWhere((existing) => existing.origin == override.origin);
      merged.add(override);
    }
    return merged;
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
      if (_ownsDirectory) {
        await directory.delete(recursive: true);
      }
    }
  }
}

class _FixtureControl extends LegionControlTransport {
  _FixtureControl(this.app);
  final SafeApp app;

  @override
  Future<ControlCapabilities> getCapabilities() async => ControlCapabilities(
    protocolVersion: ControlCapabilities.currentProtocolVersion,
    supported: const [ControlCapability.interactiveControl],
  );

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
    if (method == 'ApplyFanCurve' &&
        app.hasFanFixture &&
        arguments.length == 1 &&
        arguments.single is List<int>) {
      final bytes = List<int>.unmodifiable(arguments.single as List<int>);
      if (utf8.decode(bytes) != _editedFixtureCurve()) {
        throw StateError('Unexpected synthetic fan-curve payload');
      }
      app.fanCurveRequests.add(bytes);
      if (app.nextFailure == ControlFailure.commandFailed) {
        app.nextFailure = null;
        throw const LegionControlCommandFailedException(
          'Test backend rejected the fan curve. Fix the backend and retry.',
        );
      }
      await app.writeCompletion?.future;
      if (app.fanCurveResult == FixtureFanCurveResult.applied) {
        final controller =
            '${app.directory.path}/sys/module/legion_laptop/'
            'drivers/platform:legion/legion/hwmon/hwmon0';
        for (final entry in const {
          'pwm1_auto_point1_pwm': 40,
          'pwm2_auto_point1_pwm': 40,
          'pwm1_auto_point1_temp': 40,
          'pwm2_auto_point1_temp': 42,
        }.entries) {
          await File('$controller/${entry.key}')
              .writeAsString('${entry.value}\n');
        }
      }
      app.fanCurveCompletions.add(bytes);
      return;
    }
    if (method == 'SetToggle' &&
        arguments.length == 2 &&
        arguments.first == ControlToggle.rapidCharging.wireValue &&
        arguments.last is bool &&
        await app.rapidChargingFile.exists()) {
      final enabled = arguments.last as bool;
      app.rapidChargingRequests.add(enabled);
      if (app.nextFailure == ControlFailure.commandFailed) {
        app.nextFailure = null;
        throw const LegionControlCommandFailedException(
          'Test backend rejected the write. Fix the backend and retry.',
        );
      }
      await app.writeCompletion?.future;
      if (app.rapidChargingResult != FixtureRapidChargingResult.unchanged) {
        await app.rapidChargingFile.writeAsString(enabled ? '1\n' : '0\n');
        app.rapidChargingWrites.add(enabled);
      }
      if (app.rapidChargingResult ==
          FixtureRapidChargingResult.readbackUnavailable) {
        await app.rapidChargingFile.delete();
      }
      return;
    }
    if (method == 'SetFeature' &&
        app.hasPowerLimitFixture &&
        arguments.length == 2 &&
        arguments.last is String) {
      final limit = FixturePowerLimit.values
          .where((limit) => limit.feature.wireValue == arguments.first)
          .firstOrNull;
      if (limit != null) {
        final value = int.tryParse(arguments.last as String);
        final minimum = limit == FixturePowerLimit.gpu ? 1 : 5;
        if (value == null || value < minimum || value > 200) {
          throw StateError('Unexpected power limit: $arguments');
        }
        app.powerLimitRequests.add((limit, value));
        if (app.failNextPowerLimit == limit) {
          app.failNextPowerLimit = null;
          throw const LegionControlCommandFailedException(
            'Test backend rejected the power limit. Retry after recovery.',
          );
        }
        await app.writeCompletion?.future;
        await File(
          '${app.directory.path}/sys/module/legion_laptop/drivers/'
          'platform:legion/legion/${limit.attribute}',
        ).writeAsString('$value\n');
        app.powerLimitWrites.add((limit, value));
        return;
      }
    }
    if (method == 'ApplyFanPreset' &&
        app.hasFanFixture &&
        arguments.length == 1 &&
        arguments.single is String) {
      final preset = ControlFanPreset.values
          .where((value) => value.wireValue == arguments.single)
          .firstOrNull;
      if (preset == null) {
        throw StateError('Unexpected fan preset: ${arguments.single}');
      }
      app.fanPresetRequests.add(preset);
      if (app.nextFailure == ControlFailure.commandFailed) {
        app.nextFailure = null;
        throw const LegionControlCommandFailedException(
          'Test backend rejected the write. Fix the backend and retry.',
        );
      }
      await app.writeCompletion?.future;
      await _writeFanPreset(preset);
      app.fanPresetWrites.add(preset);
      return;
    }
    if (method == 'SetFeature' &&
        arguments.length == 2 &&
        arguments.first == ControlFeature.platformProfile.wireValue &&
        arguments.last is String) {
      final profile = FixturePlatformProfile.values
          .where((value) => value.wireValue == arguments.last)
          .firstOrNull;
      if (profile == null) {
        throw StateError('Unexpected platform profile: ${arguments.last}');
      }
      app.platformProfileRequests.add(profile);
      if (app.nextFailure == ControlFailure.commandFailed) {
        app.nextFailure = null;
        throw const LegionControlCommandFailedException(
          'Test backend rejected the write. Fix the backend and retry.',
        );
      }
      await app.writeCompletion?.future;
      final profileFile = File(
        '${app.directory.path}/sys/firmware/acpi/platform_profile',
      );
      await profileFile.writeAsString('${profile.wireValue}\n');
      app.platformProfileWrites.add(profile);
      return;
    }
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

  Future<void> _writeFanPreset(ControlFanPreset preset) async {
    final controller =
        '${app.directory.path}/sys/module/legion_laptop/'
        'drivers/platform:legion/legion/hwmon/hwmon0';
    // Synthetic steps distinguish preset readback; these are not laptop curves.
    final pwmStep = switch (preset) {
      ControlFanPreset.quietBattery || ControlFanPreset.quietAc => 12,
      ControlFanPreset.balancedBattery || ControlFanPreset.balancedAc => 16,
      ControlFanPreset.performanceBattery ||
      ControlFanPreset.performanceAc => 24,
      ControlFanPreset.balancedPerformanceBattery ||
      ControlFanPreset.balancedPerformanceAc => 18,
    };
    for (var point = 1; point <= 10; point++) {
      final pwm = (point * pwmStep).clamp(0, 255);
      await File('$controller/pwm1_auto_point${point}_pwm')
          .writeAsString('$pwm\n');
      await File('$controller/pwm2_auto_point${point}_pwm')
          .writeAsString('$pwm\n');
    }
  }

  @override
  Future<void> close() async => app._controlClosed.complete();
}

// Independent expected wire document for edits to the synthetic table's first
// CPU/GPU point. Do not use FanCurve.toYaml: this also checks its serialization.
String _editedFixtureCurve() {
  final document = StringBuffer('name: custom\nentries:\n');
  for (var point = 1; point <= 10; point++) {
    final pwm = point == 1 ? 40 : point * 20;
    document
      ..writeln('- fan1_speed: ${(pwm / 255 * 10000).round()}.0')
      ..writeln('  fan2_speed: ${(pwm / 255 * 9000).round()}.0')
      ..writeln('  cpu_lower_temp: 3')
      ..writeln('  cpu_upper_temp: ${point == 1 ? 40 : 30 + point * 5}')
      ..writeln('  gpu_lower_temp: 3')
      ..writeln('  gpu_upper_temp: ${point == 1 ? 42 : 32 + point * 5}')
      ..writeln('  ic_lower_temp: 2')
      ..writeln('  ic_upper_temp: ${35 + point * 5}')
      ..writeln('  acceleration: 4')
      ..writeln('  deceleration: 8');
  }
  document.writeln('enable_minifancurve: true');
  return document.toString();
}

extension on FixturePlatformProfile {
  String get wireValue => switch (this) {
    FixturePlatformProfile.quiet => 'quiet',
    FixturePlatformProfile.balanced => 'balanced',
    FixturePlatformProfile.performance => 'performance',
    FixturePlatformProfile.maxPower => 'max-power',
    FixturePlatformProfile.custom => 'custom',
  };
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
  Future<GpuReading?> readSnapshot() async => null;
}

class _NoPackagePower implements PackagePowerTelemetryClient {
  @override
  Future<void> enable() async =>
      throw StateError('CPU power access is outside this journey');

  @override
  Future<void> disable() async =>
      throw StateError('CPU power access is outside this journey');

  @override
  Future<double?> readPackagePowerWatts() async => null;
}

class _NoLiveSensors implements LiveSensorRepository {
  @override
  Future<LiveSensorSnapshot> loadSnapshot() async =>
      LiveSensorSnapshot.initial();
}
