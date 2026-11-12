import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yaru/yaru.dart';

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
    final canChooseMode =
        available ||
        state.nextControlMode == ControlMode.temporaryHelper ||
        state.activeControlMode == ControlMode.temporaryHelper;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Permission to change settings', style: textTheme.titleSmall),
        const SizedBox(height: 8),
        const Text(
          'Changing fan, power, battery, or graphics settings may require administrator approval.',
        ),
        const SizedBox(height: 8),
        if (canChooseMode) ...[
          const Text(
            'Installed service sends changes to a background program already installed on your system. '
            'Temporary helper starts a program just for this app session, without installing a system service.',
          ),
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
                                  'After you close and reopen the app, the first hardware change may ask for administrator approval. '
                                  'The helper stops when you close the app or after 15 minutes without a request from the app. '
                                  'Stopping it does not undo changes already made. '
                                  'It cannot manage background services or graphics changes scheduled for the next boot.',
                              confirmLabel: 'Use on next launch',
                            );
                            if (!context.mounted || !confirmed) return;
                          }
                          final current = ref.read(settingsBlocProvider);
                          if (current.isSavingControlMode ||
                              (mode == ControlMode.temporaryHelper &&
                                  !ref.read(
                                    portableControlAvailableProvider,
                                  ))) {
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
                ? 'Saving your choice…'
                : state.nextControlMode == state.activeControlMode
                ? 'In use now: ${state.activeControlMode.label}. A different choice takes effect after you close and reopen the app.'
                : 'In use now: ${state.activeControlMode.label}. Close and reopen the app to use ${state.nextControlMode.label}.',
            style: textTheme.bodySmall,
          ),
          if (!available) ...[
            const SizedBox(height: 4),
            const Text(
              'The temporary helper is not included in this version of the app. Choose Installed service for the next launch.',
            ),
          ],
        ] else
          const Text(
            'This version sends approved changes to the Legion control service, a background program that must be installed on your system.',
          ),
        const SizedBox(height: 12),
        YaruExpandable(
          isExpanded: false,
          expandIconSemanticLabel: 'Toggle other hardware permissions',
          expandButtonPosition: YaruExpandableButtonPosition.end,
          header: const Text('Other hardware permissions'),
          child: const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'This setting does not grant access to keyboard lighting or CPU power readings. '
              'Those features need separate device permissions or services.',
            ),
          ),
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
