import '../../../core/models/app_failure.dart';
import '../../../core/data/privileged_repository.dart';
import '../../../core/services/legion_sysfs_service.dart';
import '../models/devices_snapshot.dart';

class DevicesRepositoryException extends AppFailure {
  const DevicesRepositoryException(super.message, {super.kind, super.details});
}

class DevicesRepository extends PrivilegedRepository {
  const DevicesRepository({
    required LegionSysfsService sysfsService,
    required super.bridgeService,
  }) : _sysfsService = sysfsService;

  @override
  Exception wrapBridgeError(AppFailure failure) => DevicesRepositoryException(
    failure.message,
    kind: failure.kind,
    details: failure.details,
  );

  final LegionSysfsService _sysfsService;

  Future<DevicesSnapshot> loadSnapshot() async {
    final touchpad = await _sysfsService.readTouchpadMode();
    final winKey = await _sysfsService.readWinKeyMode();
    final fnLock = await _sysfsService.readFnLockMode();
    final camera = await _sysfsService.readCameraPowerMode();

    return DevicesSnapshot(
      touchpadEnabled: touchpad,
      touchpadSupported: touchpad != null,
      winKeyEnabled: winKey,
      winKeySupported: winKey != null,
      fnLockEnabled: fnLock,
      fnLockSupported: fnLock != null,
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

  Future<void> setCamera(bool enabled) async {
    final command = enabled ? 'camera-enable' : 'camera-disable';
    await runPrivilegedCommand(
      [command],
      method: 'camera.set',
      failurePrefix: 'Failed to set camera to ${enabled ? 'on' : 'off'}',
    );
  }
}
