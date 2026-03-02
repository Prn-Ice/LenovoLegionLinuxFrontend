import 'package:riverbloc/riverbloc.dart';

import '../../../core/providers/system_services_provider.dart';
import '../bloc/battery_devices_bloc.dart';
import '../bloc/battery_devices_event.dart';
import '../bloc/battery_devices_state.dart';
import '../repository/battery_devices_repository.dart';

final batteryDevicesRepositoryProvider = Provider<BatteryDevicesRepository>((
  ref,
) {
  final sysfsService = ref.watch(legionSysfsServiceProvider);
  final bridgeService = ref.watch(legionBridgeServiceProvider);

  return BatteryDevicesRepository(
    sysfsService: sysfsService,
    bridgeService: bridgeService,
  );
});

final batteryDevicesBlocProvider =
    BlocProvider.autoDispose<BatteryDevicesBloc, BatteryDevicesState>((ref) {
      final repository = ref.watch(batteryDevicesRepositoryProvider);
      return BatteryDevicesBloc(repository: repository)
        ..add(const BatteryDevicesStarted());
    });
