import '../../../core/services/legion_frontend_bridge_service.dart';
import '../../../core/services/legion_sysfs_service.dart';
import '../models/battery_devices_snapshot.dart';

class BatteryDevicesRepositoryException implements Exception {
  const BatteryDevicesRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}

class BatteryDevicesRepository {
  // Keep writes gated until backend/CLI support for always-on USB is
  // verified end-to-end (see roadmap item okf.4).
  static const bool _alwaysOnUsbWriteSupported = false;

  const BatteryDevicesRepository({
    required LegionSysfsService sysfsService,
    required LegionFrontendBridgeService bridgeService,
  }) : _sysfsService = sysfsService,
       _bridgeService = bridgeService;

  final LegionSysfsService _sysfsService;
  final LegionFrontendBridgeService _bridgeService;

  Future<BatteryDevicesSnapshot> loadSnapshot() async {
    final batteryConservation = await _sysfsService
        .readBatteryConservationMode();
    final rapidCharging = await _sysfsService.readRapidChargingMode();
    final alwaysOnUsb = await _sysfsService.readAlwaysOnUsbChargingMode();
    final touchpad = await _sysfsService.readTouchpadMode();
    final winKey = await _sysfsService.readWinKeyMode();
    final cameraPower = await _sysfsService.readCameraPowerMode();
    final fnLock = await _sysfsService.readFnLockMode();

    return BatteryDevicesSnapshot(
      batteryConservationEnabled: batteryConservation,
      rapidChargingEnabled: rapidCharging,
      alwaysOnUsbChargingEnabled: alwaysOnUsb,
      alwaysOnUsbWriteSupported: _alwaysOnUsbWriteSupported,
      touchpadEnabled: touchpad,
      winKeyEnabled: winKey,
      cameraPowerEnabled: cameraPower,
      fnLockEnabled: fnLock,
    );
  }

  Future<void> setBatteryConservation(bool enabled) async {
    final command = enabled
        ? 'batteryconservation-enable'
        : 'batteryconservation-disable';
    await _runPrivilegedCommand(
      [command],
      method: 'battery_conservation.set',
      failurePrefix:
          'Failed to set battery conservation to ${enabled ? 'on' : 'off'}',
    );
  }

  Future<void> setRapidCharging(bool enabled) async {
    final command = enabled
        ? 'rapid-charging-enable'
        : 'rapid-charging-disable';
    await _runPrivilegedCommand(
      [command],
      method: 'rapid_charging.set',
      failurePrefix:
          'Failed to set rapid charging to ${enabled ? 'on' : 'off'}',
    );
  }

  Future<void> setTouchpad(bool enabled) async {
    final command = enabled ? 'touchpad-enable' : 'touchpad-disable';
    await _runPrivilegedCommand(
      [command],
      method: 'touchpad.set',
      failurePrefix: 'Failed to set touchpad to ${enabled ? 'on' : 'off'}',
    );
  }

  Future<void> setWinKey(bool enabled) async {
    await _runPrivilegedCommand(
      ['set-feature', 'WinkeyFeature', enabled ? '1' : '0'],
      method: 'feature.set',
      failurePrefix: 'Failed to set Win key to ${enabled ? 'on' : 'off'}',
    );
  }

  Future<void> setFnLock(bool enabled) async {
    final command = enabled ? 'fnlock-enable' : 'fnlock-disable';
    await _runPrivilegedCommand(
      [command],
      method: 'fn_lock.set',
      failurePrefix: 'Failed to set Fn lock to ${enabled ? 'on' : 'off'}',
    );
  }

  Future<void> setAlwaysOnUsbCharging(bool enabled) async {
    // Guardrail: avoid attempting privileged writes while the upstream
    // implementation is intentionally read-only.
    if (!_alwaysOnUsbWriteSupported) {
      throw const BatteryDevicesRepositoryException(
        'Always-on USB is currently read-only because backend write support is not available yet.',
      );
    }

    final command = enabled
        ? 'always-on-usb-charging-enable'
        : 'always-on-usb-charging-disable';
    await _runPrivilegedCommand(
      [command],
      method: 'always_on_usb.set',
      failurePrefix:
          'Failed to set always-on USB charging to ${enabled ? 'on' : 'off'}',
    );
  }

  Future<void> _runPrivilegedCommand(
    List<String> args, {
    required String method,
    required String failurePrefix,
    bool detectUnavailableResponse = true,
  }) async {
    try {
      await _bridgeService.runPrivilegedCommand(
        method: method,
        args: args,
        detectUnavailableResponse: detectUnavailableResponse,
      );
    } on LegionBridgeException catch (error) {
      final details = error.details;
      final message = details.isEmpty
          ? '$failurePrefix.'
          : '$failurePrefix: $details';

      throw BatteryDevicesRepositoryException(message);
    }
  }
}
