import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    final textTheme = Theme.of(context).textTheme;

    if (state.isLoading && !state.hasLoaded) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Display & Lighting', style: textTheme.headlineMedium),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Hybrid / G-Sync', style: textTheme.titleLarge),
                const SizedBox(height: 8),
                const Text('Changes take full effect after reboot.'),
                const SizedBox(height: 12),
                const PrivilegedActionNotice(),
                const SizedBox(height: 8),
                if (state.errorMessage != null) ...[
                  Text(
                    state.errorMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                if (state.noticeMessage != null) ...[
                  Text(
                    state.noticeMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                SwitchListTile.adaptive(
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
                  title: const Text('Hybrid mode'),
                  subtitle: Text(
                    state.hybridModeSupported
                        ? ((state.hybridModeEnabled ?? false)
                              ? 'Enabled'
                              : 'Disabled')
                        : 'Not supported on this device',
                  ),
                ),
                const Divider(),
                Text('Overdrive', style: textTheme.titleLarge),
                const SizedBox(height: 8),
                const Text('Display overdrive control (panel-dependent).'),
                SwitchListTile.adaptive(
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
                  title: const Text('Overdrive'),
                  subtitle: Text(
                    state.overdriveSupported
                        ? ((state.overdriveEnabled ?? false)
                              ? 'Enabled'
                              : 'Disabled')
                        : 'Not supported on this device',
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: state.isLoading || state.isApplying
                      ? null
                      : () => bloc.add(const DisplayLightingRefreshRequested()),
                  icon: state.isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  label: const Text('Refresh'),
                ),
              ],
            ),
          ),
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
