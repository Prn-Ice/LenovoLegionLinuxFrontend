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
    final batteryConservation =
        await _sysfsService.readBatteryConservationMode();
    final rapidCharging = await _sysfsService.readRapidChargingMode();
    final batteryPercent = await _sysfsService.readIntFile(
      '/sys/class/power_supply/BAT0/capacity',
    );
    final batteryStatusStr = await _readBatteryStatus();
    final batteryPowerDrawW = await _sysfsService.readBatteryPowerDrawW();
    final cycleCounts = await _sysfsService.readBatteryCycleCount();
    final fullCapacityWh = await _sysfsService.readBatteryFullCapacityWh();
    final designCapacityWh = await _sysfsService.readBatteryDesignCapacityWh();
    final currentCapacityWh =
        await _sysfsService.readBatteryCurrentCapacityWh();
    final batteryTempC = await _sysfsService.readBatteryTempC();

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
