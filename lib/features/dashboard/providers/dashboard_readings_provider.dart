import 'package:riverbloc/riverbloc.dart';

import '../bloc/dashboard_readings_bloc.dart';
import '../repository/dashboard_readings_store.dart';

// main supplies the opened Hive store; tests can use in-memory choices.
final dashboardReadingsStoreProvider = Provider<DashboardReadingsStore?>(
  (ref) => null,
);

final dashboardReadingsProvider =
    BlocProvider<DashboardReadingsBloc, DashboardReadingsState>((ref) {
      return DashboardReadingsBloc(
        store: ref.watch(dashboardReadingsStoreProvider),
      );
    });
