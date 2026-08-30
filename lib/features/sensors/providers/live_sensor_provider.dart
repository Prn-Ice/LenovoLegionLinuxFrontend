import 'package:riverbloc/riverbloc.dart';

import '../../../core/providers/system_services_provider.dart';
import '../bloc/live_sensor_bloc.dart';
import '../bloc/live_sensor_state.dart';
import '../repository/live_sensor_repository.dart';

final _liveSensorRepositoryProvider = Provider<LiveSensorRepository>((ref) {
  return LiveSensorRepository(
    sysfsService: ref.watch(legionSysfsServiceProvider),
    nvidiaSmiService: ref.watch(nvidiaSmiServiceProvider),
    packagePowerTelemetryClient: ref.watch(packagePowerTelemetryClientProvider),
  );
});

final liveSensorBlocProvider =
    BlocProvider.autoDispose<LiveSensorBloc, LiveSensorState>((ref) {
      return LiveSensorBloc(
        repository: ref.watch(_liveSensorRepositoryProvider),
      );
    });
