import 'package:dbus/dbus.dart';

import '../models/power_profiles_daemon_snapshot.dart';
import 'legion_sysfs_service.dart';

class PowerProfileServiceException implements Exception {
  const PowerProfileServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class PowerProfilesDaemonClient {
  Future<PowerProfilesDaemonSnapshot?> loadSnapshot();

  Future<void> setActiveProfile(String profile);
}

class DBusPowerProfilesDaemonClient implements PowerProfilesDaemonClient {
  DBusPowerProfilesDaemonClient({DBusClient? client})
    : _client = client ?? DBusClient.system() {
    _object = DBusRemoteObject(
      _client,
      name: _busName,
      path: DBusObjectPath(_objectPath),
    );
  }

  static const _busName = 'org.freedesktop.UPower.PowerProfiles';
  static const _objectPath = '/org/freedesktop/UPower/PowerProfiles';
  static const _interface = 'org.freedesktop.UPower.PowerProfiles';
  static const _profiles = {'power-saver', 'balanced', 'performance'};

  final DBusClient _client;
  late final DBusRemoteObject _object;

  @override
  Future<PowerProfilesDaemonSnapshot?> loadSnapshot() async {
    try {
      final properties = await _object
          .getAllProperties(_interface)
          .timeout(const Duration(seconds: 3));
      return parseProperties(properties);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> setActiveProfile(String profile) async {
    if (!_profiles.contains(profile)) {
      throw PowerProfileServiceException(
        'Power Profiles Daemon does not support "$profile".',
      );
    }

    try {
      await _object
          .callMethod(
            'org.freedesktop.DBus.Properties',
            'Set',
            [
              const DBusString(_interface),
              const DBusString('ActiveProfile'),
              DBusVariant(DBusString(profile)),
            ],
            replySignature: DBusSignature(''),
            allowInteractiveAuthorization: true,
          )
          .timeout(const Duration(seconds: 10));
    } catch (error) {
      throw PowerProfileServiceException(
        'Failed to set the system power profile: $error',
      );
    }
  }

  static PowerProfilesDaemonSnapshot? parseProperties(
    Map<String, DBusValue> properties,
  ) {
    final active = _stringProperty(properties, 'ActiveProfile');
    final profileValue = properties['Profiles'];
    if (active == null || profileValue == null) return null;

    try {
      final profiles = <PowerProfileDescriptor>[];
      for (final value in profileValue.asArray()) {
        final fields = value.asStringVariantDict();
        final profile = _stringProperty(fields, 'Profile');
        if (profile == null) continue;
        profiles.add(
          PowerProfileDescriptor(
            profile: profile,
            cpuDriver: _stringProperty(fields, 'CpuDriver'),
            platformDriver: _stringProperty(fields, 'PlatformDriver'),
          ),
        );
      }
      if (profiles.isEmpty) return null;

      return PowerProfilesDaemonSnapshot(
        activeProfile: active,
        profiles: List.unmodifiable(profiles),
        batteryAware: _boolProperty(properties, 'BatteryAware'),
        version: _stringProperty(properties, 'Version'),
        performanceDegraded: _stringProperty(properties, 'PerformanceDegraded'),
      );
    } catch (_) {
      return null;
    }
  }

  static String? _stringProperty(Map<String, DBusValue> values, String name) {
    final value = values[name];
    return value is DBusString ? value.value : null;
  }

  static bool? _boolProperty(Map<String, DBusValue> values, String name) {
    final value = values[name];
    return value is DBusBoolean ? value.value : null;
  }

  Future<void> close() => _client.close();
}

class PowerProfileService {
  const PowerProfileService({
    required LegionSysfsService sysfsService,
    required PowerProfilesDaemonClient daemonClient,
  }) : _sysfsService = sysfsService,
       _daemonClient = daemonClient;

  final LegionSysfsService _sysfsService;
  final PowerProfilesDaemonClient _daemonClient;

  Future<PowerProfilesDaemonSnapshot?> loadDaemonSnapshot() =>
      _daemonClient.loadSnapshot();

  List<String> availableProfiles({
    required List<String> hardwareProfiles,
    required PowerProfilesDaemonSnapshot? daemon,
  }) {
    if (daemon == null) return _unique(hardwareProfiles);

    final values = <String>[];
    for (final descriptor in daemon.profiles) {
      final value = platformValueForDaemonProfile(
        descriptor.profile,
        hardwareProfiles,
      );
      if (value != null &&
          (hardwareProfiles.isEmpty || hardwareProfiles.contains(value)) &&
          !values.contains(value)) {
        values.add(value);
      }
    }
    for (final value in hardwareProfiles) {
      if (daemonProfileForPlatformValue(value) == null &&
          !values.contains(value)) {
        values.add(value);
      }
    }
    return values;
  }

  Future<void> setProfile(
    String platformProfile, {
    required Future<void> Function(String profile) writePlatformProfile,
  }) async {
    final hardwareProfiles = await _sysfsService.readPlatformProfileChoices();
    final daemon = await _daemonClient.loadSnapshot();
    final daemonProfile = daemonProfileForPlatformValue(platformProfile);
    final writeTarget = daemonProfile == null
        ? platformProfile.trim()
        : platformValueForDaemonProfile(daemonProfile, hardwareProfiles) ??
              platformProfile.trim();

    if (hardwareProfiles.isNotEmpty &&
        !hardwareProfiles.contains(writeTarget)) {
      throw PowerProfileServiceException(
        'The firmware does not expose the "$writeTarget" power profile.',
      );
    }

    if (daemonProfile != null && daemon?.supports(daemonProfile) == true) {
      await _daemonClient.setActiveProfile(daemonProfile);

      // PPD ignores max-power/custom changes, so setting its already-active
      // profile can be a no-op when returning to a standard firmware mode.
      final current = await _sysfsService.readPlatformProfile();
      if (current != null &&
          daemonProfileForPlatformValue(current) != daemonProfile) {
        await writePlatformProfile(writeTarget);
      }
      return;
    }

    if (daemonProfile == null && daemon?.supports('performance') == true) {
      // Vendor-only modes have no PPD representation. Pair them with its
      // performance CPU policy before selecting the firmware profile.
      await _daemonClient.setActiveProfile('performance');
    }
    await writePlatformProfile(writeTarget);
  }

  static String? daemonProfileForPlatformValue(String value) {
    return switch (value.trim()) {
      'power-saver' || 'quiet' || 'low-power' => 'power-saver',
      'balanced' => 'balanced',
      'performance' => 'performance',
      _ => null,
    };
  }

  static String? platformValueForDaemonProfile(
    String profile,
    List<String> hardwareProfiles,
  ) {
    return switch (profile) {
      'power-saver' =>
        hardwareProfiles.contains('low-power')
            ? 'low-power'
            : hardwareProfiles.contains('quiet')
            ? 'quiet'
            : 'power-saver',
      'balanced' => 'balanced',
      'performance' => 'performance',
      _ => null,
    };
  }

  static List<String> _unique(Iterable<String> values) {
    final result = <String>[];
    for (final raw in values) {
      final value = raw.trim();
      if (value.isNotEmpty && !result.contains(value)) result.add(value);
    }
    return result;
  }
}
