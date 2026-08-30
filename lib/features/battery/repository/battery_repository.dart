import '../../../core/data/privileged_repository.dart';
import '../../../core/services/legion_sysfs_service.dart';
import '../models/battery_snapshot.dart';

class BatteryRepositoryException implements Exception {
  const BatteryRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}

class BatteryRepository extends PrivilegedRepository {
  static const bool _alwaysOnUsbWriteSupported = false;

  const BatteryRepository({
    required LegionSysfsService sysfsService,
    required super.bridgeService,
  }) : _sysfsService = sysfsService;

  @override
  Exception wrapBridgeError(String message) =>
      BatteryRepositoryException(message);

  final LegionSysfsService _sysfsService;

  Future<BatterySnapshot> loadSnapshot() async {
    final results = await Future.wait([
      _sysfsService.readBatteryConservationMode(),
      _sysfsService.readRapidChargingMode(),
      _sysfsService.readBatteryPercent(),
      _sysfsService.readBatteryStatus(),
      _sysfsService.readBatteryPowerDrawW(),
      _sysfsService.readBatteryCycleCount(),
      _sysfsService.readBatteryFullCapacityWh(),
      _sysfsService.readBatteryDesignCapacityWh(),
      _sysfsService.readBatteryCurrentCapacityWh(),
      _sysfsService.readBatteryTempC(),
      _sysfsService.readAlwaysOnUsbChargingMode(),
      _sysfsService.readBatteryVoltageV(),
      _sysfsService.readBatteryManufacturer(),
      _sysfsService.readBatteryModelName(),
      _sysfsService.readBatterySerialNumber(),
    ]);

    final batteryConservation = results[0] as bool?;
    final rapidCharging = results[1] as bool?;
    final batteryPercent = results[2] as int?;
    final batteryStatusStr = results[3] as String?;
    final batteryPowerDrawW = results[4] as double?;
    final cycleCounts = results[5] as int?;
    final fullCapacityWh = results[6] as double?;
    final designCapacityWh = results[7] as double?;
    final currentCapacityWh = results[8] as double?;
    final batteryTempC = results[9] as double?;
    final alwaysOnUsb = results[10] as bool?;

    return BatterySnapshot(
      batteryConservationEnabled: batteryConservation,
      batteryConservationSupported: batteryConservation != null,
      rapidChargingEnabled: rapidCharging,
      rapidChargingSupported: rapidCharging != null,
      batteryPercent: batteryPercent,
      batteryCharging: batteryStatusStr == null
          ? null
          : batteryStatusStr == 'Charging',
      batteryPowerDrawW: batteryPowerDrawW,
      cycleCounts: cycleCounts,
      fullCapacityWh: fullCapacityWh,
      designCapacityWh: designCapacityWh,
      currentCapacityWh: currentCapacityWh,
      batteryTempC: batteryTempC,
      batteryStatus: batteryStatusStr,
      alwaysOnUsbEnabled: alwaysOnUsb,
      alwaysOnUsbSupported: _alwaysOnUsbWriteSupported,
      voltageV: results[11] as double?,
      manufacturer: results[12] as String?,
      modelName: results[13] as String?,
      serialNumber: results[14] as String?,
    );
  }

  Future<void> setBatteryConservation(bool enabled) async {
    final command = enabled
        ? 'batteryconservation-enable'
        : 'batteryconservation-disable';
    await runPrivilegedCommand(
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
    await runPrivilegedCommand(
      [command],
      method: 'rapid_charging.set',
      failurePrefix:
          'Failed to set rapid charging to ${enabled ? 'on' : 'off'}',
    );
  }

  Future<void> setAlwaysOnUsb(bool enabled) async {
    if (!_alwaysOnUsbWriteSupported) {
      throw const BatteryRepositoryException(
        'Always-on USB is read-only because backend write support is not available.',
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
}
