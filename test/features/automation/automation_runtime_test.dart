import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/automation/bloc/automation_event.dart';
import 'package:legion_frontend/features/automation/models/automation_config.dart';
import 'package:legion_frontend/features/automation/providers/automation_provider.dart';
import 'package:legion_frontend/features/automation/providers/automation_runtime_provider.dart';
import 'package:legion_frontend/features/dashboard/bloc/dashboard_event.dart';
import 'package:legion_frontend/features/dashboard/providers/dashboard_provider.dart';
import 'package:legion_frontend/features/lighting/bloc/rgb_lighting_event.dart';
import 'package:legion_frontend/features/lighting/providers/lighting_provider.dart';
import '../../support/keyboard_automation_fakes.dart';

void main() {
  test(
    'default assignments do not initialize or write to the keyboard',
    () async {
      final container = ProviderContainer(
        overrides: [
          automationRepositoryProvider.overrideWithValue(MemoryAssignments()),
          dashboardRepositoryProvider.overrideWithValue(ObservedPowerMode()),
          rgbLightingRepositoryProvider.overrideWith(
            (ref) => throw StateError(
              'Unassigned modes must not initialize lighting',
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.listen(automationRuntimeProvider, (_, _) {});
      await container
          .read(automationBlocProvider.bloc)
          .stream
          .firstWhere((s) => s.hasLoaded);
      await container.pump();
      expect(container.read(activeKeyboardAssignmentProvider).profile, isNull);
      expect(container.exists(rgbLightingBlocProvider), isFalse);
    },
  );

  test(
    'shell lifetime applies external modes once and keeps Lighting alive across page disposal',
    () async {
      final assignments = MemoryAssignments()
        ..config = AutomationConfig(
          profiles: {
            KeyboardPowerMode.balanced: 'Night',
            KeyboardPowerMode.performance: 'Gaming',
          },
        );
      final power = ObservedPowerMode();
      final keyboard = RecordingKeyboard();
      final container = ProviderContainer(
        overrides: [
          automationRepositoryProvider.overrideWithValue(assignments),
          dashboardRepositoryProvider.overrideWithValue(power),
          rgbLightingRepositoryProvider.overrideWithValue(keyboard),
          spectrumRgbRepositoryProvider.overrideWithValue(NoNativeKeyboard()),
          rgbLightingStoreProvider.overrideWithValue(MemoryLightingProfiles()),
        ],
      );
      final shell = container.listen(automationRuntimeProvider, (_, _) {});
      final lighting = container.read(rgbLightingBlocProvider.bloc);
      await lighting.stream.firstWhere(
        (s) => s.brightness == 40 && !s.isApplying,
      );
      expect(keyboard.writes, hasLength(1));
      final page = container.listen(rgbLightingBlocProvider, (_, _) {});
      page.close();
      await container.pump();
      expect(lighting.isClosed, isFalse);

      Future<void> observe(String? mode) async {
        power.mode = mode;
        final dashboard = container.read(dashboardBlocProvider.bloc);
        final read = dashboard.stream.firstWhere((s) => !s.isLoading);
        dashboard.add(const DashboardRefreshRequested());
        await read;
        await container.pump();
      }

      await observe('balanced');
      expect(keyboard.writes, hasLength(1));
      final gaming = lighting.stream.firstWhere(
        (s) => s.brightness == 90 && !s.isApplying,
      );
      await observe('performance');
      await gaming;
      expect(keyboard.writes, hasLength(2));
      await observe('quiet');
      expect(keyboard.writes, hasLength(2));

      // Assigning the currently observed mode applies after the save succeeds.
      final night = lighting.stream.firstWhere(
        (s) => s.brightness == 40 && !s.isApplying,
      );
      container
          .read(automationBlocProvider.bloc)
          .add(const KeyboardProfileAssigned(KeyboardPowerMode.quiet, 'Night'));
      await night;
      expect(keyboard.writes, hasLength(3));

      // Deleting an assigned profile does not crash or silently claim success.
      final deleted = lighting.stream.firstWhere(
        (s) => !s.profileNames.contains('Night'),
      );
      lighting.add(const RgbProfileDeleted('Night'));
      await deleted;
      await observe('unknown');
      final failure = lighting.stream.firstWhere((s) => s.errorMessage != null);
      await observe('quiet');
      await failure;
      expect(keyboard.writes, hasLength(3));
      shell.close();
      container.dispose();
    },
  );
}
