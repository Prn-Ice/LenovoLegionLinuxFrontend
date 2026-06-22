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
}
