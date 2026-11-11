import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/control_mode.dart';
import '../../../core/providers/system_services_provider.dart';
import '../../../core/widgets/privileged_action_notice.dart';
import '../bloc/settings_event.dart';
import '../providers/settings_provider.dart';

/// Saves the next-launch choice while this app session keeps its current mode.
class HardwareAccessControls extends ConsumerWidget {
  const HardwareAccessControls({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(settingsBlocProvider);
    final available = ref.watch(portableControlAvailableProvider);
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Hardware access', style: textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final mode in ControlMode.values)
              _ModeChip(
                label: mode.label,
                selected: state.nextControlMode == mode,
                onSelected:
                    state.isSavingControlMode ||
                        (mode == ControlMode.temporaryHelper && !available)
                    ? null
                    : () async {
                        if (ref.read(settingsBlocProvider).nextControlMode ==
                            mode) {
                          return;
                        }
                        if (mode == ControlMode.temporaryHelper) {
                          final confirmed = await confirmPrivilegedAction(
                            context,
                            title: 'Use a temporary helper?',
                            message:
                                'After you reopen the app, hardware changes may ask for administrator approval. Access ends when the app closes or after 15 minutes idle. Persistent services and boot-time changes require installed integration.',
                            confirmLabel: 'Use on next launch',
                          );
                          if (!context.mounted || !confirmed) return;
                        }
                        final current = ref.read(settingsBlocProvider);
                        if (current.isSavingControlMode ||
                            (mode == ControlMode.temporaryHelper &&
                                !ref.read(portableControlAvailableProvider))) {
                          return;
                        }
                        ref
                            .read(settingsBlocProvider.bloc)
                            .add(ControlModeChanged(mode));
                      },
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          state.isSavingControlMode
              ? "Saving hardware access preference…"
              : state.nextControlMode == state.activeControlMode
              ? 'Current session: ${state.activeControlMode.label}. Changes apply when you reopen the app.'
              : 'Current session: ${state.activeControlMode.label}. Reopen the app to use ${state.nextControlMode.label}.',
          style: textTheme.bodySmall,
        ),
        if (!available) ...[
          const SizedBox(height: 4),
          const Text(
            'Temporary hardware control is not available in this build.',
          ),
        ],

        const SizedBox(height: 8),
        const Text(
          'Keyboard permissions and optional power telemetry are set up separately.',
        ),
      ],
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });
  final String label;
  final bool selected;
  final VoidCallback? onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: scheme.primary,
      labelStyle: selected ? TextStyle(color: scheme.onPrimary) : null,
      checkmarkColor: scheme.onPrimary,
      onSelected: onSelected == null ? null : (_) => onSelected!(),
    );
  }
}
