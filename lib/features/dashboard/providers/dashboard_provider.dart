import 'package:riverbloc/riverbloc.dart';

import '../../../core/providers/system_services_provider.dart';
import '../bloc/dashboard_bloc.dart';
import '../bloc/dashboard_event.dart';
import '../bloc/dashboard_state.dart';
import '../repository/dashboard_repository.dart';

final dashboardRepositoryProvider = Provider<DashboardRepository>((ref) {
  final sysfsService = ref.watch(legionSysfsServiceProvider);
  final bridgeService = ref.watch(legionBridgeServiceProvider);
  return DashboardRepository(
    sysfsService: sysfsService,
    bridgeService: bridgeService,
  );
});

final dashboardBlocProvider =
    BlocProvider.autoDispose<DashboardBloc, DashboardState>((ref) {
      final repository = ref.watch(dashboardRepositoryProvider);
      return DashboardBloc(repository: repository)
        ..add(const DashboardStarted());
    });
