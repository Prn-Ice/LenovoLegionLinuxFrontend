import 'package:riverbloc/riverbloc.dart';

import '../../../core/providers/system_services_provider.dart';
import '../bloc/display_lighting_bloc.dart';
import '../bloc/display_lighting_event.dart';
import '../bloc/display_lighting_state.dart';
import '../repository/display_lighting_repository.dart';

final displayLightingRepositoryProvider = Provider<DisplayLightingRepository>((
  ref,
) {
  final sysfsService = ref.watch(legionSysfsServiceProvider);
  final bridgeService = ref.watch(legionBridgeServiceProvider);
  final xrandrService = ref.watch(xrandrServiceProvider);

  return DisplayLightingRepository(
    sysfsService: sysfsService,
    bridgeService: bridgeService,
    xrandrService: xrandrService,
  );
});

final displayLightingBlocProvider =
    BlocProvider.autoDispose<DisplayLightingBloc, DisplayLightingState>((ref) {
      final repository = ref.watch(displayLightingRepositoryProvider);
      return DisplayLightingBloc(repository: repository)
        ..add(const DisplayLightingStarted());
    });
