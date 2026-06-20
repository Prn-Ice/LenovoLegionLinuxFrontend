import '../../../core/data/privileged_repository.dart';
import '../../../core/services/legion_sysfs_service.dart';
import '../models/devices_snapshot.dart';

class DevicesRepositoryException implements Exception {
  const DevicesRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}

class DevicesRepository extends PrivilegedRepository {
  // Keep writes gated until backend/CLI support for always-on USB is
  // verified end-to-end (see roadmap item okf.4).
  static const bool _alwaysOnUsbWriteSupported = false;

  const DevicesRepository({
    required LegionSysfsService sysfsService,
    required super.bridgeService,
  }) : _sysfsService = sysfsService;

  @override
  Exception wrapBridgeError(String message) =>
      DevicesRepositoryException(message);

  final LegionSysfsService _sysfsService;

  Future<DevicesSnapshot> loadSnapshot() async {
    final touchpad = await _sysfsService.readTouchpadMode();
    final winKey = await _sysfsService.readWinKeyMode();
    final fnLock = await _sysfsService.readFnLockMode();
    final alwaysOnUsb = await _sysfsService.readAlwaysOnUsbChargingMode();
    final camera = await _sysfsService.readCameraPowerMode();

    return DevicesSnapshot(
      touchpadEnabled: touchpad,
      touchpadSupported: touchpad != null,
      winKeyEnabled: winKey,
      winKeySupported: winKey != null,
      fnLockEnabled: fnLock,
      fnLockSupported: fnLock != null,
      alwaysOnUsbEnabled: alwaysOnUsb,
      alwaysOnUsbSupported: _alwaysOnUsbWriteSupported,
      cameraEnabled: camera,
      cameraSupported: camera != null,
    );
  }

  Future<void> setTouchpad(bool enabled) async {
    final command = enabled ? 'touchpad-enable' : 'touchpad-disable';
    await runPrivilegedCommand(
      [command],
      method: 'touchpad.set',
      failurePrefix: 'Failed to set touchpad to ${enabled ? 'on' : 'off'}',
    );
  }

  Future<void> setWinKey(bool enabled) async {
    await runPrivilegedCommand(
      ['set-feature', 'WinkeyFeature', enabled ? '1' : '0'],
      method: 'feature.set',
      failurePrefix: 'Failed to set Win key to ${enabled ? 'on' : 'off'}',
    );
  }

  Future<void> setFnLock(bool enabled) async {
    final command = enabled ? 'fnlock-enable' : 'fnlock-disable';
    await runPrivilegedCommand(
      [command],
      method: 'fn_lock.set',
      failurePrefix: 'Failed to set Fn lock to ${enabled ? 'on' : 'off'}',
    );
  }

  Future<void> setAlwaysOnUsb(bool enabled) async {
    if (!_alwaysOnUsbWriteSupported) {
      throw const DevicesRepositoryException(
        'Always-on USB is currently read-only because backend write support is not available yet.',
      );
    }

    final command = enabled
        ? 'always-on-usb-charging-enable'
        : 'always-on-usb-charging-disable';
    await runPrivilegedCommand(
      [command],
      method: 'always_on_usb.set',
      failurePrefix:
          'Failed to set always-on USB charging to ${enabled ? 'on' : 'off'}',
    );
  }

  Future<void> setCamera(bool enabled) async {
    final command = enabled ? 'camera-enable' : 'camera-disable';
    await runPrivilegedCommand(
      [command],
      method: 'camera.set',
      failurePrefix: 'Failed to set camera to ${enabled ? 'on' : 'off'}',
    );
  }
}
