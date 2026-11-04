import '../../../core/data/privileged_repository.dart';
import '../../../core/models/app_failure.dart';
import '../../../core/models/control_selectors.dart';
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
    await runControlOperation(
      (client) => client.setToggle(ControlToggle.touchpad, enabled),
      args: ['$enabled'],
      method: 'touchpad.set',
      failurePrefix: 'Failed to set touchpad to ${enabled ? 'on' : 'off'}',
    );
  }

  Future<void> setWinKey(bool enabled) async {
    await runControlOperation(
      (client) => client.setFeature(ControlFeature.winkey, enabled ? '1' : '0'),
      args: [ControlFeature.winkey.wireValue, '$enabled'],
      method: 'feature.set',
      failurePrefix: 'Failed to set Win key to ${enabled ? 'on' : 'off'}',
    );
  }

  Future<void> setFnLock(bool enabled) async {
    await runControlOperation(
      (client) => client.setToggle(ControlToggle.fnLock, enabled),
      args: ['$enabled'],
      method: 'fn_lock.set',
      failurePrefix: 'Failed to set Fn lock to ${enabled ? 'on' : 'off'}',
    );
  }

  Future<void> setCamera(bool enabled) async {
    throw const DevicesRepositoryException(
      'Camera writes are not supported by the control service.',
      kind: AppFailureKind.unavailable,
    );
  }
}
