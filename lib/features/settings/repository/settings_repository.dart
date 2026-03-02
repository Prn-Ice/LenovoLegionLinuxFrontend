import 'dart:io';

import '../models/service_control.dart';
import '../models/settings_snapshot.dart';

class SettingsRepositoryException implements Exception {
  const SettingsRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}

class SettingsRepository {
  SettingsRepository();

  static final List<ServiceControl> _serviceDefinitions = [
    const ServiceControl(
      id: 'power_profiles_daemon',
      label: 'power-profiles-daemon',
      units: ['power-profiles-daemon'],
      supported: false,
      active: false,
      enabled: false,
    ),
    const ServiceControl(
      id: 'legiond_stack',
      label: 'legiond services',
      units: [
        'legiond.service',
        'legiond-onresume.service',
        'legiond-cpuset.service',
        'legiond-cpuset.timer',
      ],
      supported: false,
      active: false,
      enabled: false,
    ),
  ];

  Future<SettingsSnapshot> loadSnapshot() async {
    final services = <ServiceControl>[];

    for (final definition in _serviceDefinitions) {
      bool allSupported = true;
      bool allActive = true;
      bool allEnabled = true;

      for (final unit in definition.units) {
        final status = await _readUnitStatus(unit);
        if (!status.supported) {
          allSupported = false;
        }
        if (!status.active) {
          allActive = false;
        }
        if (!status.enabled) {
          allEnabled = false;
        }
      }

      services.add(
        definition.copyWith(
          supported: allSupported,
          active: allSupported && allActive,
          enabled: allSupported && allEnabled,
        ),
      );
    }

    return SettingsSnapshot(services: services);
  }

  Future<void> setServiceEnabled(ServiceControl service, bool enabled) async {
    if (!service.supported) {
      throw SettingsRepositoryException(
        'Service ${service.label} is not supported on this system.',
      );
    }

    final action = enabled ? 'start' : 'stop';
    final enableAction = enabled ? 'enable' : 'disable';

    for (final unit in service.units) {
      await _runPrivilegedSystemctl([action, unit], service.label);
      await _runPrivilegedSystemctl([enableAction, unit], service.label);
    }
  }

  Future<void> _runPrivilegedSystemctl(List<String> args, String label) async {
    final result = await Process.run('pkexec', ['systemctl', ...args]);
    if (result.exitCode == 0) {
      return;
    }

    final stderr = '${result.stderr}'.trim();
    final stdout = '${result.stdout}'.trim();
    final details = [
      if (stderr.isNotEmpty) stderr,
      if (stdout.isNotEmpty) stdout,
    ].join('\n');

    final message = details.isEmpty
        ? 'Failed to run systemctl ${args.join(' ')} for $label.'
        : 'Failed to run systemctl ${args.join(' ')} for $label: $details';

    throw SettingsRepositoryException(message);
  }

  Future<_UnitStatus> _readUnitStatus(String unit) async {
    final isActive = await _runSystemctl(['is-active', unit]);
    final isEnabled = await _runSystemctl(['is-enabled', unit]);

    if (isActive.notFound || isEnabled.notFound) {
      return const _UnitStatus(supported: false, active: false, enabled: false);
    }

    return _UnitStatus(
      supported: true,
      active: isActive.success,
      enabled: isEnabled.success,
    );
  }

  Future<_SystemctlResult> _runSystemctl(List<String> args) async {
    try {
      final result = await Process.run('systemctl', args);
      final stdout = '${result.stdout}'.trim().toLowerCase();
      final stderr = '${result.stderr}'.trim().toLowerCase();
      final combined = '$stdout\n$stderr';
      final notFound =
          combined.contains('not-found') ||
          combined.contains('could not be found') ||
          result.exitCode == 4;

      return _SystemctlResult(
        success: result.exitCode == 0,
        notFound: notFound,
      );
    } on ProcessException {
      return const _SystemctlResult(success: false, notFound: true);
    }
  }
}

class _SystemctlResult {
  const _SystemctlResult({required this.success, required this.notFound});

  final bool success;
  final bool notFound;
}

class _UnitStatus {
  const _UnitStatus({
    required this.supported,
    required this.active,
    required this.enabled,
  });

  final bool supported;
  final bool active;
  final bool enabled;
}
