import 'package:riverbloc/riverbloc.dart';

import '../../../core/providers/system_services_provider.dart';
import '../bloc/battery_bloc.dart';
import '../bloc/battery_event.dart';
import '../bloc/battery_state.dart';
import '../repository/battery_repository.dart';

final batteryRepositoryProvider = Provider<BatteryRepository>((ref) {
  final sysfsService = ref.watch(legionSysfsServiceProvider);
  final bridgeService = ref.watch(legionBridgeServiceProvider);

  return BatteryRepository(
    sysfsService: sysfsService,
    bridgeService: bridgeService,
  );
});

final batteryBlocProvider =
    BlocProvider.autoDispose<BatteryBloc, BatteryState>((ref) {
      final repository = ref.watch(batteryRepositoryProvider);
      return BatteryBloc(repository: repository)..add(const BatteryStarted());
    });
