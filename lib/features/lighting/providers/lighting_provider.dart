import 'package:riverbloc/riverbloc.dart';

import '../../../core/providers/system_services_provider.dart';
import '../bloc/lighting_bloc.dart';
import '../bloc/lighting_event.dart';
import '../bloc/lighting_state.dart';
import '../repository/lighting_repository.dart';

final lightingRepositoryProvider = Provider<LightingRepository>((ref) {
  final sysfsService = ref.watch(legionSysfsServiceProvider);
  final bridgeService = ref.watch(legionBridgeServiceProvider);

  return LightingRepository(
    sysfsService: sysfsService,
    bridgeService: bridgeService,
  );
});

final lightingBlocProvider =
    BlocProvider.autoDispose<LightingBloc, LightingState>((ref) {
      final repository = ref.watch(lightingRepositoryProvider);
      return LightingBloc(repository: repository)..add(const LightingStarted());
    });
