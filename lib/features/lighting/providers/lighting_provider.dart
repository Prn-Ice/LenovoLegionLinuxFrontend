import 'package:riverbloc/riverbloc.dart';

import '../../../core/providers/system_services_provider.dart';
import '../bloc/lighting_bloc.dart';
import '../bloc/lighting_event.dart';
import '../bloc/lighting_state.dart';
import '../bloc/rgb_lighting_bloc.dart';
import '../bloc/rgb_lighting_event.dart';
import '../bloc/rgb_lighting_state.dart';
import '../repository/lighting_repository.dart';
import '../repository/rgb_lighting_repository.dart';
import '../repository/spectrum_rgb_repository.dart';
import '../services/openrgb_cli_service.dart';
import '../services/spectrum_effect_engine.dart';

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

/// Native real-time per-key RGB (direct hidraw, no OpenRGB).
final spectrumRgbRepositoryProvider = Provider<SpectrumRgbRepository>(
  (ref) => SpectrumRgbRepository(),
);

/// Software animated-effect engine (drives region effects over the native path).
final spectrumEffectEngineProvider = Provider<SpectrumEffectEngine>((ref) {
  final engine = SpectrumEffectEngine(ref.watch(spectrumRgbRepositoryProvider));
  ref.onDispose(engine.dispose);
  return engine;
});

/// Per-key RGB bloc; auto-loads the keyboard on creation.
final rgbLightingBlocProvider =
    BlocProvider.autoDispose<RgbLightingBloc, RgbLightingState>((ref) {
      final repository = ref.watch(rgbLightingRepositoryProvider);
      final native = ref.watch(spectrumRgbRepositoryProvider);
      return RgbLightingBloc(repository: repository, nativeRepository: native)
        ..add(const RgbLightingStarted());
    });
