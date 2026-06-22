import 'package:riverbloc/riverbloc.dart';

import '../../../core/providers/system_services_provider.dart';
import '../bloc/lighting_bloc.dart';
import '../bloc/lighting_event.dart';
import '../bloc/lighting_state.dart';
import '../repository/lighting_repository.dart';
import '../repository/rgb_lighting_repository.dart';
import '../services/openrgb_cli_service.dart';

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

/// The OpenRGB CLI wrapper used for per-key RGB.
final openRgbServiceProvider = Provider<OpenRgbCliService>(
  (ref) => const OpenRgbCliService(),
);

/// High-level keyboard RGB control (over [openRgbServiceProvider]).
final rgbLightingRepositoryProvider = Provider<RgbLightingRepository>(
  (ref) => RgbLightingRepository(service: ref.watch(openRgbServiceProvider)),
);
