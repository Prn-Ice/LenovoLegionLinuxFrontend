import 'dart:io';

import '../../../core/services/legion_frontend_bridge_service.dart';
import '../../../core/services/legion_sysfs_service.dart';
import '../models/battery_snapshot.dart';

class BatteryRepositoryException implements Exception {
  const BatteryRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}

class BatteryRepository {
  const BatteryRepository({
    required LegionSysfsService sysfsService,
    required LegionFrontendBridgeService bridgeService,
  }) : _sysfsService = sysfsService,
       _bridgeService = bridgeService;

  final LegionSysfsService _sysfsService;
  final LegionFrontendBridgeService _bridgeService;

  Future<BatterySnapshot> loadSnapshot() async {
    final results = await Future.wait([
      _sysfsService.readBatteryConservationMode(),
      _sysfsService.readRapidChargingMode(),
      _sysfsService.readIntFile('/sys/class/power_supply/BAT0/capacity'),
      _readBatteryStatus(),
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

  Future<String?> _readBatteryStatus() async {
    try {
      final file = File('/sys/class/power_supply/BAT0/status');
      if (!await file.exists()) return null;
      return (await file.readAsString()).trim();
    } catch (_) {
      return null;
    }
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

      throw BatteryRepositoryException(message);
    }
  }
}
