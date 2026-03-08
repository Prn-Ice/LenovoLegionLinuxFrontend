import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/battery_devices/bloc/battery_devices_bloc.dart';
import 'package:legion_frontend/features/battery_devices/bloc/battery_devices_event.dart';
import 'package:legion_frontend/features/battery_devices/bloc/battery_devices_state.dart';
import 'package:legion_frontend/features/battery_devices/models/battery_devices_snapshot.dart';
import 'package:legion_frontend/features/battery_devices/repository/battery_devices_repository.dart';
import 'package:mocktail/mocktail.dart';

class MockBatteryDevicesRepository extends Mock
    implements BatteryDevicesRepository {}

void main() {
  late MockBatteryDevicesRepository repo;

  setUp(() {
    repo = MockBatteryDevicesRepository();
    when(() => repo.loadSnapshot()).thenAnswer(
      (_) async => const BatteryDevicesSnapshot(
        batteryConservationEnabled: true,
        rapidChargingEnabled: null,
        alwaysOnUsbChargingEnabled: null,
        alwaysOnUsbWriteSupported: false,
        touchpadEnabled: null,
        winKeyEnabled: null,
        cameraPowerEnabled: null,
        fnLockEnabled: null,
      ),
    );
  });

  group('BatteryDevicesBloc BatteryDevicesTicked', () {
    blocTest<BatteryDevicesBloc, BatteryDevicesState>(
      'BatteryDevicesTicked reloads silently when not applying',
      build: () => BatteryDevicesBloc(repository: repo),
      seed: () => BatteryDevicesState.initial(),
      act: (bloc) => bloc.add(const BatteryDevicesTicked()),
      expect: () => [
        isA<BatteryDevicesState>().having(
          (s) => s.isLoading,
          'isLoading',
          false,
        ),
      ],
    );

    blocTest<BatteryDevicesBloc, BatteryDevicesState>(
      'BatteryDevicesTicked is skipped when isApplying',
      build: () => BatteryDevicesBloc(repository: repo),
      seed: () => BatteryDevicesState.initial().copyWith(isApplying: true),
      act: (bloc) => bloc.add(const BatteryDevicesTicked()),
      expect: () => isEmpty,
    );
  });
}
