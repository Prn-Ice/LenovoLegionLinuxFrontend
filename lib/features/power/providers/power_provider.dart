import 'package:riverbloc/riverbloc.dart';

import '../../../core/providers/system_services_provider.dart';
import '../bloc/power_bloc.dart';
import '../bloc/power_event.dart';
import '../bloc/power_state.dart';
import '../repository/power_repository.dart';

final powerRepositoryProvider = Provider<PowerRepository>((ref) {
  final sysfsService = ref.watch(legionSysfsServiceProvider);
  final cliService = ref.watch(legionCliServiceProvider);

  return PowerRepository(sysfsService: sysfsService, cliService: cliService);
});

final powerBlocProvider = BlocProvider.autoDispose<PowerBloc, PowerState>((
  ref,
) {
  final repository = ref.watch(powerRepositoryProvider);
  return PowerBloc(repository: repository)..add(const PowerStarted());
});
