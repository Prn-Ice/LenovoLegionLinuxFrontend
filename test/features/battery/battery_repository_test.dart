import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/services/legion_frontend_bridge_service.dart';
import 'package:legion_frontend/core/services/legion_sysfs_service.dart';
import 'package:legion_frontend/features/battery/repository/battery_repository.dart';
import 'package:mocktail/mocktail.dart';

class _MockSysfsService extends Mock implements LegionSysfsService {}

class _MockBridgeService extends Mock implements LegionFrontendBridgeService {}

void main() {
  late _MockSysfsService sysfs;
  late BatteryRepository repository;

  setUp(() {
    sysfs = _MockSysfsService();
    repository = BatteryRepository(
      sysfsService: sysfs,
      bridgeService: _MockBridgeService(),
    );
    when(sysfs.readBatteryConservationMode).thenAnswer((_) async => true);
    when(sysfs.readRapidChargingMode).thenAnswer((_) async => false);
    when(sysfs.readBatteryPercent).thenAnswer((_) async => 100);
    when(sysfs.readBatteryStatus).thenAnswer((_) async => 'Full');
    when(sysfs.readBatteryPowerDrawW).thenAnswer((_) async => 0);
    when(sysfs.readBatteryCycleCount).thenAnswer((_) async => 87);
    when(sysfs.readBatteryFullCapacityWh).thenAnswer((_) async => 56.8);
    when(sysfs.readBatteryDesignCapacityWh).thenAnswer((_) async => 60);
    when(sysfs.readBatteryCurrentCapacityWh).thenAnswer((_) async => 56.8);
    when(sysfs.readBatteryTempC).thenAnswer((_) async => 27);
    when(sysfs.readAlwaysOnUsbChargingMode).thenAnswer((_) async => true);
    when(sysfs.readBatteryVoltageV).thenAnswer((_) async => 17.3);
    when(sysfs.readBatteryManufacturer).thenAnswer((_) async => 'SMP');
    when(sysfs.readBatteryModelName).thenAnswer((_) async => 'L22M4PC3');
    when(sysfs.readBatterySerialNumber).thenAnswer((_) async => '387');
  });

  test('retains raw status, identity, and read-only USB state', () async {
    final snapshot = await repository.loadSnapshot();

    expect(snapshot.batteryStatus, 'Full');
    expect(snapshot.batteryCharging, isFalse);
    expect(snapshot.manufacturer, 'SMP');
    expect(snapshot.modelName, 'L22M4PC3');
    expect(snapshot.alwaysOnUsbEnabled, isTrue);
    expect(snapshot.alwaysOnUsbSupported, isFalse);
  });

  test('always-on USB write stays guarded', () {
    expect(
      () => repository.setAlwaysOnUsb(false),
      throwsA(
        isA<BatteryRepositoryException>().having(
          (error) => error.message,
          'message',
          contains('read-only'),
        ),
      ),
    );
  });
}
