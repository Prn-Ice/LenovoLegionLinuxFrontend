import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yaru/yaru.dart';

import '../../../core/widgets/app_shell_components.dart';
import '../../../core/widgets/privileged_action_notice.dart';
import '../bloc/display_lighting_bloc.dart';
import '../bloc/display_lighting_event.dart';
import '../providers/display_lighting_provider.dart';

class DisplayLightingPage extends ConsumerWidget {
  const DisplayLightingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(displayLightingBlocProvider);
    final bloc = ref.read(displayLightingBlocProvider.bloc);

    if (state.isLoading && !state.hasLoaded) {
      return const Center(child: YaruCircularProgressIndicator());
    }

    return AppPageBody(
      title: 'Display & Lighting',
      errorMessage: state.errorMessage,
      noticeMessage: state.noticeMessage,
      children: [
        AppSectionCard(
          title: 'Hybrid / G-Sync',
          description: 'Changes take full effect after reboot.',
          children: [
            const PrivilegedActionNotice(),
            const SizedBox(height: 8),
            AppSwitchTile(
              value: state.hybridModeEnabled ?? false,
              onChanged: (state.hybridModeSupported && !state.isApplying)
                  ? (enabled) async {
                      final confirmed = await confirmPrivilegedAction(
                        context,
                        title: 'Toggle hybrid mode',
                        message:
                            'Changing hybrid mode uses privileged access and may prompt for authentication.',
                        confirmLabel: 'Apply',
                      );
                      if (!context.mounted || !confirmed) {
                        return;
                      }
                      _setHybridMode(bloc, enabled);
                    }
                  : null,
              title: 'Hybrid mode',
              subtitle: state.hybridModeSupported
                  ? boolEnabledLabel(state.hybridModeEnabled)
                  : 'Not supported on this device',
            ),
          ],
        ),
        const SizedBox(height: 16),
        AppSectionCard(
          title: 'Overdrive',
          description: 'Display overdrive control (panel-dependent).',
          children: [
            AppSwitchTile(
              value: state.overdriveEnabled ?? false,
              onChanged: (state.overdriveSupported && !state.isApplying)
                  ? (enabled) async {
                      final confirmed = await confirmPrivilegedAction(
                        context,
                        title: 'Toggle overdrive',
                        message:
                            'Changing overdrive uses privileged access and may prompt for authentication.',
                        confirmLabel: 'Apply',
                      );
                      if (!context.mounted || !confirmed) {
                        return;
                      }
                      _setOverdriveMode(bloc, enabled);
                    }
                  : null,
              title: 'Overdrive',
              subtitle: state.overdriveSupported
                  ? boolEnabledLabel(state.overdriveEnabled)
                  : 'Not supported on this device',
            ),
          ],
        ),
        const SizedBox(height: 16),
        AppRefreshButton(
          isBusy: state.isLoading,
          onPressed: state.isApplying
              ? null
              : () => bloc.add(const DisplayLightingRefreshRequested()),
        ),
      ],
    );
  }

  void _setHybridMode(DisplayLightingBloc bloc, bool enabled) {
    bloc.add(HybridModeSetRequested(enabled));
  }

  void _setOverdriveMode(DisplayLightingBloc bloc, bool enabled) {
    bloc.add(OverdriveModeSetRequested(enabled));
  }
}
