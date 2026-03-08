// lib/features/analytics/providers/analytics_provider.dart
import 'package:riverbloc/riverbloc.dart';

import '../../../core/providers/system_services_provider.dart';
import '../bloc/analytics_bloc.dart';
import '../bloc/analytics_state.dart';
import '../repository/analytics_repository.dart';

final analyticsRepositoryProvider = Provider<AnalyticsRepository>((ref) {
  return AnalyticsRepository(
    sysfsService: ref.watch(legionSysfsServiceProvider),
    box: ref.watch(sensorRecordBoxProvider),
  );
});

final analyticsBlocProvider = BlocProvider<AnalyticsBloc, AnalyticsState>((
  ref,
) {
  return AnalyticsBloc(repository: ref.watch(analyticsRepositoryProvider));
});
