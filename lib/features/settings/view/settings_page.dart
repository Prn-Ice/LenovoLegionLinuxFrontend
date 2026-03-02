import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_shell_components.dart';
import '../../../core/widgets/privileged_action_notice.dart';
import '../bloc/settings_event.dart';
import '../models/service_control.dart';
import '../providers/settings_provider.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(settingsBlocProvider);
    final bloc = ref.read(settingsBlocProvider.bloc);

    if (state.isLoading && !state.hasLoaded) {
      return const Center(child: CircularProgressIndicator());
    }

    return AppPageBody(
      title: 'Settings',
      errorMessage: state.errorMessage,
      noticeMessage: state.noticeMessage,
      children: [
        AppSectionCard(
          title: 'System Services',
          description:
              'Enable or disable Linux service dependencies used by Legion tooling.',
          children: [
            const PrivilegedActionNotice(),
            const SizedBox(height: 8),
            if (state.services.isEmpty)
              const Text('No service controls available.'),
            ...state.services.map(
              (service) => _ServiceTile(
                service: service,
                isBusy: state.isApplying,
                onChanged: (enabled) async {
                  final confirmed = await confirmPrivilegedAction(
                    context,
                    title: 'Update ${service.label}',
                    message:
                        'Changing Linux services uses privileged access and may prompt for authentication.',
                    confirmLabel: 'Apply',
                  );
                  if (!context.mounted || !confirmed) {
                    return;
                  }
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
        const SizedBox(height: 16),
        AppRefreshButton(
          isBusy: state.isLoading,
          onPressed: state.isApplying
              ? null
              : () => bloc.add(const SettingsRefreshRequested()),
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
    return AppSwitchTile(
      value: service.targetEnabled,
      onChanged: service.supported && !isBusy ? onChanged : null,
      title: service.label,
      subtitle: _subtitle(service),
    );
  }

  String _subtitle(ServiceControl service) {
    if (!service.supported) {
      return 'Not available on this system';
    }

    final runtime = service.active ? 'running' : 'stopped';
    final boot = service.enabled ? 'enabled' : 'disabled';
    return '$runtime, $boot at boot • admin action';
  }
}
