import 'package:riverbloc/riverbloc.dart';

import '../../dashboard/providers/dashboard_provider.dart';
import '../../lighting/bloc/rgb_lighting_event.dart';
import '../../lighting/providers/lighting_provider.dart';
import '../models/automation_config.dart';
import 'automation_provider.dart';

// Include the mode in the value: two modes may deliberately use the same
// profile. Unrelated telemetry and navigation must not reapply it.
final activeKeyboardAssignmentProvider =
    Provider<({KeyboardPowerMode? mode, String? profile})>((ref) {
      final config = ref.watch(automationBlocProvider);
      final rawMode = ref.watch(
        dashboardBlocProvider.select(
          (state) => state.snapshot.status.powerProfile,
        ),
      );
      final mode = KeyboardPowerMode.fromPlatformProfile(rawMode);
      return (
        mode: mode,
        profile: config.hasLoaded ? config.config.profiles[mode] : null,
      );
    });

/// The shell retains this wiring, so assignments and animations outlive pages.
final automationRuntimeProvider = Provider.autoDispose<void>((ref) {
  ref.listen(activeKeyboardAssignmentProvider, (previous, next) {
    if (previous == next || next.profile == null) return;
    ref.read(rgbLightingBlocProvider.bloc).add(RgbProfileLoaded(next.profile!));
  }, fireImmediately: true);
});
