import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bloc/settings_event.dart';
import '../models/service_control.dart';
import '../providers/settings_provider.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(settingsBlocProvider);
    final bloc = ref.read(settingsBlocProvider.bloc);
    final textTheme = Theme.of(context).textTheme;

    if (state.isLoading && !state.hasLoaded) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Settings', style: textTheme.headlineMedium),
        const SizedBox(height: 16),
        if (state.errorMessage != null) ...[
          Text(
            state.errorMessage!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          const SizedBox(height: 8),
        ],
        if (state.noticeMessage != null) ...[
          Text(
            state.noticeMessage!,
            style: TextStyle(color: Theme.of(context).colorScheme.primary),
          ),
          const SizedBox(height: 8),
        ],
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('System Services', style: textTheme.titleLarge),
                const SizedBox(height: 8),
                const Text(
                  'Enable or disable Linux service dependencies used by Legion tooling.',
                ),
                const SizedBox(height: 12),
                if (state.services.isEmpty)
                  const Text('No service controls available.'),
                ...state.services.map(
                  (service) => _ServiceTile(
                    service: service,
                    isBusy: state.isApplying,
                    onChanged: (enabled) {
                      bloc.add(
                        SettingsServiceToggled(
                          serviceId: service.id,
                          enabled: enabled,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: state.isLoading || state.isApplying
              ? null
              : () => bloc.add(const SettingsRefreshRequested()),
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
    );
  }
}

class _ServiceTile extends StatelessWidget {
  const _ServiceTile({
    required this.service,
    required this.isBusy,
    required this.onChanged,
  });

  final ServiceControl service;
  final bool isBusy;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile.adaptive(
      value: service.targetEnabled,
      onChanged: service.supported && !isBusy ? onChanged : null,
      title: Text(service.label),
      subtitle: Text(_subtitle(service)),
    );
  }

  String _subtitle(ServiceControl service) {
    if (!service.supported) {
      return 'Not available on this system';
    }

    final runtime = service.active ? 'running' : 'stopped';
    final boot = service.enabled ? 'enabled' : 'disabled';
    return '$runtime, $boot at boot';
  }
}
