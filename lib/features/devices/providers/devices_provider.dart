import 'package:riverbloc/riverbloc.dart';

import '../../../core/providers/system_services_provider.dart';
import '../bloc/devices_bloc.dart';
import '../bloc/devices_event.dart';
import '../bloc/devices_state.dart';
import '../repository/devices_repository.dart';

final devicesRepositoryProvider = Provider<DevicesRepository>((ref) {
  final sysfsService = ref.watch(legionSysfsServiceProvider);
  final bridgeService = ref.watch(legionBridgeServiceProvider);

  return DevicesRepository(
    sysfsService: sysfsService,
    bridgeService: bridgeService,
  );
});

final devicesBlocProvider =
    BlocProvider.autoDispose<DevicesBloc, DevicesState>((ref) {
      final repository = ref.watch(devicesRepositoryProvider);
      return DevicesBloc(repository: repository)..add(const DevicesStarted());
    });
